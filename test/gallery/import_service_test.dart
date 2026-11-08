import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/capture/stitching/xmp_pano.dart';
import 'package:sphere360/gallery/import_service.dart';

// Reuse the minimal-JPEG builder from the XMP test (kept local to avoid a
// shared helper file).
Uint8List minimalJpeg({int width = 4096, int height = 2048}) {
  final b = BytesBuilder();
  b.add([0xFF, 0xD8]);
  b.add([0xFF, 0xE0, 0x00, 0x10]);
  b.add('JFIF\x00'.codeUnits);
  b.add([0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]);
  b.add([0xFF, 0xDB, 0x00, 0x06, 0x01, 0x01, 0x01, 0x01]);
  b.add([0xFF, 0xC0, 0x00, 0x0B, 0x08]);
  b.add([(height >> 8) & 0xFF, height & 0xFF]);
  b.add([(width >> 8) & 0xFF, width & 0xFF]);
  b.add([0x01, 0x01, 0x11, 0x00]);
  b.add([0xFF, 0xD9]);
  return b.toBytes();
}

void main() {
  group('validateForImport', () {
    test('accepts a 2:1 JPEG without metadata (aspect fallback)', () {
      final check = validateForImport(minimalJpeg(width: 4096, height: 2048));
      expect(check, isA<ImportOk>());
      final ok = check as ImportOk;
      expect(ok.width, 4096);
      expect(ok.height, 2048);
    });

    test('accepts a photo with equirectangular GPano metadata', () {
      final jpeg = writeGpanoXmp(minimalJpeg(width: 2048, height: 1024),
          width: 2048, height: 1024);
      final check = validateForImport(jpeg);
      expect(check, isA<ImportOk>());
    });

    test('accepts a slightly-off 2:1 ratio within tolerance', () {
      final check = validateForImport(minimalJpeg(width: 2000, height: 1001));
      expect(check, isA<ImportOk>());
    });

    test('rejects a non-2:1 photo without metadata', () {
      final check = validateForImport(minimalJpeg(width: 4032, height: 3024));
      expect(check, isA<ImportRejected>());
      expect((check as ImportRejected).reason, contains('Not a 360° photo'));
    });

    test('rejects non-JPEG bytes', () {
      final check =
          validateForImport(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]));
      expect(check, isA<ImportRejected>());
      expect((check as ImportRejected).reason, contains('not a JPEG'));
    });

    test('rejects GPano metadata with a different projection', () {
      // Hand-build an XMP packet with a cubic projection type.
      final base = minimalJpeg(width: 4096, height: 2048);
      final packet =
          utf8.encode('http://ns.adobe.com/xap/1.0/\x00<?xpacket begin=""?>'
              '<x:xmpmeta><rdf:RDF><rdf:Description '
              'xmlns:GPano="http://ns.google.com/photos/1.0/panorama/" '
              'GPano:ProjectionType="cubic"/></rdf:RDF></x:xmpmeta>');
      final b = BytesBuilder();
      b.add([0xFF, 0xD8, 0xFF, 0xE1]);
      final len = packet.length + 2;
      b.add([(len >> 8) & 0xFF, len & 0xFF]);
      b.add(packet);
      b.add(base.sublist(2));
      final jpeg = b.toBytes();

      final check = validateForImport(jpeg);
      expect(check, isA<ImportRejected>());
      expect((check as ImportRejected).reason, contains('cubic'));
    });
  });

  group('jpegSize', () {
    test('reads dimensions from the SOF marker', () {
      final (w, h) = jpegSize(minimalJpeg(width: 6000, height: 3000));
      expect(w, 6000);
      expect(h, 3000);
    });

    test('returns nulls for garbage', () {
      final (w, h) = jpegSize(Uint8List(20));
      expect(w, isNull);
      expect(h, isNull);
    });
  });
}
