import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/orientation/quaternion.dart';
import 'package:sphere360/capture/stitching/equirect_projection.dart';
import 'package:sphere360/capture/stitching/equirect_stitcher.dart';
import 'package:sphere360/capture/stitching/exif_orientation.dart';

void main() {
  group('ExifOrientation parser', () {
    test('reads orientation from a little-endian EXIF blob', () {
      final jpeg = _minimalJpeg(orientation: 6, littleEndian: true);
      expect(ExifOrientation.read(jpeg), equals(6));
    });

    test('reads orientation from a big-endian EXIF blob', () {
      final jpeg = _minimalJpeg(orientation: 8, littleEndian: false);
      expect(ExifOrientation.read(jpeg), equals(8));
    });

    test('returns 1 for plain JPEG without EXIF', () {
      final bytes =
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x04, 1, 2, 3, 4]);
      expect(ExifOrientation.read(bytes), equals(1));
    });

    test('returns 1 for garbage', () {
      expect(ExifOrientation.read(Uint8List(10)), equals(1));
    });
  });

  group('CoverageTracker', () {
    final cam = FrameCamera(fovHDeg: 60, imageWidth: 1600, imageHeight: 1200);

    test('marks bins under the frame and reports fraction', () {
      final cov = CoverageTracker(lonBins: 36, latBins: 18, fullSphere: true);
      // Identity device (screen up): camera faces the ground.
      cov.markFrame(Quaternion.identity, cam);
      expect(cov.fraction, greaterThan(0));
      expect(cov.fraction, lessThan(1));
    });

    test('panorama sweep covers the middle band', () {
      final cov = CoverageTracker(lonBins: 36, latBins: 18, fullSphere: false);
      // Upright portrait aiming at the horizon, sweeping full yaw.
      final upright =
          Quaternion.axisAngle(const Vector3(1, 0, 0), -math.pi / 2);
      for (var k = 0; k < 12; k++) {
        final yaw =
            Quaternion.axisAngle(const Vector3(0, 0, 1), k * math.pi / 6);
        cov.markFrame(yaw * upright, cam);
      }
      expect(cov.fraction, greaterThan(0.6));
    });

    test('nextGap points at uncovered area and nulls when done', () {
      final cov = CoverageTracker(lonBins: 12, latBins: 6, fullSphere: true);
      expect(cov.nextGap(0, 0), isNotNull);
      // Wide camera straight down + straight up + horizon sweep ≈ all bins.
      final wide =
          FrameCamera(fovHDeg: 120, imageWidth: 1000, imageHeight: 1000);
      cov.markFrame(Quaternion.identity, wide); // camera faces down
      cov.markFrame(
        Quaternion.axisAngle(const Vector3(1, 0, 0), math.pi), // faces up
        wide,
      );
      final upright =
          Quaternion.axisAngle(const Vector3(1, 0, 0), -math.pi / 2);
      for (var k = 0; k < 6; k++) {
        final yaw =
            Quaternion.axisAngle(const Vector3(0, 0, 1), k * math.pi / 3);
        cov.markFrame(yaw * upright, wide);
      }
      // With a 120° diagonal camera, most of the sphere should be covered.
      expect(cov.fraction, greaterThan(0.9));
    });

    test('isLonBinCovered agrees with markFrame', () {
      final cov = CoverageTracker(lonBins: 36, latBins: 18);
      expect(cov.isLonBinCovered(0), isFalse);
      final wide =
          FrameCamera(fovHDeg: 120, imageWidth: 1000, imageHeight: 1000);
      cov.markFrame(Quaternion.identity, wide);
      var covered = 0;
      for (var i = 0; i < 36; i++) {
        if (cov.isLonBinCovered(i)) covered++;
      }
      expect(covered, greaterThan(0));
    });

    test('reset clears coverage', () {
      final cov = CoverageTracker();
      cov.markFrame(Quaternion.identity, cam);
      cov.reset();
      expect(cov.fraction, equals(0));
    });
  });
}

/// Builds a JPEG with an APP1/EXIF segment containing just the orientation.
Uint8List _minimalJpeg({required int orientation, required bool littleEndian}) {
  final tiff = <int>[];
  void u16(int v, {required bool le}) {
    if (le) {
      tiff
        ..add(v & 0xFF)
        ..add((v >> 8) & 0xFF);
    } else {
      tiff
        ..add((v >> 8) & 0xFF)
        ..add(v & 0xFF);
    }
  }

  void u32(int v, {required bool le}) {
    if (le) {
      tiff
        ..add(v & 0xFF)
        ..add((v >> 8) & 0xFF)
        ..add((v >> 16) & 0xFF)
        ..add((v >> 24) & 0xFF);
    } else {
      tiff
        ..add((v >> 24) & 0xFF)
        ..add((v >> 16) & 0xFF)
        ..add((v >> 8) & 0xFF)
        ..add(v & 0xFF);
    }
  }

  final le = littleEndian;
  // TIFF header: byte order mark + 42 + IFD0 offset (8).
  tiff
    ..add(le ? 0x49 : 0x4D)
    ..add(le ? 0x49 : 0x4D);
  u16(42, le: le);
  u32(8, le: le);
  // IFD0: 1 entry, tag 0x0112 (orientation), type SHORT (3), count 1,
  // value in the first two bytes of the value field.
  u16(1, le: le);
  u16(0x0112, le: le);
  u16(3, le: le);
  u32(1, le: le);
  u16(orientation, le: le);
  tiff
    ..add(0)
    ..add(0);
  // Next IFD offset = 0.
  u32(0, le: le);

  final exif = <int>[
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // 'Exif\0\0'
    ...tiff,
  ];
  final segLen = exif.length + 2;
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE1, // APP1
    (segLen >> 8) & 0xFF, segLen & 0xFF,
    ...exif,
    0xFF, 0xD9, // EOI
  ]);
}
