import 'dart:math' as math;

import 'capture_dots.dart';

/// Semantics port of the original app's `useCaptureWorklet` capture director.
///
/// The original (found as worklet source in the decompiled Hermes bundle)
/// runs a per-frame update that:
///
///  * picks a target dot — the sticky previous target if still uncaptured,
///    else the pitch-weighted nearest uncaptured dot
///    (`len = (|Δpitch|·pitchWeight)² + |Δyaw|²`), with polar dots
///    (ceiling/floor) only eligible once every normal dot is captured, and
///    the floor dot only when floor capture is enabled;
///  * detects a "hold" — aim within `holdDeltaAngle` (3°) on pitch/yaw/roll —
///    which the capture screen combines with an angular-velocity gate
///    (< 5°/s) and a 400 ms hold timer before the frame is taken
///    automatically;
///  * exposes guidance: an arrow offset/rotation that hides near the target,
///    and flags for the normal (rect) / polar (circle) outline visuals.
///
/// This class is pure Dart on purpose: deterministic, unit-testable, no
/// platform channels.
class DotCaptureDirector {
  DotCaptureDirector({
    required List<CaptureDot> dots,
    this.holdDeltaAngle = 3,
    this.holdDuration = const Duration(milliseconds: 400),
    this.maxAngularVelocityDegPerSec = 5,
    this.pitchWeight = 0.2,
    this.arrowNearAngle = 6,
  })  : dots = dots,
        statuses = List.filled(dots.length, DotStatus.notCaptured);

  /// The dot layout for the session; statuses are kept in parallel.
  final List<CaptureDot> dots;

  /// Aim tolerance in degrees (original: `holdDeltaAngle = 3`,
  /// scaled by HOLD_TOLERANCE_MULTIPLIER = 1).
  final double holdDeltaAngle;

  /// How long the aim must stay inside tolerance before the frame is taken
  /// (original: `CAPTURE_HOLD_DURATION = 400` ms).
  final Duration holdDuration;

  /// Angular-velocity gate while holding (original: 5°/s).
  final double maxAngularVelocityDegPerSec;

  /// Pitch weighting for target selection (original: `pitchWeight = 0.2`).
  final double pitchWeight;

  /// When the aim is within this angle of the target the arrow hides
  /// (original: `deltaArrowAngle = 6`).
  final double arrowNearAngle;

  final List<DotStatus> statuses;

  /// Current aim (degrees). Yaw in [0, 360), pitch in [−90, +90], roll in
  /// degrees (screen tilt).
  double camYaw = 0;
  double camPitch = 0;
  double camRoll = 0;

  int targetId = -1;
  int holdId = -1;
  bool nearTarget = false;
  bool showOutline = false;
  bool get isPolarTarget => targetId >= 0 && dots[targetId].isPolar;

  DateTime? _holdStart;
  int _prevTarget = -1;

  bool get allCaptured => statuses.every((s) => s == DotStatus.captured);
  int get capturedCount =>
      statuses.where((s) => s == DotStatus.captured).length;

  void reset() {
    for (var i = 0; i < statuses.length; i++) {
      statuses[i] = DotStatus.notCaptured;
    }
    targetId = -1;
    holdId = -1;
    _prevTarget = -1;
    _holdStart = null;
    nearTarget = false;
    showOutline = false;
  }

