import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/orientation/original_orientation_filter.dart';
import 'package:sphere360/capture/orientation/quaternion.dart';

Quaternion _rot(Vector3 axis, double deg) =>
    Quaternion.axisAngle(axis, deg * math.pi / 180);

final _xAxis = const Vector3(1, 0, 0);
final _yAxis = const Vector3(0, 1, 0);
final _zAxis = const Vector3(0, 0, 1);

void main() {
  group('OriginalOrientationFilter — conventions', () {
    test('identity (phone flat, screen up) → pitch −90, roll 0, yaw 0', () {
      final f = OriginalOrientationFilter();
      final (pitch, roll, yaw) = f.update(Quaternion.identity);
      expect(pitch, closeTo(-90, 1e-6));
      expect(roll, closeTo(0, 1e-6));
      expect(yaw.abs(), lessThan(1e-6));
    });

    test('phone upright (90° around X) → pitch 0', () {
      final f = OriginalOrientationFilter();
      final (pitch, roll, _) = f.update(_rot(_xAxis, 90));
      expect(pitch, closeTo(0, 1e-6));
      expect(roll, closeTo(0, 1e-6));
    });

    test('phone upright + tilted 45° up → pitch +45', () {
      final f = OriginalOrientationFilter();
      final (pitch, _, _) = f.update(_rot(_xAxis, 135));
      expect(pitch, closeTo(45, 1e-6));
    });

    test('phone upright + tilted −45° down → pitch −45', () {
      final f = OriginalOrientationFilter();
      final (pitch, _, _) = f.update(_rot(_xAxis, 45));
      expect(pitch, closeTo(-45, 1e-6));
    });

    test('upright phone tilted sideways → roll ±90°', () {
      final f = OriginalOrientationFilter();
      // ZYX composition q = qY(roll) * qX(pitch): pitch 90 (upright) then
      // roll 90 around the long (screen-top) axis.
      final q = _rot(_yAxis, 90) * _rot(_xAxis, 90);
      final (_, roll, _) = f.update(q);
      expect(roll.abs(), closeTo(90, 1e-6));
    });

    test('pitch past straight-down maps into (−180, 180], not −270…−180', () {
      // The module's range fix: atan2 values in (−180, −90) get +360°
      // before the −90° shift. A −95° X rotation (5° past straight down)
      // reads as pitch −95 − 90 = −185 ≡ +175, reported as +175.
      final f = OriginalOrientationFilter();
      final (pitch, _, _) = f.update(_rot(_xAxis, -95));
      expect(pitch, closeTo(175, 1e-6));
      expect(pitch, lessThanOrEqualTo(180));
    });

    test('pitch just above the fix threshold stays put', () {
      // −90° exactly (and anything in [−90, 0)) is NOT lifted.
      final f = OriginalOrientationFilter();
      final (pitch, _, _) = f.update(_rot(_xAxis, -85));
      expect(pitch, closeTo(-175, 1e-6));
    });
  });

  group('OriginalOrientationFilter — yaw jump clamp (±25°)', () {
    test('a huge yaw jump is clamped to +25° then filtered to +20°', () {
      final f = OriginalOrientationFilter();
      f.update(Quaternion.identity); // yaw 0
      // A 100° yaw jump in a single reading: the module accepts only 25°,
      // then the 0.8 low-pass moves the output 80% of the way: 0.8·25 = 20.
      final (_, _, yaw) = f.update(_rot(_zAxis, -100));
      expect(yaw, closeTo(20, 1e-6));
    });

    test('a huge negative yaw jump is clamped to −25° then filtered', () {
      final f = OriginalOrientationFilter();
      f.update(Quaternion.identity);
      final (_, _, yaw) = f.update(_rot(_zAxis, 100));
      expect(yaw, closeTo(-20, 1e-6));
    });

    test('successive small steps converge toward the real yaw', () {
      final f = OriginalOrientationFilter();
      f.update(Quaternion.identity);
      // 10 readings of a 10° step: 100° total, each step under the clamp.
      var q = Quaternion.identity;
      var lastYaw = 0.0;
      for (var i = 0; i < 10; i++) {
        q = _rot(_zAxis, -10) * q;
        final (_, _, yaw) = f.update(q);
        lastYaw = yaw;
      }
      expect(lastYaw, greaterThan(80));
      expect(lastYaw, lessThan(100));
    });

    test('a turn across the ±180° seam is small, not 340°', () {
      // The module's normalizeAngle wraps into [−180, 180]: turning right
      // from +170° by 20° ends at 190° ≡ −170°. The raw delta of −340°
      // must be read as +20°, not clamped to −25° in the wrong direction
      // (the pre-fix bug treated it as −340 → −25).
      final f = OriginalOrientationFilter();
      f.update(_rot(_zAxis, -170)); // yaw +170
      expect(f.yawDeg, closeTo(170, 1e-6));
      // Physical right turn of 20°: yaw 170 → 190 ≡ −170.
      final (_, _, yaw) = f.update(_rot(_zAxis, 170));
      // Clamped target −170; filtered 170 + 0.8·(+20) = 186 ≡ −174.
      expect(yaw, closeTo(-174, 1e-6));
    });

    test('seam-crossing yaw keeps converging in the right direction', () {
      final f = OriginalOrientationFilter();
      f.update(_rot(_zAxis, -170)); // yaw +170
      // Feed the −170 yaw repeatedly; the filter must settle at −170
      // (with the ±360-guard bug it ran away toward +150).
      for (var i = 0; i < 30; i++) {
        f.update(_rot(_zAxis, 170));
      }
      expect(f.yawDeg, closeTo(-170, 1e-3));
    });
  });

  group('OriginalOrientationFilter — low-pass filter (α = 0.8)', () {
    test('a step input moves the output 80% of the way', () {
      final f = OriginalOrientationFilter();
      f.update(_rot(_xAxis, 90)); // pitch 0 baseline
      // Next reading instantly +10° pitch: expected 0 + 0.8·10 = 8°.
      final (pitch, _, _) = f.update(_rot(_xAxis, 100));
      expect(pitch, closeTo(8, 1e-6));
    });

    test('non-default alpha respected', () {
      final f = OriginalOrientationFilter(alpha: 0.5);
      f.update(_rot(_xAxis, 90));
      final (pitch, _, _) = f.update(_rot(_xAxis, 100));
      expect(pitch, closeTo(5, 1e-6));
    });
  });

  group('OriginalOrientationFilter — lifecycle', () {
    test('reset returns to uninitialized state', () {
      final f = OriginalOrientationFilter();
      f.update(_rot(_xAxis, 90));
      f.reset();
      expect(f.initialized, isFalse);
      // After reset the first sample snaps directly (no filter lag).
      final (pitch, _, _) = f.update(_rot(_xAxis, 135));
      expect(pitch, closeTo(45, 1e-6));
    });

    test('stays quiet when fed the same orientation repeatedly', () {
      final f = OriginalOrientationFilter();
      const q = Quaternion.identity;
      f.update(q);
      for (var i = 0; i < 20; i++) {
        f.update(q);
      }
      expect(f.pitchDeg, closeTo(-90, 1e-6));
      expect(f.yawDeg.abs(), lessThan(1e-6));
    });
  });

  group('angleDeltaDeg', () {
    test('wraps through 360 correctly', () {
      expect(angleDeltaDeg(350, 10), closeTo(20, 1e-9));
      expect(angleDeltaDeg(10, 350), closeTo(-20, 1e-9));
      expect(angleDeltaDeg(180, 180), 0);
    });
  });
}
