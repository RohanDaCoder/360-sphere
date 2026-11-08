import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../orientation/quaternion.dart';
import 'equirect_projection.dart';

/// Coverage bookkeeping for the capture HUD.
class CoverageTracker {
  CoverageTracker(
      {this.lonBins = 36, this.latBins = 18, this.fullSphere = true});

  final int lonBins;
  final int latBins;
  final bool fullSphere;

  final List<bool> _covered = [];

  /// Latitude rows that count toward coverage. Panorama mode tracks only
  /// the middle third (single horizontal strip).
  int get _firstRow => fullSphere ? 0 : latBins ~/ 3;
  int get _lastRow => fullSphere ? latBins - 1 : 2 * latBins ~/ 3 - 1;

  int get coveredCount => _covered.where((c) => c).length;
  int get totalCount => lonBins * (_lastRow - _firstRow + 1);

  double get fraction {
    if (_covered.isEmpty) return 0;
    return coveredCount / totalCount;
  }

  void markFrame(Quaternion q, FrameCamera cam) {
    _ensure();
    final fwd = q.rotate(FrameCamera.forward).normalized();
    final lon0 = Equirect.lonOf(fwd);
    final lat0 = Equirect.latOf(fwd);
    final r = cam.diagonalFov / 2;
    final cosLat = math.cos(lat0).clamp(0.15, 1.0);
    final rLon = math.min(math.pi, r / cosLat);

    for (var ilat = 0; ilat < latBins; ilat++) {
      // Panorama mode only tracks the horizontal band.
      if (!fullSphere && (ilat < _firstRow || ilat > _lastRow)) continue;
      final lat = -math.pi / 2 + (ilat + 0.5) / latBins * math.pi;
      final dLat = (lat - lat0).abs();
      if (dLat > r) continue;
      for (var ilon = 0; ilon < lonBins; ilon++) {
        final lon = -math.pi + (ilon + 0.5) / lonBins * 2 * math.pi;
        var dLon = (lon - lon0).abs();
        if (dLon > math.pi) dLon = 2 * math.pi - dLon;
        if (dLon <= rLon) {
          _covered[ilat * lonBins + ilon] = true;
        }
      }
    }
  }

  /// Nearest uncovered bin center (lon, lat in radians) to the given aim,
  /// or null when everything is covered.
  (double, double)? nextGap(double headingRad, double elevationRad) {
    _ensure();
    (double, double)? best;
    var bestDist = double.infinity;
    for (var ilat = _firstRow; ilat <= _lastRow; ilat++) {
      final lat = -math.pi / 2 + (ilat + 0.5) / latBins * math.pi;
      for (var ilon = 0; ilon < lonBins; ilon++) {
        if (_covered[ilat * lonBins + ilon]) continue;
        final lon = -math.pi + (ilon + 0.5) / lonBins * 2 * math.pi;
        var dLon = (lon - headingRad).abs();
        if (dLon > math.pi) dLon = 2 * math.pi - dLon;
        final d = math
            .sqrt(dLon * dLon + (lat - elevationRad) * (lat - elevationRad));
        if (d < bestDist) {
          bestDist = d;
          best = (lon, lat);
        }
      }
    }
    return best;
  }

  void reset() => _covered.fillRange(0, _covered.length, false);

  /// Whether the longitude bin [i] (0 = −180°, increasing eastward) has any
  /// coverage — used by the HUD ring.
  bool isLonBinCovered(int i) {
    _ensure();
    for (var j = _firstRow; j <= _lastRow; j++) {
      if (_covered[j * lonBins + i]) return true;
    }
    return false;
  }

  void _ensure() {
    if (_covered.length != lonBins * latBins) {
      _covered.clear();
      _covered.addAll(List.filled(lonBins * latBins, false));
    }
  }
}

