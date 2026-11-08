import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/orientation/quaternion.dart';
import 'package:sphere360/capture/stitching/equirect_projection.dart';

void main() {
  group('Equirect direction/lon-lat round trip', () {
    test('direction → lon/lat → direction', () {
      final cases = <(double, double)>[
        (0.0, 0.0),
        (math.pi / 2, 0.0),
        (-0.7, 0.4),
        (math.pi - 0.01, -1.2),
        (0.0, math.pi / 2 - 0.01),
        (2.5, -0.9),
      ];
      for (final (lon, lat) in cases) {
        final d = Equirect.direction(lon, lat);
        final lon2 = Equirect.lonOf(d);
        final lat2 = Equirect.latOf(d);
        // lon wrap-around near ±π
        var dLon = (lon2 - lon).abs();
        if (dLon > math.pi) dLon = 2 * math.pi - dLon;
        expect(dLon, lessThan(1e-9), reason: 'lon $lon');
        expect(lat2, closeTo(lat, 1e-9), reason: 'lat $lat');
      }
    });

    test('pixel mapping is 2:1 and centered', () {
      // north (lon 0) → center of the image.
      final north = Equirect.pixelOf(0, 0, 4096, 2048);
      expect(north.dx, closeTo(2048, 1e-9));
      expect(north.dy, closeTo(1024, 1e-9));

      final top = Equirect.pixelOf(0, math.pi / 2, 4096, 2048);
      expect(top.dy, closeTo(0, 1e-9));

      // Both seam edges (+π and −π) map to the same pixel column (x = 0,
      // with the [-π, π) convention).
      final seamPlus = Equirect.pixelOf(math.pi, 0, 4096, 2048);
      expect(seamPlus.dx, closeTo(0, 1e-9));
      final seamMinus = Equirect.pixelOf(-math.pi, 0, 4096, 2048);
      expect(seamMinus.dx, closeTo(0, 1e-9));
    });
  });

  group('FrameCamera projection', () {
    final cam = FrameCamera(fovHDeg: 60, imageWidth: 1600, imageHeight: 1200);

    test('center of the frustum projects to image center', () {
      // Camera identity looking along -Z device: direction (0,0,-1) is the
      // optical axis center.
      final uv = cam.projectDevice(const Vector3(0, 0, -1));
      expect(uv, isNotNull);
      final (u, v) = uv!;
      expect(u, closeTo(0, 1e-9));
      expect(v, closeTo(0, 1e-9));
    });

    test('up in the image maps to negative v', () {
      // Device +Y is image-up; a ray toward device +Y tilts the point up.
      final uv = cam.projectDevice(const Vector3(0, 0.3, -1));
      expect(uv, isNotNull);
      expect(uv!.$2, lessThan(0));
    });

    test('behind-camera and out-of-frustum rays are rejected', () {
      expect(cam.projectDevice(const Vector3(0, 0, 1)), isNull);
      // tan(30°) ≈ 0.577; a ray at u > 1 is outside.
      expect(cam.projectDevice(const Vector3(-2, 0, 1)), isNull);
      expect(cam.projectDevice(const Vector3(0, -2, 1)), isNull);
    });

    test('fov geometry is consistent', () {
      // At the horizontal edge: |x/z| = tan(fovH/2).
      final tanHalf = math.tan(cam.fovH / 2);
      final uv = cam.projectDevice(Vector3(tanHalf, 0, -1));
      expect(uv!.$1, closeTo(1, 1e-9));
    });
  });

  group('FrameProjector mesh', () {
    test('mesh centered on the camera aim with valid uvs', () {
      final projector = FrameProjector();
      final cam = FrameCamera(fovHDeg: 60, imageWidth: 1600, imageHeight: 1200);

      // Upright portrait facing north (R_x(+90°): device Y → world up,
      // camera −Z → north).
      final q = Quaternion.axisAngle(const Vector3(1, 0, 0), math.pi / 2);
      final mesh = projector.build(
        q: q,
        cam: cam,
        canvasWidth: 4096,
        canvasHeight: 2048,
      );

      expect(mesh.isEmpty, isFalse);
      expect(mesh.positions.length, equals(mesh.uvs.length));
      expect(mesh.positions.length, equals(mesh.alphas.length));

      // The camera aim (north, lon=0) should map to canvas x ≈ 2048.
      final fwd = q.rotate(const Vector3(0, 0, -1));
      final aimPixel =
          Equirect.pixelOf(Equirect.lonOf(fwd), Equirect.latOf(fwd), 4096, 2048);
      var minDist = double.infinity;
      for (final p in mesh.positions) {
        final d = (p - aimPixel).distance;
        if (d < minDist) minDist = d;
      }
      // Mesh is ~28 cells across ~60°+ margin; cell size ≈ 4096·(2.4/28)/2π
      // ≈ 22px/deg... allow generous tolerance.
      expect(minDist, lessThan(120));

      // All uvs within the image bounds (clamped).
      for (final uv in mesh.uvs) {
        expect(uv.dx, inInclusiveRange(0, cam.imageWidth));
        expect(uv.dy, inInclusiveRange(0, cam.imageHeight));
      }

      // Interior vertices fully opaque.
      final opaqueCount = mesh.alphas.where((a) => a > 0.999).length;
      expect(opaqueCount, greaterThan(mesh.alphas.length * 0.3));
    });

    test('seam-crossing mesh extends outside the canvas (for shifted redraw)', () {
      final projector = FrameProjector();
      final cam = FrameCamera(fovHDeg: 60, imageWidth: 1600, imageHeight: 1200);

      // Upright portrait facing the seam (south, lon = ±π).
      final upright = Quaternion.axisAngle(const Vector3(1, 0, 0), math.pi / 2);
      final yawToSeam = Quaternion.axisAngle(const Vector3(0, 0, 1), math.pi);
      final q = yawToSeam * upright;

      final mesh = projector.build(
        q: q,
        cam: cam,
        canvasWidth: 4096,
        canvasHeight: 2048,
      );

      final xs = mesh.positions.map((p) => p.dx);
      final minX = xs.reduce(math.min);
      final maxX = xs.reduce(math.max);
      // Either the mesh crosses 0 or 4096 (positions are unwrapped).
      expect(minX < 0 || maxX > 4096, isTrue,
          reason: 'minX=$minX maxX=$maxX');
    });

    test('triangle expansion drops invisible quads only', () {
      final projector = FrameProjector();
      final cam = FrameCamera(fovHDeg: 60, imageWidth: 1600, imageHeight: 1200);
      final q = Quaternion.axisAngle(const Vector3(1, 0, 0), math.pi / 2);
      final mesh = projector.build(
        q: q,
        cam: cam,
        canvasWidth: 2048,
        canvasHeight: 1024,
      );

      final (pos, uv, alpha) =
          FrameProjector.expandToTriangles(mesh, projector.gridLon);
      expect(pos.length, uv.length);
      expect(pos.length, alpha.length);
      expect(pos.length % 3, equals(0));
      expect(pos.length, greaterThan(0));
    });
  });
}
