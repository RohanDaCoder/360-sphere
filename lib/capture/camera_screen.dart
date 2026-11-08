import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/settings.dart';
import '../core/sphere_repository.dart';
import '../core/theme.dart';
import '../gallery/sphere_detail_screen.dart';
import 'capture_session_controller.dart';
import 'widgets/capture_hud.dart';

/// The capture screen: live preview + gyro coverage HUD + shutter,
/// following the original app's camera flow.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  CaptureSessionController? _session;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _session = CaptureSessionController(
          settings: context.read<SettingsController>().settings,
          repository: context.read<SphereRepository>(),
          camera: controller,
        )..start();
      });
    } on CameraException catch (e) {
      setState(() => _cameraError = e.description ?? e.code);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (cam == null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      cam.pausePreview();
    } else if (state == AppLifecycleState.resumed) {
      cam.resumePreview();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.dispose();
    _camera?.dispose();
    super.dispose();
  }

  void _onModeChanged(CaptureMode mode) {
    final s = _session;
    if (s == null || s.mode == mode) return;
    setState(() {
      s.mode = mode;
      s.discard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null || _cameraError != null) {
      return Scaffold(
        backgroundColor: AppTheme.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_camera_outlined,
                    size: 64, color: Colors.white54),
                const SizedBox(height: 16),
                Text(
                  _cameraError ?? 'Starting camera…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                if (_cameraError != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() => _cameraError = null);
                      _initCamera();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Live preview.
            Positioned.fill(child: CameraPreview(_camera!)),

            // Dimming scrim.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                    stops: const [0, 0.25, 0.65, 1],
                  ),
                ),
              ),
            ),

            // Gyro HUD.
            Positioned.fill(child: CaptureHud(controller: session)),

            // Mode chips + session status.
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: _TopBar(session: session, onModeChanged: _onModeChanged),
            ),

            // Bottom controls.
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: _BottomControls(session: session),
            ),

            // Processing / done overlay.
            _ProcessingOverlay(session: session),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session, required this.onModeChanged});

  final CaptureSessionController session;
  final ValueChanged<CaptureMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            for (final m in CaptureMode.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(m.label),
                  selected: session.mode == m,
                  onSelected: (_) => onModeChanged(m),
                ),
              ),
            const Spacer(),
            if (session.phase == CapturePhase.capturing)
              _CoverageBadge(session: session),
          ],
        ),
      ),
    );
  }
}

class _CoverageBadge extends StatelessWidget {
  const _CoverageBadge({required this.session});

  final CaptureSessionController session;

  @override
  Widget build(BuildContext context) {
    final pct = (session.coverageFraction * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          const Icon(Icons.track_changes, size: 16, color: AppTheme.warn),
          const SizedBox(width: 6),
          Text('${session.capturedFrames} frames',
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.session});

  final CaptureSessionController session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final capturing = session.phase == CapturePhase.capturing;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  session.error!,
                  style: const TextStyle(color: AppTheme.warn, fontSize: 12),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () => _showHelp(context),
                  icon: const Icon(Icons.help_outline,
                      color: Colors.white70, size: 28),
                  tooltip: 'How to capture',
                ),
                GestureDetector(
                  onTap: session.captureFrame,
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: capturing
                          ? AppTheme.accent.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                    child:
                        const Icon(Icons.camera, color: Colors.white, size: 36),
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    if (session.phase == CapturePhase.previewing) {
                      await session.startAutoCapture();
                    } else if (session.phase == CapturePhase.capturing) {
                      await session.finish();
                    }
                  },
                  icon: Icon(
                    capturing ? Icons.check_circle : Icons.play_circle,
                    color: capturing ? AppTheme.ok : Colors.white,
                    size: 36,
                  ),
                  tooltip: capturing ? 'Finish & stitch' : 'Start auto sweep',
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Capture a 360° photo',
                style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            Text(
              '1. Tap ▶ to start the auto sweep (or tap the shutter for manual frames).\n'
              '2. Hold the phone upright and pivot slowly around yourself.\n'
              '3. Follow the amber arrow — it points at missing coverage.\n'
              '4. For full spheres, also tilt up toward the sky and down toward the ground.\n'
              '5. Tap ✓ when the ring is mostly orange to stitch and save.',
              style: TextStyle(height: 1.6, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay({required this.session});

  final CaptureSessionController session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (session.phase == CapturePhase.done && session.result != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final result = session.result;
            if (result != null && context.mounted) {
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (_) => SphereDetailScreen(sphereId: result.id),
              ));
            }
          });
          return const SizedBox.shrink();
        }
        if (session.phase != CapturePhase.processing) {
          return const SizedBox.shrink();
        }
        return Container(
          color: Colors.black.withValues(alpha: 0.75),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.accent),
                SizedBox(height: 20),
                Text('Stitching…',
                    style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }
}