  /// Fraction [0, 1] of the current hold, for the HUD progress ring.
  double get holdFraction {
    final start = _holdStart;
    if (start == null || holdId < 0) return 0;
    final elapsed = DateTime.now().difference(start).inMilliseconds;
    return (elapsed / holdDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Mark [id] captured (called after its frame was taken). Returns true
  /// when the dot actually transitioned (the caller uses this to fire the
  /// capture haptic exactly once).
  bool markCaptured(int id) {
    if (id < 0 || id >= statuses.length) return false;
    final already = statuses[id] == DotStatus.captured;
    statuses[id] = DotStatus.captured;
    if (holdId == id) {
      holdId = -1;
      _holdStart = null;
    }
    if (targetId == id) _prevTarget = -1;
    return !already;
  }

  /// Feed one sensor-derived aim sample. [angularVelocityDegPerSec] is the
  /// smoothed angular speed of the device (used to gate the hold).
  ///
  /// Returns the id of the dot whose hold just completed (the capture screen
  /// then takes the picture), or −1.
  int update({
    required double yawDeg,
    required double pitchDeg,
    required double rollDeg,
    double? angularVelocityDegPerSec,
  }) {
    camYaw = yawDeg;
    camPitch = pitchDeg;
    camRoll = rollDeg;

    _pickTarget();

    // Hold detection: inside tolerance on pitch (and yaw for normal dots),
    // roll level, and not moving too fast.
    var newHoldId = -1;
    if (targetId >= 0 && !_isCaptured(targetId)) {
      final d = dots[targetId];
      final dPitch = (d.pitchDeg - camPitch).abs();
      final dYaw = angleDiff(d.yawDeg - camYaw).abs();
      final rollOk = camRoll.abs() < holdDeltaAngle;
      final yawOk = d.isPolar || dYaw < holdDeltaAngle;
      final speed = angularVelocityDegPerSec;
      final speedOk = speed == null || speed < maxAngularVelocityDegPerSec;
      if (dPitch < holdDeltaAngle && rollOk && yawOk && speedOk) {
        newHoldId = targetId;
      }
    }

    // Hold bookkeeping.
    var completed = -1;
    if (newHoldId != holdId) {
      // The previous hold broke: its dot returns to NOT_CAPTURED.
      if (holdId >= 0 && statuses[holdId] == DotStatus.holding) {
        statuses[holdId] = DotStatus.notCaptured;
      }
      holdId = newHoldId;
      _holdStart = newHoldId >= 0 ? DateTime.now() : null;
      if (newHoldId >= 0) statuses[newHoldId] = DotStatus.holding;
    } else if (holdId >= 0) {
      final start = _holdStart;
      if (start != null) {
        final held = DateTime.now().difference(start);
        if (held >= holdDuration) {
          statuses[holdId] = DotStatus.capturing;
          completed = holdId;
          holdId = -1;
          _holdStart = null;
        }
      }
    }

    // Guidance state.
    if (targetId >= 0) {
      final d = dots[targetId];
      final dPitch = (d.pitchDeg - camPitch).abs();
      final dYaw = angleDiff(d.yawDeg - camYaw).abs();
      nearTarget =
          dPitch < arrowNearAngle && (d.isPolar || dYaw < arrowNearAngle);
    } else {
      nearTarget = false;
    }
    showOutline = targetId >= 0 && !nearTarget;
    if (allCaptured) showOutline = false;

    return completed;
  }

  void _pickTarget() {
    if (dots.isEmpty) {
      targetId = -1;
      return;
    }
    if (allCaptured) {
      targetId = -1;
      holdId = -1;
      _holdStart = null;
      return;
    }

    var allNormalDone = true;
    var hasCaptured = false;
    for (var i = 0; i < dots.length; i++) {
      if (statuses[i] == DotStatus.captured) hasCaptured = true;
      if (!dots[i].isPolar && statuses[i] != DotStatus.captured) {
        allNormalDone = false;
      }
    }

    // Sticky previous target while it is still uncaptured (and not a polar
    // dot that must wait, nor a disabled floor dot).
    if (hasCaptured &&
        _prevTarget >= 0 &&
        _prevTarget < dots.length &&
        !_isCaptured(_prevTarget)) {
      final d = dots[_prevTarget];
      final polarBlocked = d.isPolar && !allNormalDone;
      final floorBlocked = d.type == DotType.floor && !_floorEnabled;
      if (!polarBlocked && !floorBlocked) {
        targetId = _prevTarget;
        return;
      }
    }

    // Nearest uncaptured dot by the original's weighted metric.
    var minLen = double.infinity;
    var best = -1;
    for (var i = 0; i < dots.length; i++) {
      final d = dots[i];
      if (_isCaptured(i)) continue;
      if (d.isPolar && !allNormalDone) continue; // polar dots go last
      if (d.type == DotType.floor && !_floorEnabled) continue;
      final absPitch = (d.pitchDeg - camPitch).abs();
      final absYaw = angleDiff(d.yawDeg - camYaw).abs();
      final wP = absPitch * pitchWeight;
      final len = d.isPolar ? wP * wP : wP * wP + absYaw * absYaw;
      if (len < minLen) {
        minLen = len;
        best = i;
      }
    }
    targetId = best;
    _prevTarget = best;
  }

  bool _isCaptured(int id) => statuses[id] == DotStatus.captured;

  /// Whether the floor dot participates; the original exposes this as
  /// `inFloorCapture` on the capture screen.
  bool _floorEnabled = true;
  set floorEnabled(bool v) => _floorEnabled = v;

  /// Signed smallest difference b − a mapped into (−180, 180]
  /// (port of the original's `angleDiffW` worklet).
  static double angleDiff(double deltaDeg) {
    var d = deltaDeg.remainder(360);
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Arrow guidance, ported from the original's worklet: the arrow points
  /// from the current aim toward the target; straight up/down for polar
  /// targets; hidden when near.
  ///
  /// Returns (visible, angleDeg) where the angle is measured like the
  /// original: atan2 direction for the arrow rotation with 0° = up.
  (bool, double) arrowGuidance() {
    if (targetId < 0 || nearTarget) return (false, 90);
    final d = dots[targetId];
    if (d.type == DotType.ceiling) return (true, 0);
    if (d.type == DotType.floor) return (true, 180);
    // Screen direction: yaw delta → horizontal, pitch delta → vertical
    // (inverted because pitch up moves the target up the screen).
    final dYaw = angleDiff(d.yawDeg - camYaw);
    final dPitch = d.pitchDeg - camPitch;
    // Screen angle with 0° = up, 90° = right (compass yaw increases when
    // turning right), so: atan2(yawDelta, pitchDelta).
    final angle = math.atan2(dYaw, dPitch) * 180 / math.pi;
    return (true, angle);
  }
}
