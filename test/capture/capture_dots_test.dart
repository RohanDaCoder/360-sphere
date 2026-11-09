import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/dots/capture_dots.dart';
import 'package:sphere360/capture/dots/dot_capture_director.dart';
import 'package:sphere360/core/models.dart';

void main() {
  group('CaptureDots layouts (ported from the original capture screen)', () {
    test('photosphere normal FOV = 33 dots: 13/9/9/1/1', () {
      final dots = CaptureDots.layout(CaptureMode.photosphere,
          cameraFovDeg: 62, includeFloor: true);
      expect(dots, hasLength(33));
      expect(dots.where((d) => d.name == 'middle'), hasLength(13));
      expect(dots.where((d) => d.name == 'top'), hasLength(9));
      expect(dots.where((d) => d.name == 'bottom'), hasLength(9));
      expect(dots.where((d) => d.type == DotType.ceiling), hasLength(1));
      expect(dots.where((d) => d.type == DotType.floor), hasLength(1));
      expect(dots.firstWhere((d) => d.name == 'top').pitchDeg, 45);
      expect(dots.firstWhere((d) => d.name == 'bottom').pitchDeg, -45);
      expect(dots.firstWhere((d) => d.type == DotType.ceiling).pitchDeg, 90);
    });

    test('photosphere wide FOV (>82°) = 30 dots: 12/8/8/1/1', () {
      final dots = CaptureDots.layout(CaptureMode.photosphere,
          cameraFovDeg: 90, includeFloor: true);
      expect(dots, hasLength(30));
      expect(dots.where((d) => d.name == 'middle'), hasLength(12));
      expect(dots.where((d) => d.name == 'top'), hasLength(8));
      expect(dots.where((d) => d.name == 'bottom'), hasLength(8));
    });

    test('floor dot excluded when includeFloor = false (inFloorCapture off)',
        () {
      final dots = CaptureDots.layout(CaptureMode.photosphere,
          cameraFovDeg: 62, includeFloor: false);
      expect(dots.where((d) => d.type == DotType.floor), isEmpty);
      expect(dots, hasLength(32));
    });

    test('photosphere rows are evenly spaced across the full circle', () {
      final dots = CaptureDots.layout(CaptureMode.photosphere,
          cameraFovDeg: 62, includeFloor: true);
      final mid =
          dots.where((d) => d.name == 'middle').map((d) => d.yawDeg).toList();
      final spacing = 360 / 13;
      for (var k = 0; k < mid.length; k++) {
        expect(mid[k], closeTo(k * spacing, 1e-9));
      }
    });

    test('panorama modes produce single-row/column layouts', () {
      expect(CaptureDots.layout(CaptureMode.panoramaHorizontal), hasLength(8));
      expect(CaptureDots.layout(CaptureMode.panoramaWideAngle), hasLength(6));
      final vertical = CaptureDots.layout(CaptureMode.panoramaVertical);
      expect(vertical, hasLength(9));
      expect(vertical.first.pitchDeg, -60);
      expect(vertical.last.pitchDeg, 60);
      expect(vertical.every((d) => d.yawDeg == 0), isTrue);
    });

    test('fisheye layout: 3 equatorial dots 120° apart + ceiling + floor', () {
      final dots =
          CaptureDots.layout(CaptureMode.panoramaFisheye, includeFloor: true);
      expect(dots, hasLength(5));
      final equator =
          dots.where((d) => d.type == DotType.normal).map((d) => d.yawDeg);
      expect(equator, containsAll(<double>[0, 120, 240]));
    });
  });

  group('DotCaptureDirector (ported hold-to-capture worklet)', () {
    DotCaptureDirector build({bool includeFloor = true}) {
      return DotCaptureDirector(
        dots: CaptureDots.layout(CaptureMode.photosphere,
            cameraFovDeg: 62, includeFloor: includeFloor),
      )..floorEnabled = includeFloor;
    }

    test('angleDiff matches the original angleDiffW worklet', () {
      double ref(double a, double b) {
        var x = a < 0 ? a + 360 : a;
        var y = b < 0 ? b + 360 : b;
        var diff = y - x;
        if (diff > 180) {
          diff -= 360;
        } else if (diff < -180) {
          diff += 360;
        }
        return diff;
      }

      for (final pair in const [
        (0.0, 0.0),
        (0.0, 90.0),
        (350.0, 10.0),
        (10.0, 350.0),
      ]) {
        expect(DotCaptureDirector.angleDiff(pair.$2 - pair.$1),
            closeTo(ref(pair.$1, pair.$2), 1e-9));
      }
      // The ±180° boundary maps to either sign depending on the input
      // wrap; both denote the same half-turn.
      expect(DotCaptureDirector.angleDiff(180).abs(), 180);
      expect(DotCaptureDirector.angleDiff(-90 - 90).abs(), 180);
    });

    test('targets the nearest uncaptured dot, then moves on', () {
      final d = build();
      // Aim between middle dots 0 (yaw 0) and 1 (yaw 27.7): dot 0 wins.
      d.update(yawDeg: 5, pitchDeg: 0, rollDeg: 0);
      expect(d.targetId, 0);
      d.markCaptured(0);
      // Aim at yaw 14 (mid-gap): dot 1 is the weighted-nearest (the
      // original's pitchWeight 0.2 makes same-row yaw moves cheaper than
      // pitch moves).
      d.update(yawDeg: 14, pitchDeg: 0, rollDeg: 0);
      expect(d.targetId, 1);
      d.markCaptured(1);
      // Aim back at yaw 0: the top dot at yaw 0 (Δpitch 45, Δyaw 0) now
      // wins — the ported metric row-jumps exactly like the original.
      d.update(yawDeg: 0, pitchDeg: 0, rollDeg: 0);
      expect(d.dots[d.targetId].name, 'top');
    });

    test('polar dots are targeted only after all normal dots', () {
      final d = build();
      // Capture all 31 normal dots.
      for (var i = 0; i < 31; i++) {
        d.markCaptured(i);
      }
      d.update(yawDeg: 0, pitchDeg: 0, rollDeg: 0);
      final target = d.dots[d.targetId];
      expect(target.type, anyOf(DotType.ceiling, DotType.floor));
    });

    test('floor dot skipped when floor capture disabled', () {
      final d = build(includeFloor: false);
      for (var i = 0; i < 31; i++) {
        d.markCaptured(i);
      }
      d.update(yawDeg: 0, pitchDeg: 0, rollDeg: 0);
      expect(d.dots[d.targetId].type, DotType.ceiling);
      d.markCaptured(d.targetId);
      expect(d.allCaptured, isTrue);
      d.update(yawDeg: 0, pitchDeg: 0, rollDeg: 0);
      expect(d.targetId, -1);
    });

    test('hold completes after 400 ms on target and fires capture', () async {
      final d = DotCaptureDirector(
        dots: CaptureDots.layout(CaptureMode.photosphere,
            cameraFovDeg: 62, includeFloor: true),
        holdDuration: const Duration(milliseconds: 400),
      )..floorEnabled = true;
      var completed = d.update(yawDeg: 0, pitchDeg: 0, rollDeg: 0);
      expect(completed, -1);
      expect(d.holdId, 0);
      expect(d.statuses[0], DotStatus.holding);

      // Still on target after 150 ms: no capture yet.
      Future<void> tick(int ms, {double yaw = 0}) async {
        await Future<void>.delayed(Duration(milliseconds: ms));
        completed = d.update(yawDeg: yaw, pitchDeg: 0, rollDeg: 0);
      }

      await tick(150);
      expect(completed, -1);
      // Move off target: hold resets.
      await tick(50, yaw: 40);
      expect(d.holdId, -1);
      expect(d.statuses[0], DotStatus.notCaptured);

      // Back on target and hold through the full duration.
      await tick(100);
      final sw = Stopwatch()..start();
      var id = -1;
      while (sw.elapsed < const Duration(milliseconds: 600) && id < 0) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        id = d.update(yawDeg: 0, pitchDeg: 0, rollDeg: 0);
      }
      expect(id, 0);
      expect(d.statuses[0], DotStatus.capturing);
    });

    test('angular velocity above 5°/s blocks the hold', () {
      final d = build();
      final completed = d.update(
        yawDeg: 0,
        pitchDeg: 0,
        rollDeg: 0,
        angularVelocityDegPerSec: 30,
      );
      expect(completed, -1);
      expect(d.holdId, -1);
    });

    test('roll beyond tolerance blocks the hold', () {
      final d = build();
      d.update(yawDeg: 0, pitchDeg: 0, rollDeg: 20);
      expect(d.holdId, -1);
    });

    test('arrow guidance: right / up / down / hidden near target', () {
      final d = build();
      // Aim at yaw 100: nearest middle dot sits at yaw ~110.8 → arrow
      // visible, pointing right (90°).
      d.update(yawDeg: 100, pitchDeg: 0, rollDeg: 0);
      var (visible, angle) = d.arrowGuidance();
      expect(visible, isTrue);
      expect(angle, closeTo(90, 5)); // to the right

      // Ceiling dot: arrow points up (0°).
      for (var i = 0; i < 31; i++) {
        d.markCaptured(i);
      }
      d.update(yawDeg: 0, pitchDeg: 0, rollDeg: 0);
      (visible, angle) = d.arrowGuidance();
      expect(visible, isTrue);
      expect(angle, 0);

      // Near the target: arrow hidden, outline shown.
      d.update(yawDeg: 0, pitchDeg: 88, rollDeg: 0);
      expect(d.nearTarget, isTrue);
      (visible, angle) = d.arrowGuidance();
      expect(visible, isFalse);
    });
  });

  group('markCaptured transitions (capture haptic gate)', () {
    test('returns true only on the first capture of a dot', () {
      final d = DotCaptureDirector(
        dots: CaptureDots.layout(CaptureMode.photosphere,
            cameraFovDeg: 62, includeFloor: true),
      )..reset();

      expect(d.markCaptured(0), isTrue); // NOT_CAPTURED → CAPTURED
      expect(d.markCaptured(0), isFalse); // already captured
      expect(d.markCaptured(1), isTrue);
      expect(d.markCaptured(1), isFalse);
    });

    test('rejects invalid ids', () {
      final d = DotCaptureDirector(
        dots: CaptureDots.layout(CaptureMode.panoramaHorizontal,
            cameraFovDeg: 62, includeFloor: true),
      )..reset();

      expect(d.markCaptured(-1), isFalse);
      expect(d.markCaptured(999), isFalse);
    });
  });
}
