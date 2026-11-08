import 'dart:typed_data';

/// Minimal JPEG APP1/EXIF orientation reader.
///
/// The camera plugin returns JPEGs whose pixels are stored in sensor
/// orientation with an EXIF `Orientation` tag describing how to rotate them
/// upright. Dart's image decoder does not apply EXIF rotation, so we parse
/// just that one tag ourselves.
abstract final class ExifOrientation {
  /// Returns the EXIF orientation 1..8, or 1 when absent/unparseable.
  static int read(Uint8List jpeg) {
    if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return 1;

    var i = 2;
    while (i + 4 <= jpeg.length) {
      if (jpeg[i] != 0xFF) return 1;
      final marker = jpeg[i + 1];
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      if (marker == 0xDA) return 1; // start of scan — no EXIF found
      final segLen = (jpeg[i + 2] << 8) | jpeg[i + 3];
      if (segLen < 2) return 1;

      if (marker == 0xE1 && i + 4 + 6 <= jpeg.length) {
        final exifHead = jpeg.sublist(i + 4, i + 10);
        const exifSig = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // 'Exif\0\0'
        var isExif = true;
        for (var k = 0; k < 6; k++) {
          if (exifHead[k] != exifSig[k]) {
            isExif = false;
            break;
          }
        }
        if (isExif) {
          return _parseTiffOrientation(jpeg, i + 10);
        }
      }
      i += 2 + segLen;
    }
    return 1;
  }

  static int _parseTiffOrientation(Uint8List b, int tiffStart) {
    if (tiffStart + 8 > b.length) return 1;
    final endian = b[tiffStart];
    late int Function(int, int) u16;
    late int Function(int, int, int, int) u32;
    if (endian == 0x49) {
      // 'II' little endian
      u16 = (p, _) => b[p] | (b[p + 1] << 8);
      u32 = (p, _, __, ___) =>
          b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24);
    } else if (endian == 0x4D) {
      // 'MM' big endian
      u16 = (p, _) => (b[p] << 8) | b[p + 1];
      u32 = (p, _, __, ___) =>
          (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
    } else {
      return 1;
    }

    final ifdOffset = u32(tiffStart + 4, 0, 0, 0);
    final ifd = tiffStart + ifdOffset;
    if (ifd + 2 > b.length) return 1;
    final entryCount = u16(ifd, 0);
    for (var e = 0; e < entryCount; e++) {
      final entry = ifd + 2 + e * 12;
      if (entry + 12 > b.length) return 1;
      final tag = u16(entry, 0);
      if (tag == 0x0112) {
        // Orientation
        final value = u16(entry + 8, 0);
        return (value >= 1 && value <= 8) ? value : 1;
      }
    }
    return 1;
  }
}
