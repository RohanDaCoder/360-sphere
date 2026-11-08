import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/orientation/quaternion.dart';

void main() {
  group('Quaternion basics', () {
    test('identity rotates nothing', () {
      final v = Quaternion.identity.rotate(const Vector3(1, 2, 3));
      expect(v.x, closeTo(1, 1e-12));
      expect(v.y, closeTo(2, 1e-12));
      expect(v.z, closeTo(3, 1e-12));
    });

    test('axisAngle 90° about Z maps X to Y', () {
      final q = Quaternion.axisAngle(const Vector3(0, 0, 1), math.pi / 2);
      final v = q.rotate(const Vector3(1, 0, 0));
      expect(v.x, closeTo(0, 1e-9));
      expect(v.y, closeTo(1, 1e-9));
      expect(v.z, closeTo(0, 1e-9));
    });

    test('rotateInverse undoes rotate', () {
      final q = Quaternion.axisAngle(const Vector3(1, 1, 0), 0.7);
      final v = const Vector3(0.3, -1.2, 2.0);
      final back = q.rotateInverse(q.rotate(v));
      expect(back.x, closeTo(v.x, 1e-9));
      expect(back.y, closeTo(v.y, 1e-9));
      expect(back.z, closeTo(v.z, 1e-9));
    });

    test('norm is 1 for axisAngle constructions', () {
      for (final angle in [0.0, 0.5, 1.2, math.pi, -2.0]) {
        final q = Quaternion.axisAngle(const Vector3(1, 2, -1), angle);
        expect(q.norm, closeTo(1, 1e-12), reason: 'angle=$angle');
      }
    });

    test('slerp endpoints', () {
      final a = Quaternion.identity;
      final b = Quaternion.axisAngle(const Vector3(0, 0, 1), math.pi / 2);
      final mid = Quaternion.slerp(a, b, 0.5);
      // Midpoint of a 90° rotation = 45°.
      final v = mid.rotate(const Vector3(1, 0, 0));
      expect(v.x, closeTo(math.sqrt(0.5), 1e-9));
      expect(v.y, closeTo(math.sqrt(0.5), 1e-9));
      expect(Quaternion.slerp(a, b, 1).w, closeTo(b.w, 1e-9));
    });
  });

  group('Camera aim extraction', () {
    test('identity points the camera down (screen up)', () {
      // Device identity: +Z device = world up → back camera (-Z) faces down.
      final (heading, elevation) = Quaternion.identity.cameraAim;
      expect(elevation, closeTo(-math.pi / 2, 1e-9));
    });

    test('camera held upright facing north', () {
      // Upright portrait: device Y (top) = world up; camera -Z = world north.
      // R_x(+90°): Y→Z(up), Z→-Y(south), so -Z→+Y(north).
      final q = Quaternion.axisAngle(const Vector3(1, 0, 0), math.pi / 2);
      final (heading, elevation) = q.cameraAim;
      expect(elevation, closeTo(0, 1e-9));
      expect(heading, closeTo(0, 1e-9)); // north
    });

    test('camera upright facing east', () {
      // Upright facing north, then yaw to east. In ENU (X east, Y north, Z
      // up) a positive rotation about Z is counter-clockwise on the map
      // (north→west), so east is −90°.
      final upright = Quaternion.axisAngle(const Vector3(1, 0, 0), math.pi / 2);
      final yaw = Quaternion.axisAngle(const Vector3(0, 0, 1), -math.pi / 2);
      final q = yaw * upright;
      final (heading, elevation) = q.cameraAim;
      expect(elevation, closeTo(0, 1e-9));
      expect(heading, closeTo(math.pi / 2, 1e-9)); // east
    });
  });
}
