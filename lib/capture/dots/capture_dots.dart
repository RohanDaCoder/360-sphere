import '../../core/models.dart';

/// One capture target dot, as placed by the original app's capture screen.
///
/// The original builds its photosphere guidance from an array of dots, each
/// with a yaw/pitch aim point, a status and a type; the layout found in the
/// decompiled bundle is: `middle` row at pitch 0°, `top`/`bottom` rows at
/// ±45°, plus single `ceiling` (+90°) and `floor` (−90°) polar dots —
/// 13/9/9/1/1 = 33 dots for a normal camera (12/8/8/1/1 = 30 when the camera
/// field of view exceeds 82°, e.g. the wide-angle lens).
class CaptureDot {
  const CaptureDot({
    required this.name,
    required this.yawDeg,
    required this.pitchDeg,
    this.type = DotType.normal,
  });

  /// Row name ('ceiling' | 'top' | 'middle' | 'bottom' | 'floor') or a
  /// row-indexed name for panorama modes.
  final String name;

  /// Aim yaw in degrees [0, 360).
  final double yawDeg;

  /// Aim pitch in degrees [-90, +90].
  final double pitchDeg;

  final DotType type;

  bool get isPolar => type != DotType.normal;
}

enum DotType { normal, ceiling, floor }

/// Status of one dot, mirroring the original's CAPTURE_STATUS machine:
/// NOT_CAPTURED → HOLDING → CAPTURING → CAPTURED.
enum DotStatus { notCaptured, holding, capturing, captured }

/// Builds the dot layout for a capture mode.
///
/// Evidence (decompiled bundle): the photosphere branch calls a dot factory
/// with (name, pitch, count) for each row — `middle` 13 @ 0°, `top`/`bottom`
/// 9 @ ±45°, `ceiling`/`floor` 1 @ ±90° — with counts reduced by one per row
/// when the camera FOV is wider than 82°. Panorama modes reuse the same
/// mechanism with a single row / column.
abstract final class CaptureDots {
  /// Original threshold above which the wide layout (fewer dots) is used.
  static const double wideFovThreshold = 82;

  static List<CaptureDot> layout(
    CaptureMode mode, {
    double cameraFovDeg = 62,
    bool includeFloor = true,
  }) {
    switch (mode) {
      case CaptureMode.photosphere:
        final wide = cameraFovDeg > wideFovThreshold;
        return _photosphere(wide: wide, includeFloor: includeFloor);
      case CaptureMode.panoramaHorizontal:
        return _row('middle', 8);
      case CaptureMode.panoramaWideAngle:
        // Wide-angle lens: same single-row sweep, fewer shots.
        return _row('middle', 6);
      case CaptureMode.panoramaVertical:
        return _column(9);
      case CaptureMode.panoramaFisheye:
        // 180° fisheye: three equatorial shots 120° apart (k·360/3) cover
        // the horizon band; ceiling + floor complete the sphere.
        return [
          ..._row('middle', 3),
          const CaptureDot(
              name: 'ceiling', yawDeg: 0, pitchDeg: 90, type: DotType.ceiling),
          if (includeFloor)
            const CaptureDot(
                name: 'floor', yawDeg: 0, pitchDeg: -90, type: DotType.floor),
        ];
    }
  }

  static List<CaptureDot> _photosphere(
      {required bool wide, required bool includeFloor}) {
    final mid = wide ? 12 : 13;
    final band = wide ? 8 : 9;
    return [
      ..._row('middle', mid),
      ..._row('top', band, pitchDeg: 45),
      ..._row('bottom', band, pitchDeg: -45),
      const CaptureDot(
          name: 'ceiling', yawDeg: 0, pitchDeg: 90, type: DotType.ceiling),
      if (includeFloor)
        const CaptureDot(
            name: 'floor', yawDeg: 0, pitchDeg: -90, type: DotType.floor),
    ];
  }

  /// One horizontal row of [count] dots at [pitchDeg], evenly spaced
  /// around the full yaw circle (k·360/count), which also tiles cleanly
  /// across the wrap seam.
  static List<CaptureDot> _row(String name, int count, {double pitchDeg = 0}) {
    if (count <= 0) return const [];
    return List.generate(
      count,
      (k) => CaptureDot(
        name: name,
        yawDeg: k * 360 / count,
        pitchDeg: pitchDeg,
      ),
    );
  }

  /// One vertical column of [count] dots at yaw 0, sweeping pitch.
  static List<CaptureDot> _column(int count,
      {double minPitch = -60, double maxPitch = 60}) {
    if (count <= 1) {
      return const [CaptureDot(name: 'middle', yawDeg: 0, pitchDeg: 0)];
    }
    return List.generate(
      count,
      (k) => CaptureDot(
        name: 'column',
        yawDeg: 0,
        pitchDeg: minPitch + (maxPitch - minPitch) * k / (count - 1),
      ),
    );
  }
}
