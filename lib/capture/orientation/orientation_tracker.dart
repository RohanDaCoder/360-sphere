import 'dart:math' as math;

import 'quaternion.dart';

/// Complementary-filter orientation tracker (device → world quaternion).
///
/// The original app fed gyroscope samples from its sensor stack into the
/// capture pipeline. This recreation uses the same idea: integrate angular
/// velocity from the gyroscope, then gently correct pitch/roll toward gravity
/// (and optionally yaw toward the magnetic field) so drift stays bounded over
/// the ~30–60 s of a capture session.
///
/// All math is plain Dart so it is unit-testable without a device.
class OrientationTracker {
  OrientationTracker({
    this.accelGain = 0.5,
    this.magGain = 0.4,
  });

  /// Proportional gain (1/s) of the gravity (pitch/roll) correction.
  /// Error decays as e^(-accelGain·t): 0.5 → ~2 s time constant.
  final double accelGain;

  /// Proportional gain (1/s) of the magnetic yaw correction.
  final double magGain;

  Quaternion _q = Quaternion.identity;
  Quaternion get value => _q;

  /// Low-passed gravity direction in device frame (normalized).
  Vector3? _gravityDevice;

  /// First horizontal magnetic-field direction seen in the world frame;
  /// used as the (arbitrary but fixed) yaw reference. Absolute heading is
  /// irrelevant for stitching — only consistency matters.
  Vector3? _magReference;

  /// Integrate one gyroscope sample.
  ///
  /// [dt] seconds since the previous sample; [wx, wy, wz] are angular
  /// velocities in rad/s around the device X/Y/Z axes.
  void updateGyro(double dt, double wx, double wy, double wz) {
    if (dt <= 0) return;
    final dq = Quaternion.fromAngularVelocity(Vector3(wx, wy, wz).scale(dt));
    _q = (_q * dq).normalized();
  }

  /// Feed one accelerometer sample (m/s², device frame).
  void updateAccel(Vector3 accel, {double dt = 1 / 60}) {
    if (accel.length < 1e-6) return;
    final acc = accel.normalized();
    _gravityDevice = _gravityDevice == null
        ? acc
        : Vector3(
            _gravityDevice!.x * 0.9 + acc.x * 0.1,
            _gravityDevice!.y * 0.9 + acc.y * 0.1,
            _gravityDevice!.z * 0.9 + acc.z * 0.1,
          ).normalized();

    // Predicted gravity direction in device frame: world +Z (up) rotated
    // into device coordinates. At rest the accelerometer measures +up.
    final pred = _q.rotateInverse(const Vector3(0, 0, 1));
    final measured = _gravityDevice!;

    // Proportional error term (device frame). We need dq such that
    // dq⁻¹·pred = measured, i.e. dq rotates measured ONTO pred — so the
    // rotation axis is (measured × pred), magnitude ≈ sin(angle).
    final err = measured.cross(pred);
    if (err.length < 1e-10) return;

    final dq = Quaternion.fromAngularVelocity(err.scale(accelGain * dt));
    _q = (_q * dq).normalized();
  }

  /// Feed one magnetometer sample (µT, device frame).
  void updateMag(Vector3 mag, {double dt = 1 / 60}) {
    if (mag.length < 1e-6) return;
    // Magnetic field direction in world frame.
    final world = _q.rotate(mag).normalized();
    // Horizontal projection — the yaw-relevant component.
    final horiz = Vector3(world.x, world.y, 0);
    if (horiz.length < 1e-6) return; // near-vertical field (rare, e.g. poles)
    final h = horiz.normalized();
    _magReference ??= h;
    final ref = _magReference!;

    // Signed yaw error between the reference and the current field heading.
    final cross = ref.x * h.y - ref.y * h.x;
    final dot = ref.x * h.x + ref.y * h.y;
    final yawErr = math.atan2(cross, dot);
    if (yawErr.abs() < 1e-6) return;

    // Correct around the world up axis (world-frame rotation).
    final dq = Quaternion.axisAngle(
        const Vector3(0, 0, 1), -magGain * dt * yawErr);
    _q = (dq * _q).normalized();
  }

  /// Reset tracking (e.g. when a capture session starts).
  void reset() {
    _q = Quaternion.identity;
    _gravityDevice = null;
    _magReference = null;
  }
}
