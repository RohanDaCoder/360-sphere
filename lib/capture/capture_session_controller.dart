import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/models.dart';
import '../core/settings.dart';
import '../core/sphere_repository.dart';
import 'dots/capture_dots.dart';
import 'dots/dot_capture_director.dart';
import 'orientation/orientation_tracker.dart';
import 'orientation/original_orientation_filter.dart';
import 'orientation/quaternion.dart';
import 'stitching/equirect_projection.dart';
import 'stitching/equirect_stitcher.dart';
import 'stitching/frame_utils.dart';
import 'stitching/xmp_pano.dart';

/// States of a capture session.
enum CapturePhase { idle, previewing, capturing, processing, done, failed }

/// The original app's processing screen reports a four-step pipeline
/// ("Stitching... Step X/4", last step labelled "Finishing"). The local
/// equivalents here: composite → encode → thumbnail → store.
enum ProcessingStep { composite, encode, thumbnail, store }

/// Orchestrates one photosphere capture:
/// camera → gyro-oriented frames → Skia equirect stitcher → saved sphere.
///
/// Mirrors the original app's capture flow: a dot-target layout guides the
/// sweep (hold the phone on each dot to auto-capture, or tap the shutter),
/// followed by a "Stitching" pass that finalizes the equirect image.
class CaptureSessionController extends ChangeNotifier {
  CaptureSessionController({
    required this.settings,
    required this.repository,
    required CameraController camera,
  }) : _camera = camera;

  final Settings settings;
  final SphereRepository repository;
  final CameraController _camera;

  final OrientationTracker _tracker = OrientationTracker();

  /// Dart port of the original app's native OrientationAngle module —
  /// camera-pose euler angles with ±25° yaw-jump clamping and a 0.8
  /// low-pass filter, feeding the dot director exactly like the original.
  final OriginalOrientationFilter originalFilter = OriginalOrientationFilter();
  EquirectStitcher? _stitcher;
  CoverageTracker? _coverage;
  FrameProjector? _projector;

  /// Dot-target guidance director (the original app's capture worklet).
  DotCaptureDirector? director;

  CaptureMode mode = CaptureMode.photosphere;
  CapturePhase phase = CapturePhase.idle;
  String? error;

  /// Latest device orientation (device → world).
  Quaternion orientation = Quaternion.identity;

  /// Equirectangular live preview of the stitch so far.
  ui.Image? previewImage;

  double get coverageFraction => _coverage?.fraction ?? 0;
  CoverageTracker? get coverage => _coverage;

  /// Next suggested aim (heading, elevation) in radians (fallback guidance
  /// when no director is active).
  (double, double)? nextGap;
  int capturedFrames = 0;

  /// Session progress across the dot layout.
  int get dotTotal => director?.dots.length ?? 0;
  int get dotCaptured => director?.capturedCount ?? 0;

  /// Result of the last finished session.
  Photosphere? result;

  /// Current step of the finishing pipeline (1–4), like the original's
  /// "Stitching... Step X/4" progress.
  int processingStep = 0;
  static const int processingStepCount = 4;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  Timer? _autoTimer;
  final Stopwatch _dt = Stopwatch();
  bool _busy = false;
  double? _angVelDegPerSec;
  int _queuedDotId = -1;

  Future<void> start() async {
    try {
      phase = CapturePhase.previewing;
      error = null;
      result = null;
      capturedFrames = 0;
      previewImage = null;
      processingStep = 0;
      _tracker.reset();
      originalFilter.reset();
      _angVelDegPerSec = null;
      _queuedDotId = -1;
      _stitcher = EquirectStitcher(
        width: settings.equirectWidth,
        height: settings.equirectHeight,
      );
      _coverage = CoverageTracker(fullSphere: mode.wantsFullSphere)..reset();
      _projector = FrameProjector();
      director = (DotCaptureDirector(
        dots: CaptureDots.layout(
          mode,
          cameraFovDeg: settings.cameraFovDegrees,
          includeFloor: settings.includeFloorCapture,
        ),
      ))
        ..floorEnabled = settings.includeFloorCapture
        ..reset();
      _dt.reset();
      _dt.start();

      await _gyroSub?.cancel();
      await _accelSub?.cancel();
      await _magSub?.cancel();
      _gyroSub = gyroscopeEventStream().listen(_onGyro);
      _accelSub = accelerometerEventStream().listen(_onAccel);
      _magSub = magnetometerEventStream().listen(_onMag);

      if (!_camera.value.isInitialized) {
        await _camera.initialize();
      }
      await _camera.resumePreview();
      notifyListeners();
    } on CameraException catch (e) {
      _fail('Camera error: ${e.description ?? e.code}');
    } catch (e) {
      _fail('$e');
    }
  }

