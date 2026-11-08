import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-adjustable capture settings.
class Settings {
  Settings({
    this.equirectWidth = 4096,
    this.watermark = true,
    this.authorName = '',
    this.cameraFovDegrees = 62,
    this.compassAssist = true,
    this.frameRotationFix = 0,
    this.includeFloorCapture = true,
  })  : assert(equirectWidth == 2048 || equirectWidth == 4096),
        assert(cameraFovDegrees >= 40 && cameraFovDegrees <= 180),
        assert(frameRotationFix >= -1 && frameRotationFix <= 1);

  /// Equirectangular output width; height is always width / 2.
  final int equirectWidth;
  int get equirectHeight => equirectWidth ~/ 2;

  /// Stamp a signature on saved photos.
  final bool watermark;

  /// Author name included in the watermark, following the original app's
  /// "Created in … by {author}" pattern. Empty = app signature only.
  final String authorName;

  /// Watermark line rendered on finished spheres.
  String get watermarkLabel {
    final author = authorName.trim();
    return author.isEmpty
        ? 'Created in 360Sphere'
        : 'Created in 360Sphere by $author';
  }

  /// Horizontal field of view of the back camera, in degrees. For the
  /// fisheye mode this is the diagonal (full-circle) FOV of the lens.
  final double cameraFovDegrees;

  /// Apply magnetometer correction to bound gyro yaw drift.
  final bool compassAssist;

  /// Manual correction when device frames come out rotated:
  /// -1 = rotate counter-clockwise, 0 = auto, 1 = clockwise.
  final int frameRotationFix;

  /// Whether the photosphere layout includes the floor dot (the original
  /// app's `inFloorCapture` switch).
  final bool includeFloorCapture;

  Settings copyWith({
    int? equirectWidth,
    bool? watermark,
    String? authorName,
    double? cameraFovDegrees,
    bool? compassAssist,
    int? frameRotationFix,
    bool? includeFloorCapture,
  }) =>
      Settings(
        equirectWidth: equirectWidth ?? this.equirectWidth,
        watermark: watermark ?? this.watermark,
        authorName: authorName ?? this.authorName,
        cameraFovDegrees: cameraFovDegrees ?? this.cameraFovDegrees,
        compassAssist: compassAssist ?? this.compassAssist,
        frameRotationFix: frameRotationFix ?? this.frameRotationFix,
        includeFloorCapture: includeFloorCapture ?? this.includeFloorCapture,
      );

  Map<String, dynamic> toJson() => {
        'equirectWidth': equirectWidth,
        'watermark': watermark,
        'authorName': authorName,
        'cameraFovDegrees': cameraFovDegrees,
        'compassAssist': compassAssist,
        'frameRotationFix': frameRotationFix,
        'includeFloorCapture': includeFloorCapture,
      };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        equirectWidth: json['equirectWidth'] as int? ?? 4096,
        watermark: json['watermark'] as bool? ?? true,
        authorName: json['authorName'] as String? ?? '',
        cameraFovDegrees: (json['cameraFovDegrees'] as num?)?.toDouble() ?? 62,
        compassAssist: json['compassAssist'] as bool? ?? true,
        frameRotationFix: json['frameRotationFix'] as int? ?? 0,
        includeFloorCapture: json['includeFloorCapture'] as bool? ?? true,
      );
}

class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) : _settings = _load(_prefs);

  final SharedPreferences _prefs;
  Settings _settings;

  Settings get settings => _settings;

  static Settings _load(SharedPreferences prefs) {
    final raw = prefs.getString('settings');
    if (raw == null) return Settings();
    try {
      return Settings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Settings();
    }
  }

  Future<void> update(Settings next) async {
    _settings = next;
    notifyListeners();
    await _prefs.setString('settings', jsonEncode(next.toJson()));
  }
}
