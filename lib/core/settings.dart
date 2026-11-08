import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-adjustable capture settings.
class Settings {
  Settings({
    this.equirectWidth = 4096,
    this.watermark = true,
    this.cameraFovDegrees = 62,
    this.compassAssist = true,
    this.frameRotationFix = 0,
  })  : assert(equirectWidth == 2048 || equirectWidth == 4096),
        assert(cameraFovDegrees >= 40 && cameraFovDegrees <= 90),
        assert(frameRotationFix >= -1 && frameRotationFix <= 1);

  /// Equirectangular output width; height is always width / 2.
  final int equirectWidth;
  int get equirectHeight => equirectWidth ~/ 2;

  /// Stamp a small "360sphere" signature on saved photos.
  final bool watermark;

  /// Horizontal field of view of the back camera, in degrees.
  final double cameraFovDegrees;

  /// Apply magnetometer correction to bound gyro yaw drift.
  final bool compassAssist;

  /// Manual correction when device frames come out rotated:
  /// -1 = rotate counter-clockwise, 0 = auto, 1 = clockwise.
  final int frameRotationFix;

  Settings copyWith({
    int? equirectWidth,
    bool? watermark,
    double? cameraFovDegrees,
    bool? compassAssist,
    int? frameRotationFix,
  }) =>
      Settings(
        equirectWidth: equirectWidth ?? this.equirectWidth,
        watermark: watermark ?? this.watermark,
        cameraFovDegrees: cameraFovDegrees ?? this.cameraFovDegrees,
        compassAssist: compassAssist ?? this.compassAssist,
        frameRotationFix: frameRotationFix ?? this.frameRotationFix,
      );

  Map<String, dynamic> toJson() => {
        'equirectWidth': equirectWidth,
        'watermark': watermark,
        'cameraFovDegrees': cameraFovDegrees,
        'compassAssist': compassAssist,
        'frameRotationFix': frameRotationFix,
      };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        equirectWidth: json['equirectWidth'] as int? ?? 4096,
        watermark: json['watermark'] as bool? ?? true,
        cameraFovDegrees: (json['cameraFovDegrees'] as num?)?.toDouble() ?? 62,
        compassAssist: json['compassAssist'] as bool? ?? true,
        frameRotationFix: json['frameRotationFix'] as int? ?? 0,
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