  void _onGyro(GyroscopeEvent e) {
    final dt = _dt.elapsedMicroseconds / 1e6;
    _dt
      ..reset()
      ..start();
    if (dt <= 0 || dt > 0.5) return;
    _tracker.updateGyro(dt, e.x, e.y, e.z);
    orientation = _tracker.value;
    final (origYaw, origPitch, origRoll) = originalFilter.update(orientation);

    // Smoothed angular speed (original: FILTER_ALPHA = 0.5).
    final omegaDeg =
        math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) * 180 / math.pi;
    _angVelDegPerSec = _angVelDegPerSec == null
        ? omegaDeg
        : 0.5 * _angVelDegPerSec! + 0.5 * omegaDeg;

    _updateGap();

    // Dot-target guidance while capturing — driven by the original
    // OrientationAngle-module angles (pitch−90 convention, filtered).
    if (phase == CapturePhase.capturing) {
      final d = director;
      if (d != null) {
        final completed = d.update(
          yawDeg: origYaw,
          pitchDeg: origPitch,
          rollDeg: origRoll,
          angularVelocityDegPerSec: _angVelDegPerSec,
        );
        if (completed >= 0) {
          if (_busy) {
            _queuedDotId = completed;
          } else {
            unawaited(_grabFrame(dotId: completed));
          }
        }
      }
    }
    notifyListeners();
  }

  void _onAccel(AccelerometerEvent e) =>
      _tracker.updateAccel(Vector3(e.x, e.y, e.z));

  void _onMag(MagnetometerEvent e) {
    if (settings.compassAssist) {
      _tracker.updateMag(Vector3(e.x, e.y, e.z));
    }
  }

  void _updateGap() {
    final (h, e) = orientation.cameraAim;
    nextGap = _coverage?.nextGap(h, e);
  }

  /// Begin/finish the actual capture phase.
  Future<void> toggleCapture() async {
    if (phase == CapturePhase.previewing) {
      phase = CapturePhase.capturing;
      notifyListeners();
    } else if (phase == CapturePhase.capturing) {
      await finish();
    }
  }

  /// Manually grab one frame (shutter button). Captures the current target
  /// dot when the director is active.
  Future<void> captureFrame() async {
    if (phase != CapturePhase.capturing && phase != CapturePhase.previewing) {
      return;
    }
    if (phase == CapturePhase.previewing) {
      phase = CapturePhase.capturing;
      notifyListeners();
    }
    await _grabFrame(dotId: director?.targetId ?? -1);
  }

  /// Legacy auto-pilot kept for tests; the dot director's hold-to-capture is
  /// the primary flow.
  Future<void> startAutoCapture(
      {Duration interval = const Duration(milliseconds: 800)}) async {
    if (phase == CapturePhase.previewing) {
      phase = CapturePhase.capturing;
      notifyListeners();
    }
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(
        interval, (_) => _grabFrame(dotId: director?.targetId ?? -1));
  }

  void stopAutoCapture() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  Future<void> _grabFrame({int dotId = -1}) async {
    if (_busy || phase != CapturePhase.capturing) return;
    _busy = true;
    try {
      final q = orientation;
      final file = await _camera.takePicture();
      final bytes = await File(file.path).readAsBytes();
      try {
        await File(file.path).delete();
      } catch (_) {}

      final frame = await FrameUtils.decodeUpright(
        bytes,
        maxLongEdge: 1920,
        manualFix: settings.frameRotationFix,
      );

      final cam = FrameCamera(
        fovHDeg: settings.cameraFovDegrees,
        imageWidth: frame.width,
        imageHeight: frame.height,
        projection: mode.usesFisheyeLens
            ? ProjectionModel.fisheye
            : ProjectionModel.pinhole,
      );

      await _stitcher?.addFrame(
        frame: frame,
        orientation: q,
        camera: cam,
        projector: _projector,
      );
      _coverage?.markFrame(q, cam);
      if (dotId >= 0) director?.markCaptured(dotId);
      capturedFrames = _stitcher?.frameCount ?? capturedFrames;
      previewImage = _stitcher?.preview;
      _updateGap();
      notifyListeners();

      // All dots captured → the session finishes itself (the original moves
      // to its Stitching/PROCESSING state the same way).
      if (director != null &&
          director!.allCaptured &&
          phase == CapturePhase.capturing) {
        await finish();
      }
    } on CameraException catch (e) {
      _fail('Camera error: ${e.description ?? e.code}');
    } catch (e) {
      _fail('$e');
    } finally {
      _busy = false;
      // A hold completed while the camera was busy: take it now.
      final queued = _queuedDotId;
      if (queued >= 0 && phase == CapturePhase.capturing) {
        _queuedDotId = -1;
        unawaited(_grabFrame(dotId: queued));
      }
    }
  }

  /// Finish the session: finalize the equirect image and store the sphere.
  ///
  /// Reports progress through the same four steps the original's processing
  /// screen shows ("Stitching... Step X/4" → "Finishing... Step 4/4"):
  /// composite → encode (+ XMP) → thumbnail → store.
  Future<void> finish() async {
    stopAutoCapture();
    if (phase != CapturePhase.capturing) return;
    phase = CapturePhase.processing;
    processingStep = ProcessingStep.composite.index + 1;
    notifyListeners();

    try {
      final stitcher = _stitcher;
      if (stitcher == null || stitcher.frameCount == 0) {
        throw StateError('No frames captured');
      }
      final image = await stitcher.finalize(
        watermark: settings.watermark,
        watermarkText: settings.watermarkLabel,
      );

      processingStep = ProcessingStep.encode.index + 1;
      notifyListeners();
      var jpeg = await FrameUtils.encodeJpeg(image, quality: 90);
      // Stamp the GPano XMP metadata that makes this a real 360° photo for
      // Google Photos / Street View (the original's photos carry it too).
      jpeg = writeGpanoXmp(
        jpeg,
        width: image.width,
        height: image.height,
        captureSoftware: '360Sphere',
      );

      processingStep = ProcessingStep.thumbnail.index + 1;
      notifyListeners();
      final thumb = await FrameUtils.makeThumbnail(image);

      processingStep = ProcessingStep.store.index + 1;
      notifyListeners();
      result = await repository.save(
        name: '360° ${_timestampLabel()}',
        jpeg: jpeg,
        thumb: thumb,
        width: image.width,
        height: image.height,
        frameCount: capturedFrames,
        watermarked: settings.watermark,
      );
      phase = CapturePhase.done;
      notifyListeners();
    } catch (e) {
      _fail('Stitching failed: $e');
    }
  }

  void discard() {
    stopAutoCapture();
    _stitcher?.dispose();
    _stitcher = null;
    phase = CapturePhase.previewing;
    capturedFrames = 0;
    previewImage = null;
    notifyListeners();
  }

  String _timestampLabel() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)} ${two(n.hour)}${two(n.minute)}';
  }

  void _fail(String message) {
    error = message;
    phase = CapturePhase.failed;
    stopAutoCapture();
    debugPrint('[CaptureSession] $message');
    notifyListeners();
  }

  @override
  void dispose() {
    stopAutoCapture();
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _magSub?.cancel();
    _stitcher?.dispose();
    super.dispose();
  }
}
