import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/orientation/orientation_tracker.dart';
import 'package:sphere360/capture/orientation/quaternion.dart';

void main() {
  group('OrientationTracker gyro integration', () {
    test('90° yaw sweep integrates to ~90°', () {
      final t = OrientationTracker();
      // Angular velocity +π/2 rad/s about device Z for 1 s in 100 steps.
      const steps = 100;
      const dt = 1 / steps;
      for (var i = 0; i < steps; i++) {
        t.updateGyro(dt, 0, 0, math.pi / 2);
      }
      // Device +X axis should now point where +Y pointed (rotation about Z).
      final v = t.value.rotate(const Vector3(1, 0, 0));
      expect(v.x, closeTo(0, 1e-6));
      expect(v.y, closeTo(1, 1e-6));
      expect(v.z, closeTo(0, 1e-6));
    });

    test('gyro keeps quaternion normalized', () {
      final t = OrientationTracker();
      var rng = math.Random(7);
      for (var i = 0; i < 500; i++) {
        t.updateGyro(1 / 60, rng.nextDouble() - 0.5, rng.nextDouble() - 0.5,
            rng.nextDouble() - 0.5);
      }
      expect(t.value.norm, closeTo(1, 1e-9));
    });
  });

  group('OrientationTracker gravity correction', () {
    test('pitch error decays toward gravity', () {
      final t = OrientationTracker();
      // Start flat (screen up); accelerometer says the device is actually
      // upright portrait. Gravity correction must close the 90° gap while a
      // slow gyro drift fights it; steady-state error ≈ drift/gain.
      for (var i = 0; i < 600; i++) {
        t.updateGyro(1 / 60, 0.05, 0, 0); // drifting pitch
        t.updateAccel(const Vector3(0, 9.8, 0), dt: 1 / 60);
      }
      // Camera aim elevation should stay near horizontal-ish (device upright
      // => -Z close to horizon): the accel correction wins over the drift.
      final (_, elevation) = t.value.cameraAim;
      expect(elevation.abs(), lessThan(0.15));
    });

    test('tilted device converges to true tilt', () {
      final t = OrientationTracker();
      // Truth: upright portrait tilted 30° back. Compute the accelerometer
      // reading for that pose; start the tracker at identity so the gravity
      // correction must close a 60° gap (identity→upright) plus the tilt.
      final trueQ =
          Quaternion.axisAngle(const Vector3(1, 0, 0), math.pi / 2 - math.pi / 6);
      final gravityDevice = trueQ.rotateInverse(const Vector3(0, 0, 9.8));

      for (var i = 0; i < 900; i++) {
        t.updateAccel(gravityDevice, dt: 1 / 60);
      }
      // Compare device up-axes: tracker's device→world applied to device +Y
      // should approach the true one.
      final upEst = t.value.rotate(const Vector3(0, 1, 0));
      final upTrue = trueQ.rotate(const Vector3(0, 1, 0));
      expect(upEst.x, closeTo(upTrue.x, 0.02));
      expect(upEst.y, closeTo(upTrue.y, 0.02));
      expect(upEst.z, closeTo(upTrue.z, 0.02));
    });
  });

  group('OrientationTracker magnetic yaw correction', () {
    test('yaw drift is pulled back toward the magnetic reference', () {
      final t = OrientationTracker();
      // True pose: device flat, screen up (identity). Field: pointing north
      // in world => in device frame (identity) reads (0, 50, 0) µT.
      const field = Vector3(0, 50, 0);

      // First sample establishes the reference.
      t.updateMag(field, dt: 1 / 60);

      // Inject yaw drift via gyro about Z; mag correction should bound it.
      for (var i = 0; i < 120; i++) {
        t.updateGyro(1 / 60, 0, 0, 0.02); // 0.02 rad/s spurious yaw
        t.updateMag(field, dt: 1 / 60);
      }
      // Without correction yaw would be ~0.04 rad; with it, much less.
      final (heading, _) = t.value.cameraAim;
      // Flat device camera faces down; use device +X heading instead:
      final xAxis = t.value.rotate(const Vector3(1, 0, 0));
      final yaw = math.atan2(xAxis.y, xAxis.x);
      expect(yaw.abs(), lessThan(0.03));
      expect(heading, isNotNull);
    });
  });
}
