import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../orientation/quaternion.dart';

/// Equirectangular projection math shared by the stitcher, coverage tracker
/// and HUD.
///
/// World frame is ENU (X east, Y north, Z up).
/// A direction `d` maps to longitude/latitude:
///   λ = atan2(d.x, d.y)  ∈ (-π, π]   (0 = north, π/2 = east)
///   φ = asin(d.z)        ∈ [-π/2, π/2]
/// and to equirectangular pixels on a W×H (2:1) canvas:
///   x = (λ + π) / 2π · W
///   y = (π/2 − φ) / π · H
abstract final class Equirect {
  /// Direction (unit vector) for a longitude/latitude pair.
  static Vector3 direction(double lonRad, double latRad) => Vector3(
        math.cos(latRad) * math.sin(lonRad),
        math.cos(latRad) * math.cos(lonRad),
        math.sin(latRad),
      );

  /// Longitude (radians) of a world direction.
  static double lonOf(Vector3 d) => math.atan2(d.x, d.y);

  /// Latitude (radians) of a world direction.
  static double latOf(Vector3 d) =>
      math.asin((d.length < 1e-9 ? 0 : d.z / d.length).clamp(-1.0, 1.0));

  /// Pixel position on a [width]×[height] equirectangular canvas, with
  /// longitude normalized into (-π, π].
  static Offset pixelOf(
      double lonRad, double latRad, double width, double height) {
    return pixelOfRaw(_wrapLon(lonRad), latRad, width, height);
  }

  /// Like [pixelOf] but does NOT normalize longitude. Used by the mesh
  /// builder: positions may fall outside [0, width] and the stitcher draws
  /// shifted copies so patches crossing the ±180° seam stay connected.
  static Offset pixelOfRaw(
      double lonRad, double latRad, double width, double height) {
    final x = (lonRad + math.pi) / (2 * math.pi) * width;
    final y = (math.pi / 2 - latRad) / math.pi * height;
    return Offset(x, y);
  }

  static double _wrapLon(double lon) {
    var l = lon;
    while (l >= math.pi) {
      l -= 2 * math.pi;
    }
    while (l < -math.pi) {
      l += 2 * math.pi;
    }
    return l;
  }
}

/// Pinhole camera model for one captured frame.
///
/// The frame is an "upright portrait" image: after our EXIF handling, the
/// image x-axis follows device +X and the image y-axis (downwards) follows
/// device −Y. The back camera optical axis is device −Z.
class FrameCamera {
  FrameCamera(
      {required this.fovHDeg,
      required this.imageWidth,
      required this.imageHeight})
      : fovH = fovHDeg * math.pi / 180,
        aspect = imageWidth / imageHeight;

  final double fovHDeg;
  final int imageWidth;
  final int imageHeight;

  final double fovH;
  final double aspect;

  double get tanHalfFovH => math.tan(fovH / 2);
  double get tanHalfFovV => tanHalfFovH * (imageHeight / imageWidth);
  double get fovV => 2 * math.atan(tanHalfFovV);

  /// Diagonal field of view (bounding angular radius ≈ diagonal / 2).
  double get diagonalFov =>
      2 *
      math.atan(
          math.sqrt(tanHalfFovH * tanHalfFovH + tanHalfFovV * tanHalfFovV));

  /// Camera forward axis in device frame.
  static const Vector3 forward = Vector3(0, 0, -1);

  /// Project a device-frame direction into normalized image coordinates.
  ///
  /// Returns `(u, v)` with u,v ∈ [-1, 1] (image center at 0) or `null` when
  /// the direction is behind the camera / outside the frustum margin.
  (double, double)? projectDevice(Vector3 dirDevice, {double margin = 0.0}) {
    final zc = -dirDevice.z; // depth along optical axis
    if (zc <= 1e-9) return null;
    final u = dirDevice.x / zc / tanHalfFovH;
    final v = -dirDevice.y / zc / tanHalfFovV;
    if (u.abs() > 1 + margin || v.abs() > 1 + margin) return null;
    return (u, v);
  }
}

/// One warped camera frame ready to be painted onto the equirect canvas as a
/// textured triangle mesh (Flutter's `Canvas.drawVertices` — the same Skia
/// mesh-warped offscreen-texture technique the original app used).
class WarpedFrameMesh {
  WarpedFrameMesh({
    required this.positions,
    required this.uvs,
    required this.alphas,
  });

  /// Equirectangular canvas positions, one per grid vertex.
  final List<Offset> positions;

  /// Frame texture coordinates (pixels in the source frame), same length.
  final List<Offset> uvs;

  /// Per-vertex alpha for edge feathering, same length, 0..1.
  final List<double> alphas;

  bool get isEmpty => positions.length < 4;
}

/// Builds a warped mesh for a frame captured with orientation [q]
/// (device → world).
class FrameProjector {
  FrameProjector({
    this.gridLon = 28,
    this.gridLat = 16,
    this.featherDeg = 6,
  });

  /// Mesh resolution across longitude.
  final int gridLon;

  /// Mesh resolution across latitude.
  final int gridLat;

  /// Angular width (degrees) of the soft fade at frame borders.
  final double featherDeg;

