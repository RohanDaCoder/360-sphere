import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/orientation/quaternion.dart';
import 'package:sphere360/capture/stitching/equirect_projection.dart';

void main() {
  group('FrameCamera fisheye projection (panorama-fisheye mode)', () {
    test('diagonalFov equals the configured full-circle FOV', () {
      final cam = FrameCamera(
        fovHDeg: 180,
        imageWidth: 1000,
        imageHeight: 1000,
        projection: ProjectionModel.fisheye,
      );
      expect(cam.diagonalFov, closeTo(math.pi, 1e-9));
    });

    test('on-axis direction maps to the image center', () {
      final cam = FrameCamera(
        fovHDeg: 180,
        imageWidth: 1000,
        imageHeight: 1000,
        projection: ProjectionModel.fisheye,
      );
      final uv = cam.projectDevice(const Vector3(0, 0, -1));
      expect(uv, isNotNull);
      expect(uv!.$1, closeTo(0, 1e-9));
      expect(uv.$2, closeTo(0, 1e-9));
    });

    test('equidistant mapping: radius proportional to angle from axis', () {
      final cam = FrameCamera(
        fovHDeg: 180,
        imageWidth: 1000,
        imageHeight: 1000,
        projection: ProjectionModel.fisheye,
      );
      // 90° off-axis on the horizontal axis → r = 90/90 = 1 → u = ±1.
      // Device +X is the image right side.
      final right = cam.projectDevice(const Vector3(1, 0, 0));
      expect(right, isNotNull);
      expect(right!.$1, closeTo(1.0, 1e-9));
      // 45° off-axis → r = 0.5.
      final half = cam.projectDevice(const Vector3(1, 0, -1).normalized());
      expect(half, isNotNull);
      expect(half!.$1, closeTo(0.5, 1e-9));
      // Vertical: v sign follows -y (image y down).
      final up = cam.projectDevice(const Vector3(0, 1, 0));
      expect(up, isNotNull);
      expect(up!.$2, closeTo(-1.0, 1e-9));
    });

    test('directions outside the lens circle are rejected', () {
      final cam = FrameCamera(
        fovHDeg: 180,
        imageWidth: 1000,
        imageHeight: 1000,
        projection: ProjectionModel.fisheye,
      );
      // Behind the lens.
      expect(cam.projectDevice(const Vector3(0, 0, 1)), isNull);
      // A 180° lens rejects nothing off-plane, but a 120° lens rejects
      // directions beyond 60° from the axis.
      final narrow = FrameCamera(
        fovHDeg: 120,
        imageWidth: 1000,
        imageHeight: 1000,
        projection: ProjectionModel.fisheye,
      );
      expect(narrow.projectDevice(const Vector3(-1, 0, 0)), isNull); // 90° off
      expect(
        narrow.projectDevice(const Vector3(-1, 0, -2).normalized()),
        isNotNull, // ~26.6° off
      );
    });

    test('mesh builder accepts fisheye frames (smoke)', () {
      final cam = FrameCamera(
        fovHDeg: 180,
        imageWidth: 1000,
        imageHeight: 1000,
        projection: ProjectionModel.fisheye,
      );
      final projector = FrameProjector();
      final mesh = projector.build(
        q: Quaternion.identity,
        cam: cam,
        canvasWidth: 4096,
        canvasHeight: 2048,
      );
      expect(mesh.isEmpty, isFalse);
      expect(mesh.positions.length, mesh.uvs.length);
      expect(mesh.positions.length, mesh.alphas.length);
    });
  });
}
