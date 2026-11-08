import 'dart:math' as math;

/// Minimal 3D vector used by the orientation and projection math.
class Vector3 {
  const Vector3(this.x, this.y, this.z);

  final double x, y, z;

  static const Vector3 zero = Vector3(0, 0, 0);
  static const Vector3 unitX = Vector3(1, 0, 0);
  static const Vector3 unitY = Vector3(0, 1, 0);
  static const Vector3 unitZ = Vector3(0, 0, 1);

  Vector3 operator +(Vector3 o) => Vector3(x + o.x, y + o.y, z + o.z);
  Vector3 operator -(Vector3 o) => Vector3(x - o.x, y - o.y, z - o.z);
  Vector3 operator -() => Vector3(-x, -y, -z);
  Vector3 scale(double s) => Vector3(x * s, y * s, z * s);

  double dot(Vector3 o) => x * o.x + y * o.y + z * o.z;

  Vector3 cross(Vector3 o) => Vector3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => math.sqrt(dot(this));

  Vector3 normalized() {
    final l = length;
    if (l < 1e-12) return Vector3.zero;
    return Vector3(x / l, y / l, z / l);
  }

  @override
  String toString() => 'V3($x, $y, $z)';
}

/// Unit quaternion representing device orientation.
///
/// Convention (matches Android sensor axes):
///  * Device frame: X points right on the screen, Y points to the top of the
///    screen, Z points out of the screen toward the user.
///  * World frame: ENU — X east, Y north, Z up.
///  * [Quaternion] `q` maps device-frame vectors to world-frame vectors:
///    `v_world = q.rotate(v_device)`.
///  * The back camera looks along device `-Z`, with the image's "up" along
///    device `+Y` when the phone is held upright in portrait.
class Quaternion {
  const Quaternion(this.w, this.x, this.y, this.z);

  final double w, x, y, z;

  static const Quaternion identity = Quaternion(1, 0, 0, 0);

  double get norm => math.sqrt(w * w + x * x + y * y + z * z);

  Quaternion normalized() {
    final n = norm;
    if (n < 1e-12) return identity;
    return Quaternion(w / n, x / n, y / n, z / n);
  }

  Quaternion get conjugate => Quaternion(w, -x, -y, -z);
  Quaternion get inverse => conjugate.normalized();

  Quaternion operator *(Quaternion o) => Quaternion(
        w * o.w - x * o.x - y * o.y - z * o.z,
        w * o.x + x * o.w + y * o.z - z * o.y,
        w * o.y - x * o.z + y * o.w + z * o.x,
        w * o.z + x * o.y - y * o.x + z * o.w,
      );

  /// Rotate vector v by this quaternion: `q * v * q^-1`.
  Vector3 rotate(Vector3 v) {
    // Optimized form avoiding full quaternion products.
    final qv = Vector3(x, y, z);
    final t = qv.cross(v).scale(2.0);
    final cross2 = qv.cross(t);
    return v + t.scale(w) + cross2;
  }

  /// Rotate vector v from world frame into device frame.
  Vector3 rotateInverse(Vector3 v) => inverse.rotate(v);

  /// Quaternion for a rotation of [angleRad] around [axis] (unit vector).
  factory Quaternion.axisAngle(Vector3 axis, double angleRad) {
    final a = axis.normalized();
    final h = angleRad / 2;
    final s = math.sin(h);
    return Quaternion(math.cos(h), a.x * s, a.y * s, a.z * s).normalized();
  }

  /// Exponential map: build the small rotation quaternion for an angular
  /// velocity vector `omega * dt` (device frame).
  factory Quaternion.fromAngularVelocity(Vector3 omegaDt) {
    final theta = omegaDt.length;
    if (theta < 1e-10) return identity;
    return Quaternion.axisAngle(omegaDt.scale(1 / theta), theta);
  }

  /// Intrinsic ZYX euler angles (yaw about world Z, pitch, roll) in radians.
  (double yaw, double pitch, double roll) get eulerZYX {
    final sinp = 2 * (w * y - z * x);
    final pitch = sinp.clamp(-1.0, 1.0);
    return (
      math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)), // yaw (Z)
      math.asin(pitch), // pitch (Y)
      math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y)), // roll (X)
    );
  }

  /// Yaw (compass heading) of the device's -Z camera axis, radians.
  double get cameraHeading {
    final fwd = rotate(const Vector3(0, 0, -1));
    return math.atan2(fwd.x, fwd.y); // heading from north (Y), clockwise east.
  }

  /// Heading (azimuth, radians) and elevation (radians) of the camera axis.
  (double heading, double elevation) get cameraAim {
    final fwd = rotate(const Vector3(0, 0, -1));
    final f = fwd.normalized();
    final elev = math.asin(f.z.clamp(-1.0, 1.0));
    final az = math.atan2(f.x, f.y);
    return (az, elev);
  }

  /// Spherical linear interpolation.
  static Quaternion slerp(Quaternion a, Quaternion b, double t) {
    var dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    var bb = b;
    if (dot < 0) {
      bb = Quaternion(-b.w, -b.x, -b.y, -b.z);
      dot = -dot;
    }
    if (dot > 0.9995) {
      return Quaternion(
        a.w + t * (bb.w - a.w),
        a.x + t * (bb.x - a.x),
        a.y + t * (bb.y - a.y),
        a.z + t * (bb.z - a.z),
      ).normalized();
    }
    final theta0 = math.acos(dot.clamp(-1.0, 1.0));
    final theta = theta0 * t;
    final sinTheta0 = math.sin(theta0);
    final s0 = math.sin(theta0 - theta) / sinTheta0;
    final s1 = math.sin(theta) / sinTheta0;
    return Quaternion(
      s0 * a.w + s1 * bb.w,
      s0 * a.x + s1 * bb.x,
      s0 * a.y + s1 * bb.y,
      s0 * a.z + s1 * bb.z,
    ).normalized();
  }

  @override
  String toString() => 'Q($w, $x, $y, $z)';
}
