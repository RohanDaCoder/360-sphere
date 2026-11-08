import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';
import 'psv_bridge.dart';

/// Fullscreen immersive 360° viewer (Photo Sphere Viewer in a WebView),
/// matching the original app's viewing experience.
class SphereViewerScreen extends StatefulWidget {
  const SphereViewerScreen({super.key, required this.imagePath, this.title});

  /// Path to the equirectangular JPEG.
  final String imagePath;

  /// Optional caption (sphere name).
  final String? title;

  @override
  State<SphereViewerScreen> createState() => _SphereViewerScreenState();
}

class _SphereViewerScreenState extends State<SphereViewerScreen> {
  final PsvBridge _bridge = PsvBridge();
  late final WebViewController _controller;
  late final Future<void> _loaded;

  @override
  void initState() {
    super.initState();
    _controller = _bridge.build();
    _bridge.onState = (s, d) {
      if (!mounted) return;
      if (s == ViewerState.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Viewer error: ${d ?? "unknown"}')),
        );
      }
    };
    _loaded = () async {
      final bytes = await readFileBytes(widget.imagePath);
      await _bridge.showImage(bytes);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.55),
        title: Text(widget.title ?? '360° Viewer',
            style: const TextStyle(fontSize: 18)),
        actions: [
          FutureBuilder<void>(
            future: _loaded,
            builder: (context, snap) {
              final ready = _bridge.state == ViewerState.loaded;
              return IconButton(
                onPressed: ready ? _toggleGyro : null,
                icon: const Icon(Icons.threed_rotation),
                tooltip: 'Toggle gyroscope',
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          FutureBuilder<void>(
            future: _loaded,
            builder: (context, snap) {
              final done = snap.connectionState == ConnectionState.done &&
                  _bridge.state == ViewerState.loaded;
              if (done) return const SizedBox.shrink();
              return const Positioned.fill(
                child: ColoredBox(
                  color: AppTheme.bg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.accent),
                        SizedBox(height: 16),
                        Text('Loading 360° photo…',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGyro() async {
    await _bridge.setGyro(true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Gyroscope mode requested — allow motion access if prompted.')),
      );
    }
  }
}