  WarpedFrameMesh build({
    required Quaternion q,
    required FrameCamera cam,
    required double canvasWidth,
    required double canvasHeight,
  }) {
    // Camera aim (forward axis) in world coordinates.
    final fwdWorld = q.rotate(FrameCamera.forward).normalized();
    final lon0 = Equirect.lonOf(fwdWorld);
    final lat0 = Equirect.latOf(fwdWorld);

    // Angular radius covered by the frame (diagonal / 2) + feather margin.
    final radius = cam.diagonalFov / 2 + featherDeg * math.pi / 180;

    // Longitude extent widens toward the poles (cos lat), clamped to π.
    final maxLat = math.pi / 2 - lat0.abs() < radius
        ? math.pi / 2
        : math.min(math.pi / 2, lat0 + radius);
    final minLat = math.pi / 2 + lat0.abs() < radius
        ? -math.pi / 2
        : math.max(-math.pi / 2, lat0 - radius);
    final cosLat = math.cos(lat0).clamp(0.15, 1.0);
    var halfLon = radius / cosLat;
    if (halfLon > math.pi) halfLon = math.pi;

    final positions = <Offset>[];
    final uvs = <Offset>[];
    final alphas = <double>[];

    // Tan-space footprint of the frame: a rectangle in (u, v) of half-size 1.
    // We iterate an *unwrapped* longitude grid so meshes that straddle the
    // ±π seam simply extend past the canvas edge (Skia clips them); this
    // keeps the mesh a single connected patch.
    final u0 = lon0 - halfLon;
    final du = 2 * halfLon / gridLon;
    final dv = (maxLat - minLat) / gridLat;

    final feather = featherDeg * math.pi / 180;

    // Track the bounding uv actually inside the frustum so fully-outside
    // vertices can clamp (avoids sampling garbage while staying alpha 0).
    Offset lastUv = Offset(cam.imageWidth / 2, cam.imageHeight / 2);

    for (var j = 0; j <= gridLat; j++) {
      for (var i = 0; i <= gridLon; i++) {
        final lon = u0 + du * i;
        final lat = minLat + dv * j;
        final dirWorld = Equirect.direction(lon, lat);
        final dirDevice = q.rotateInverse(dirWorld);

        final uvN = cam.projectDevice(dirDevice, margin: 0.05);
        if (uvN != null) {
          final (u, v) = uvN;
          lastUv = Offset(
            ((u + 1) / 2 * cam.imageWidth)
                .clamp(0.0, (cam.imageWidth - 1).toDouble()),
            ((v + 1) / 2 * cam.imageHeight)
                .clamp(0.0, (cam.imageHeight - 1).toDouble()),
          );
          // Feather: distance (radians) outside the unit frustum circle-ish.
          final angDist = _angularDistanceToFrustum(u, v, cam);
          final a = (1 - (angDist / feather)).clamp(0.0, 1.0);
          final pos = Equirect.pixelOfRaw(lon, lat, canvasWidth, canvasHeight);
          positions.add(pos);
          uvs.add(lastUv);
          alphas.add(a);
        } else {
          // Outside the frustum: keep the mesh rectangular by clamping to
          // the last valid uv with alpha 0 (contributes nothing visually but
          // keeps triangle topology simple — quads with all-invisible
          // corners are dropped in [expandToTriangles]).
          final pos = Equirect.pixelOfRaw(lon, lat, canvasWidth, canvasHeight);
          positions.add(pos);
          uvs.add(lastUv);
          alphas.add(0.0);
        }
      }
    }

    return WarpedFrameMesh(positions: positions, uvs: uvs, alphas: alphas);
  }

  /// Approximate angular distance (radians) from the frame border for
  /// normalized coords (u, v), used for the alpha feather ramp.
  double _angularDistanceToFrustum(double u, double v, FrameCamera cam) {
    // Border distance in normalized units, negative = inside.
    final du = math.max(u.abs() - 1, v.abs() - 1).clamp(0.0, 1.0);
    if (du <= 0) return 0;
    // Convert normalized border distance to an angular measure using the
    // smaller fov scale; approximate, only used for the fade ramp.
    final scale = math.min(cam.fovH, cam.fovV);
    return du * scale;
  }

  /// Expand the mesh into a triangle list, dropping quads whose corners are
  /// all invisible or fully transparent.
  static (List<Offset>, List<Offset>, List<double>) expandToTriangles(
      WarpedFrameMesh mesh, int gridLon) {
    final pos = <Offset>[];
    final uv = <Offset>[];
    final alpha = <double>[];
    final stride = gridLon + 1;

    final rows = mesh.alphas.length ~/ stride;

    bool rowVisible(int i, int j) => mesh.alphas[j * stride + i] > 0.01;

    for (var j = 0; j < rows - 1; j++) {
      for (var i = 0; i < gridLon; i++) {
        final a = j * stride + i;
        final b = a + 1;
        final c = a + stride;
        final d = c + 1;
        if (a >= mesh.alphas.length || d >= mesh.alphas.length) continue;
        final visible = rowVisible(i, j) ||
            rowVisible(i + 1, j) ||
            rowVisible(i, j + 1) ||
            rowVisible(i + 1, j + 1);
        if (!visible) continue;

        void tri(int i0, int i1, int i2) {
          pos
            ..add(mesh.positions[i0])
            ..add(mesh.positions[i1])
            ..add(mesh.positions[i2]);
          uv
            ..add(mesh.uvs[i0])
            ..add(mesh.uvs[i1])
            ..add(mesh.uvs[i2]);
          alpha
            ..add(mesh.alphas[i0])
            ..add(mesh.alphas[i1])
            ..add(mesh.alphas[i2]);
        }

        tri(a, c, b);
        tri(b, c, d);
      }
    }
    return (pos, uv, alpha);
  }
}
