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
import 'orientation/orientation_tracker.dart';
import 'orientation/quaternion.dart';
import 'stitching/equirect_projection.dart';
import 'stitching/equirect_stitcher.dart';
import 'stitching/frame_utils.dart';

/// States of a capture session.
enum CapturePhase { idle, previewing, capturing, processing, done, failed }

/// Orchestrates one photosphere capture:
/// camera → gyro-oriented frames → Skia equirect stitcher → saved sphere.
///
/// Mirrors the original app's capture flow (camera sweep followed by a
/// "Stitching" pass), with the difference that frames are periodic still
/// shots rather than a continuous video stream.
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
  EquirectStitcher? _stitcher;
  CoverageTracker? _coverage;
  FrameProjector? _projector;

  CaptureMode mode = CaptureMode.photosphere;
  CapturePhase phase = CapturePhase.idle;
  String? error;

  /// Latest device orientation (device → world).
  Quaternion orientation = Quaternion.identity;

  /// Equirectangular live preview of the stitch so far.
  ui.Image? previewImage;

  double get coverageFraction => _coverage?.fraction ?? 0;
  CoverageTracker? get coverage => _coverage;

  /// Next suggested aim (heading, elevation) in radians, for the HUD arrow.
  (double, double)? nextGap;
  int capturedFrames = 0;

  /// Result of the last finished session.
  Photosphere? result;

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  Timer? _autoTimer;
  final Stopwatch _dt = Stopwatch();
  bool _busy = false;

  Future<void> start() async {
    try {
      phase = CapturePhase.previewing;
      error = null;
      result = null;
      capturedFrames = 0;
      previewImage = null;
      _tracker.reset();
      _stitcher = EquirectStitcher(
        width: settings.equirectWidth,
        height: settings.equirectHeight,
      );
      _coverage = CoverageTracker(fullSphere: mode.wantsFullSphere)..reset();
      _projector = FrameProjector();
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
    _updateGap();
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

  /// Manually grab one frame (shutter button).
  Future<void> captureFrame() async {
    if (phase != CapturePhase.capturing && phase != CapturePhase.previewing) {
      return;
    }
    if (phase == CapturePhase.previewing) {
      phase = CapturePhase.capturing;
      notifyListeners();
    }
    await _grabFrame();
  }

  /// Auto-pilot: capture a frame roughly every [interval] while the user
  /// sweeps the phone around.
  Future<void> startAutoCapture(
      {Duration interval = const Duration(milliseconds: 800)}) async {
    if (phase == CapturePhase.previewing) {
      phase = CapturePhase.capturing;
      notifyListeners();
    }
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(interval, (_) => _grabFrame());
  }

  void stopAutoCapture() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  Future<void> _grabFrame() async {
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
      );

      await _stitcher?.addFrame(
        frame: frame,
        orientation: q,
        camera: cam,
        projector: _projector,
      );
      _coverage?.markFrame(q, cam);
      capturedFrames = _stitcher?.frameCount ?? capturedFrames;
      previewImage = _stitcher?.preview;
      _updateGap();
      notifyListeners();
    } on CameraException catch (e) {
      _fail('Camera error: ${e.description ?? e.code}');
    } catch (e) {
      _fail('$e');
    } finally {
      _busy = false;
    }
  }

  /// Finish the session: finalize the equirect image and store the sphere.
  Future<void> finish() async {
    stopAutoCapture();
    if (phase != CapturePhase.capturing) return;
    phase = CapturePhase.processing;
    notifyListeners();

    try {
      final stitcher = _stitcher;
      if (stitcher == null || stitcher.frameCount == 0) {
        throw StateError('No frames captured');
      }
      final image = await stitcher.finalize(watermark: settings.watermark);
      final jpeg = await FrameUtils.encodeJpeg(image, quality: 90);
      final thumb = await FrameUtils.makeThumbnail(image);
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

/// Normalize an angle into [0, 2π).
double normalizeAngle(double rad) {
  var r = rad;
  while (r < 0) {
    r += 2 * math.pi;
  }
  while (r >= 2 * math.pi) {
    r -= 2 * math.pi;
  }
  return r;
}
