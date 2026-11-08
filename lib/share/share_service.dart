import 'dart:io';

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

/// Sharing / saving helpers.
///
/// The original app shares a hosted viewer link; this recreation (core
/// pipeline, no backend) shares the equirectangular image file itself.
abstract final class ShareService {
  static const String shareText =
      'Check out my 360° photo! Captured with 360Sphere';

  static Future<void> shareFile(String path) async {
    await Share.shareXFiles(
      [XFile(path)],
      text: shareText,
      subject: '360° photo',
    );
  }

  static Future<void> saveToGallery(String path) async {
    await Gal.putImage(path, album: '360Sphere');
  }

  static bool exists(String path) => File(path).existsSync();
}
