import 'dart:io';
import 'dart:typed_data';

import '../capture/stitching/xmp_pano.dart';

/// Result of validating a candidate photo for import into My 360s.
sealed class ImportCheck {
  const ImportCheck();
}

/// The photo is a full equirectangular 360° image and can be imported.
class ImportOk extends ImportCheck {
  const ImportOk({required this.width, required this.height});
  final int width;
  final int height;
}

/// The photo is not importable; [reason] is user-presentable.
class ImportRejected extends ImportCheck {
  const ImportRejected(this.reason);
  final String reason;
}

/// Validates an image file the way the original app's import flow does:
/// the photo must be a 2:1 equirectangular 360° image (the original shows
/// its "Not a 360° Photo" alert otherwise).
///
/// The check accepts a photo when *either* condition holds:
/// 1. it carries GPano XMP metadata with an equirectangular projection —
///    the authoritative signal used by Google services; or
/// 2. its pixel aspect ratio is 2:1 within [aspectTolerance] (many
///    photosphere exports carry no metadata at all).
ImportCheck validateForImport(
  Uint8List bytes, {
  double aspectTolerance = 0.02,
}) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return const ImportRejected(
        'Not a 360° photo: the file is not a JPEG image.');
  }

  // Authoritative path: GPano metadata.
  if (hasGpanoXmp(bytes)) {
    final projection = gpanoProjectionType(bytes);
    if (projection == 'equirectangular') {
      final (w, h) = jpegSize(bytes);
      if (w != null && h != null) {
        return ImportOk(width: w, height: h);
      }
      return const ImportRejected(
          'The image could not be decoded. Please try another file.');
    }
    return ImportRejected(
        'Not a 360° photo: the metadata declares "$projection" instead of '
        'equirectangular.');
  }

  // Fallback: 2:1 aspect ratio.
  final (w, h) = jpegSize(bytes);
  if (w == null || h == null || w == 0 || h == 0) {
    return const ImportRejected(
        'The image could not be decoded. Please try another file.');
  }
  final ratio = w / h;
  if ((ratio - 2).abs() > aspectTolerance) {
    return const ImportRejected(
        'Not a 360° photo: a 360° photo must be an equirectangular image '
        'with a 2:1 width-to-height ratio.');
  }
  return ImportOk(width: w, height: h);
}

/// Reads the pixel dimensions from a JPEG's SOF marker (no full decode).
(int?, int?) jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return (null, null);
  }
  var i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] != 0xFF) return (null, null);
    final marker = bytes[i + 1];
    if (marker == 0xD8 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0x01) {
      i += 2;
      continue;
    }
    if (marker == 0xDA) return (null, null); // scan data: no SOF found
    final len = (bytes[i + 2] << 8) | bytes[i + 3];
    // SOF0..SOF15 except DHT (C4), JPG (C8), DAC (CC).
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      if (i + 9 <= bytes.length) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        return (w, h);
      }
      return (null, null);
    }
    i += 2 + len;
  }
  return (null, null);
}

/// Reads a file into bytes (small helper for the import button flow).
Future<Uint8List> readFileBytes(String path) async {
  final data = await File(path).readAsBytes();
  return data;
}
