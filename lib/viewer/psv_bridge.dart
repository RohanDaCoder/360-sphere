import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Status of the viewer bridge.
enum ViewerState { loading, ready, streaming, loaded, failed }

/// Bridges a JPEG equirectangular photo into the bundled Photo Sphere
/// Viewer page. The image is streamed as base64 chunks because the page is
/// loaded from Flutter assets (no file:// access to app documents).
class PsvBridge {
  PsvBridge({this.onState});

  /// State callback; replaceable.
  void Function(ViewerState state, String? detail)? onState;

  WebViewController? _controller;
  final Completer<void> _pageReady = Completer<void>();
  ViewerState _state = ViewerState.loading;
  String? _error;

  ViewerState get state => _state;
  String? get error => _error;

  /// Build the controller for [SphereViewerScreen].
  WebViewController build() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('PsvBridge', onMessageReceived: _onMessage)
      ..setBackgroundColor(const Color(0xFF101214))
      ..loadFlutterAsset('assets/viewer/viewer.html');
    _controller = c;
    return c;
  }

  void _onMessage(JavaScriptMessage msg) {
    final body = msg.message;
    if (body == 'ready') {
      if (!_pageReady.isCompleted) _pageReady.complete();
      _setState(ViewerState.ready, null);
    } else if (body == 'loaded') {
      _setState(ViewerState.loaded, null);
    } else if (body.startsWith('error:')) {
      _error = body.substring(6);
      _setState(ViewerState.failed, _error);
    }
  }

  void _setState(ViewerState s, String? detail) {
    _state = s;
    onState?.call(s, detail);
  }

  /// Push [jpegBytes] into the page in chunks and finalize.
  Future<void> showImage(Uint8List jpegBytes) async {
    final controller = _controller;
    if (controller == null) return;
    await _pageReady.future.timeout(const Duration(seconds: 15));

    _setState(ViewerState.streaming, null);
    final b64 = base64Encode(jpegBytes);
    const chunkSize = 512 * 1024;
    final total = (b64.length / chunkSize).ceil();

    for (var i = 0; i < total; i++) {
      final start = i * chunkSize;
      final end = start + chunkSize > b64.length ? b64.length : start + chunkSize;
      final part = b64.substring(start, end);
      await controller.runJavaScript(
          'window.appendChunk($i, $total, "${_escape(part)}")');
    }
    await controller.runJavaScript('window.finalizeImage()');
  }

  Future<void> setGyro(bool enabled) async {
    await _controller?.runJavaScript('window.setGyro($enabled)');
  }

  static String _escape(String js) =>
      js.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll("'", r"\'");
}

/// Reads a file as bytes without dart:io clutter at call sites.
Future<Uint8List> readFileBytes(String path) async {
  final f = File(path);
  return Uint8List.fromList(await f.readAsBytes());
}
