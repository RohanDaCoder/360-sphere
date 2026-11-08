import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import 'exif_orientation.dart';

/// Decoding, rotation and encoding helpers for camera frames.
abstract final class FrameUtils {
  /// Decode JPEG bytes to a [ui.Image], downscaled so the long edge is at
  /// most [maxLongEdge] px (keeps stitching textures light).
  static Future<ui.Image> decodeJpeg(
    Uint8List bytes, {
    int maxLongEdge = 1920,
  }) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: null,
      targetHeight: null,
      allowUpscaling: false,
    );
    var image = (await codec.getNextFrame()).image;
    final longEdge = math.max(image.width, image.height);
    if (longEdge > maxLongEdge) {
      final scale = maxLongEdge / longEdge;
      final w = (image.width * scale).round();
      final h = (image.height * scale).round();
      image = await _resample(image, w, h);
    }
    return image;
  }

  /// Apply the standard EXIF orientation transform (1..8).
  static Future<ui.Image> applyExif(ui.Image image, int orientation) async {
    switch (orientation) {
      case 1:
        return image;
      case 2:
        return _transform(image, rotate90: false, flipX: true);
      case 3:
        return _rotate(image, math.pi);
      case 4:
        return _transform(image, rotate90: false, flipX: true, extraPi: true);
      case 5:
        return _transform(image, rotate90: true, flipX: true);
      case 6:
        return _rotateQuarter(image, clockwise: true);
      case 7:
        return _transform(image, rotate90: true, flipX: false, flip: true);
      case 8:
        return _rotateQuarter(image, clockwise: false);
      default:
        return image;
    }
  }

  /// Rotate by an exact multiple of 90° (used by the aspect heuristic when
  /// the JPEG carries no usable EXIF).
  static Future<ui.Image> rotateQuarter(ui.Image image,
          {required bool clockwise}) =>
      _rotateQuarter(image, clockwise: clockwise);

  static Future<ui.Image> _rotateQuarter(ui.Image image,
      {required bool clockwise}) async {
    final recorder = ui.PictureRecorder();
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, h, w));
    canvas.translate(clockwise ? h : 0, clockwise ? 0 : w);
    canvas.rotate(clockwise ? math.pi / 2 : -math.pi / 2);
    canvas.drawImage(
        image, ui.Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    final p = recorder.endRecording();
    final out = await p.toImage(image.height, image.width);
    p.dispose();
    return out;
  }

  static Future<ui.Image> _rotate(ui.Image image, double radians) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder,
        ui.Rect.fromLTWH(
            0, 0, image.width.toDouble(), image.height.toDouble()));
    canvas.translate(image.width / 2, image.height / 2);
    canvas.rotate(radians);
    canvas.drawImage(image, ui.Offset(-image.width / 2, -image.height / 2),
        Paint()..filterQuality = FilterQuality.medium);
    final p = recorder.endRecording();
    final out = await p.toImage(image.width, image.height);
    p.dispose();
    return out;
  }

  /// Combined transforms for the mirrored EXIF cases.
  static Future<ui.Image> _transform(
    ui.Image image, {
    required bool rotate90,
    required bool flipX,
    bool extraPi = false,
    bool flip = false,
  }) async {
    ui.Image src = image;
    if (rotate90) src = await _rotateQuarter(src, clockwise: true);
    if (extraPi) src = await _rotate(src, math.pi);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder,
        ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()));
    if (flip) {
      canvas.translate(0, src.height.toDouble());
      canvas.scale(1, -1);
    }
    if (flipX) {
      canvas.translate(src.width.toDouble(), 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImage(
        src, ui.Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    final p = recorder.endRecording();
    final out = await p.toImage(src.width, src.height);
    p.dispose();
    return out;
  }

  static Future<ui.Image> _resample(ui.Image image, int w, int h) async {
    final recorder = ui.PictureRecorder();
    final canvas =
        ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    final src =
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    canvas.drawImageRect(
        image, src, dst, Paint()..filterQuality = FilterQuality.medium);
    final p = recorder.endRecording();
    final out = await p.toImage(w, h);
    p.dispose();
    return out;
  }

  /// Encode a [ui.Image] to JPEG bytes via package:image (Street View and
  /// the Photo Sphere Viewer both expect JPEG).
  static Future<Uint8List> encodeJpeg(ui.Image image,
      {int quality = 88}) async {
    final data =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) throw StateError('Could not read image bytes');
    // Copy into an exactly-sized buffer: package:image requires a ByteBuffer
    // sized to width*height*channels.
    final rgba = Uint8List.fromList(data.buffer.asUint8List());
    final decoded = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: rgba.buffer,
      numChannels: 4,
    );
    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }

  /// Downscaled JPEG thumbnail for the gallery grid.
  static Future<Uint8List> makeThumbnail(ui.Image image,
      {int longEdge = 512}) async {
    final scale = longEdge / math.max(image.width, image.height);
    final w = math.max(1, (image.width * scale).round());
    final h = math.max(1, (image.height * scale).round());
    final small = await _resample(image, w, h);
    return encodeJpeg(small, quality: 80);
  }

  /// Full EXIF-aware decode: returns an upright frame.
  static Future<ui.Image> decodeUpright(
    Uint8List jpegBytes, {
    int maxLongEdge = 1920,
    int manualFix = 0,
  }) async {
    var image = await decodeJpeg(jpegBytes, maxLongEdge: maxLongEdge);
    final orientation = ExifOrientation.read(jpegBytes);
    if (orientation != 1) {
      image = await applyExif(image, orientation);
    }
    if (manualFix != 0) {
      image = await _rotateQuarter(image, clockwise: manualFix > 0);
    }
    return image;
  }
}
