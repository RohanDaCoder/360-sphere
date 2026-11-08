import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/stitching/xmp_pano.dart';

/// Minimal JPEG: SOI + APP0(JFIF) + DQT + SOF0(4096×2048) + EOI.
/// Good enough for the segment-walking logic (no real image data needed).
Uint8List minimalJpeg({int width = 4096, int height = 2048}) {
  final b = BytesBuilder();
  b.add([0xFF, 0xD8]); // SOI
  // APP0 JFIF
  b.add([0xFF, 0xE0, 0x00, 0x10]);
  b.add(utf8.encode('JFIF\x00'));
  b.add([0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]);
  // DQT (dummy)
  b.add([0xFF, 0xDB, 0x00, 0x06, 0x01, 0x01, 0x01, 0x01]);
  // SOF0: precision 8, height, width, 1 component
  b.add([0xFF, 0xC0, 0x00, 0x0B, 0x08]);
  b.add([(height >> 8) & 0xFF, height & 0xFF]);
  b.add([(width >> 8) & 0xFF, width & 0xFF]);
  b.add([0x01, 0x01, 0x11, 0x00]);
  // EOI
  b.add([0xFF, 0xD9]);
  return b.toBytes();
}

void main() {
  group('buildGpanoXmp', () {
    test('contains the required equirectangular attributes', () {
      final xmp = buildGpanoXmp(width: 4096, height: 2048);
      expect(xmp, contains('GPano:ProjectionType="equirectangular"'));
      expect(xmp, contains('GPano:UsePanoramaViewer="True"'));
      expect(xmp, contains('GPano:FullPanoWidthPixels="4096"'));
      expect(xmp, contains('GPano:FullPanoHeightPixels="2048"'));
      expect(xmp, contains('GPano:CroppedAreaImageWidthPixels="4096"'));
      expect(xmp, contains('GPano:CroppedAreaImageHeightPixels="2048"'));
      expect(xmp, contains('GPano:CroppedAreaLeftPixels="0"'));
      expect(xmp, contains('GPano:CroppedAreaTopPixels="0"'));
      expect(xmp,
          contains('xmlns:GPano="http://ns.google.com/photos/1.0/panorama/"'));
    });

    test('includes heading and title when given', () {
      final xmp = buildGpanoXmp(
        width: 2048,
        height: 1024,
        poseHeadingDegrees: 123.4,
        title: 'My <Place> & "More"',
      );
      expect(xmp, contains('GPano:PoseHeadingDegrees="123.4"'));
      expect(xmp, contains('My &lt;Place&gt; &amp; &quot;More&quot;'));
    });

    test('omits heading when not given', () {
      final xmp = buildGpanoXmp(width: 2048, height: 1024);
      expect(xmp.contains('PoseHeadingDegrees'), isFalse);
    });
  });

  group('writeGpanoXmp', () {
    test('inserts a detectable APP1 right after SOI', () {
      final jpeg = minimalJpeg();
      final out = writeGpanoXmp(jpeg, width: 4096, height: 2048);
      // Still a JPEG.
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      // First segment is APP1 with the XMP header.
      expect(out[2], 0xFF);
      expect(out[3], 0xE1);
      const header = 'http://ns.adobe.com/xap/1.0/\x00';
      // Layout: SOI(2) + FF E1(2) + length(2) + header + packet.
      final body =
          utf8.decode(out.sublist(6 + header.length), allowMalformed: true);
      expect(body, startsWith('<?xpacket'));
      expect(hasGpanoXmp(out), isTrue);
      expect(gpanoProjectionType(out), 'equirectangular');
    });

    test('original bytes are preserved after the inserted segment', () {
      final jpeg = minimalJpeg(width: 8192, height: 4096);
      final out = writeGpanoXmp(jpeg, width: 8192, height: 4096);
      // The tail (EOI) is still the original ending.
      expect(out[out.length - 2], 0xFF);
      expect(out[out.length - 1], 0xD9);
      // Length grows by the packet size, not by accident.
      expect(out.length, greaterThan(jpeg.length));
      expect(out.length - jpeg.length, lessThan(2000));
    });

    test('replaces an existing XMP packet instead of duplicating', () {
      final jpeg = minimalJpeg();
      final once = writeGpanoXmp(jpeg, width: 4096, height: 2048);
      final twice = writeGpanoXmp(once, width: 4096, height: 2048);
      // Only one APP1 XMP segment may exist.
      var count = 0;
      for (var i = 0; i + 4 < twice.length; i++) {
        if (twice[i] == 0xFF && twice[i + 1] == 0xE1) count++;
      }
      expect(count, equals(1));
      expect(gpanoProjectionType(twice), 'equirectangular');
    });

    test('rejects non-JPEG input', () {
      expect(
        () => writeGpanoXmp(Uint8List.fromList([1, 2, 3, 4]),
            width: 10, height: 5),
        throwsArgumentError,
      );
    });
  });

  group('hasGpanoXmp / gpanoProjectionType', () {
    test('false for a plain JPEG without XMP', () {
      expect(hasGpanoXmp(minimalJpeg()), isFalse);
      expect(gpanoProjectionType(minimalJpeg()), isNull);
    });

    test('false for garbage', () {
      expect(hasGpanoXmp(Uint8List(20)), isFalse);
    });
  });
}
