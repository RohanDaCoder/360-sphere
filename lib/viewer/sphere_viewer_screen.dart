import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';
import 'psv_bridge.dart';

/// Fullscreen immersive 360° viewer (Photo Sphere Viewer in a WebView),
/// matching the original app's viewing experience: Play (autorotate),
/// gyroscope, share, download-to-gallery and delete actions.
class SphereViewerScreen extends StatefulWidget {
  const SphereViewerScreen({
    super.key,
    required this.imagePath,
    this.title,
    this.onShare,
    this.onSave,
    this.onDelete,
  });

  /// Path to the equirectangular JPEG.
  final String imagePath;

  /// Optional caption (sphere name).
  final String? title;

  /// Optional viewer actions (the original exposes Share / Download /
  /// Delete buttons on its viewer screen). When null the button is hidden.
  final Future<void> Function()? onShare;
  final Future<void> Function()? onSave;
  final Future<bool> Function()? onDelete;

  @override
  State<SphereViewerScreen> createState() => _SphereViewerScreenState();
}

class _SphereViewerScreenState extends State<SphereViewerScreen> {
  final PsvBridge _bridge = PsvBridge();
  late final WebViewController _controller;
  late final Future<void> _loaded;

  /// Autorotate starts OFF, matching the original app (its Play button is
  /// what starts the 3rpm rotation).
  bool _autorotate = false;
  bool _gyro = false;

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
              return Row(
                children: [
                  IconButton(
                    onPressed: ready ? _toggleAutorotate : null,
                    icon: Icon(
                        _autorotate ? Icons.pause_circle : Icons.play_circle),
                    tooltip:
                        _autorotate ? 'Pause autorotate' : 'Play (autorotate)',
                  ),
                  IconButton(
                    onPressed: ready ? _toggleGyro : null,
                    icon: Icon(
                      Icons.threed_rotation,
                      color: _gyro ? AppTheme.accent : null,
                    ),
                    tooltip: 'Toggle gyroscope',
                  ),
                  if (widget.onSave != null)
                    IconButton(
                      onPressed: _save,
                      icon: const Icon(Icons.download),
                      tooltip: 'Save to gallery',
                    ),
                  if (widget.onShare != null)
                    IconButton(
                      onPressed: _share,
                      icon: const Icon(Icons.share),
                      tooltip: 'Share',
                    ),
                  if (widget.onDelete != null)
                    IconButton(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                    ),
                ],
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

  Future<void> _toggleAutorotate() async {
    setState(() => _autorotate = !_autorotate);
    await _bridge.setAutorotate(_autorotate);
  }

  Future<void> _toggleGyro() async {
    setState(() => _gyro = !_gyro);
    await _bridge.setGyro(_gyro);
    if (_gyro && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Gyroscope mode requested — allow motion access if prompted.')),
      );
    }
  }

  Future<void> _share() async {
    await widget.onShare?.call();
  }

  Future<void> _save() async {
    await widget.onSave?.call();
  }

  Future<void> _delete() async {
    final deleted = await widget.onDelete?.call() ?? false;
    if (deleted && mounted) Navigator.of(context).pop();
  }
}