/// Accumulates gyro-oriented camera frames onto an equirectangular canvas.
///
/// This mirrors the original app's stitching engine: camera frames become
/// Skia textures warped onto the sphere projection (here via
/// `Canvas.drawVertices` with per-vertex feathering), composited over an
/// accumulating offscreen image.
class EquirectStitcher {
  EquirectStitcher({required this.width, required this.height})
      : assert(width == height * 2, 'equirect canvas must be 2:1');

  final int width;
  final int height;

  ui.Image? _accumulated;
  final List<ui.Image> _framePool = [];
  int frameCount = 0;

  ui.Image? get preview => _accumulated;

  Future<void> addFrame({
    required ui.Image frame,
    required Quaternion orientation,
    required FrameCamera camera,
    FrameProjector? projector,
  }) async {
    final proj = projector ?? FrameProjector();
    final mesh = proj.build(
      q: orientation,
      cam: camera,
      canvasWidth: width.toDouble(),
      canvasHeight: height.toDouble(),
    );
    if (mesh.isEmpty) return;

    final (pos, uv, alpha) =
        FrameProjector.expandToTriangles(mesh, proj.gridLon);
    if (pos.isEmpty) return;

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      pos,
      textureCoordinates: uv,
      colors: _whiteAlphas(alpha),
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

    if (_accumulated != null) {
      canvas.drawImage(_accumulated!, ui.Offset.zero, Paint());
    }

    final shader = ui.ImageShader(
      frame,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      _identityMatrix64(),
    );
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..shader = shader;

    // Seam handling: draw the mesh once at the origin and, when it extends
    // past either horizontal edge, again shifted by ±width so the wrapped
    // portion lands on the opposite side of the canvas.
    canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
    final minX = _minX(pos);
    final maxX = _maxX(pos);
    if (minX < 0) {
      canvas.translate(width.toDouble(), 0);
      canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
      canvas.translate(-width.toDouble(), 0);
    }
    if (maxX > width) {
      canvas.translate(-width.toDouble(), 0);
      canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
      canvas.translate(width.toDouble(), 0);
    }

    final picture = recorder.endRecording();
    final next = await picture.toImage(width, height);
    picture.dispose();
    _accumulated?.dispose();
    _accumulated = next;
    frameCount++;
  }

  /// Final accumulated image, optionally stamped with a signature.
  Future<ui.Image> finalize({bool watermark = false}) async {
    if (_accumulated == null) {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder,
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
      canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..color = const ui.Color(0xFF101214));
      final p = recorder.endRecording();
      final img = await p.toImage(width, height);
      p.dispose();
      _accumulated = img;
    }
    if (!watermark) return _accumulated!;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    canvas.drawImage(_accumulated!, ui.Offset.zero, Paint());

    const label = '360sphere';
    final tp = TextPainter(
      text: const TextSpan(
        text: label,
        style: TextStyle(
          color: ui.Color(0xB3FFFFFF),
          fontSize: 44,
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        ui.Offset(
          width - tp.width - 56,
          height - tp.height - 40,
        ));

    final p = recorder.endRecording();
    final img = await p.toImage(width, height);
    p.dispose();
    return img;
  }

  void dispose() {
    _accumulated?.dispose();
    _accumulated = null;
    for (final f in _framePool) {
      f.dispose();
    }
    _framePool.clear();
  }

  static List<Color> _whiteAlphas(List<double> alphas) {
    final colors = <Color>[];
    for (final a in alphas) {
      final v = (a.clamp(0.0, 1.0) * 255).round();
      colors.add(Color.fromARGB(v, 255, 255, 255));
    }
    return colors;
  }

  static Float64List _identityMatrix64() {
    final m = Float64List(16);
    m[0] = 1;
    m[5] = 1;
    m[10] = 1;
    m[15] = 1;
    return m;
  }

  static double _minX(List<ui.Offset> pts) {
    var m = double.infinity;
    for (final p in pts) {
      if (p.dx < m) m = p.dx;
    }
    return m;
  }

  static double _maxX(List<ui.Offset> pts) {
    var m = double.negativeInfinity;
    for (final p in pts) {
      if (p.dx > m) m = p.dx;
    }
    return m;
  }
}
