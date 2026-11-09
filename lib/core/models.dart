/// Domain models for 360Sphere.
library;

/// Capture mode, mirroring the mode set offered by the original app
/// (panorama horizontal / vertical / wide-angle / fisheye + photosphere —
/// mode names recovered from the bundle's string table).
enum CaptureMode {
  photosphere('360° Photosphere'),
  panoramaHorizontal('Panorama (horizontal)'),
  panoramaVertical('Panorama (vertical)'),
  panoramaWideAngle('Panorama (wide-angle)'),
  panoramaFisheye('Panorama (fisheye)');

  const CaptureMode(this.label);
  final String label;

  /// Whether this mode expects full-sphere coverage (pitch sweep included).
  bool get wantsFullSphere => this == CaptureMode.photosphere;

  /// Whether frames come from an equidistant fisheye lens (≈180°) instead of
  /// a regular rectilinear camera — changes the warp model in
  /// [FrameCamera].
  bool get usesFisheyeLens => this == CaptureMode.panoramaFisheye;
}

/// Where a photosphere was taken — captured at the start of a capture
/// session (the original app records the same `geo_location`
/// {latitude, longitude, heading} with each photo and reuses it as the
/// Street View pose when publishing).
class GeoPose {
  GeoPose({
    required this.latitude,
    required this.longitude,
    this.heading,
    this.accuracy,
  });

  final double latitude;
  final double longitude;

  /// Course/compass heading in degrees (0–360), when known.
  final double? heading;

  /// GPS accuracy radius in meters, when known.
  final double? accuracy;

  factory GeoPose.fromJson(Map<String, dynamic> json) => GeoPose(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        heading: (json['heading'] as num?)?.toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (heading != null) 'heading': heading,
        if (accuracy != null) 'accuracy': accuracy,
      };
}

/// A captured and stitched 360° photo ("photosphere").
class Photosphere {
  Photosphere({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.imageFileName,
    required this.width,
    required this.height,
    required this.frameCount,
    this.description = '',
    this.watermarked = false,
    this.geoLocation,
    this.streetViewPhotoId,
    this.streetViewShareLink,
  });

  final String id;
  String name;

  /// Free-form note attached to the photo (the original's PhotoNameScreen
  /// collects name + description; name is capped at 200 characters there).
  String description;
  final DateTime createdAt;

  /// File name of the equirectangular JPEG inside the app's sphere store.
  final String imageFileName;
  final int width;
  final int height;
  final int frameCount;
  final bool watermarked;

  /// Position (and heading, when known) where the photo was captured —
  /// used as the Street View pose when publishing, like the original's
  /// `geo_location` on its photo records.
  final GeoPose? geoLocation;

  /// Set once the photo has been published to Google Street View / Maps.
  String? streetViewPhotoId;

  /// Google's `shareLink` for the published photo (a Google Maps URL),
  /// returned by `photo.create` and kept alongside the id (the original
  /// does the same; its viewer's Google Maps button opens this link).
  String? streetViewShareLink;

  factory Photosphere.fromJson(Map<String, dynamic> json) => Photosphere(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled 360°',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        imageFileName: json['imageFileName'] as String,
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        frameCount: json['frameCount'] as int? ?? 0,
        description: json['description'] as String? ?? '',
        watermarked: json['watermarked'] as bool? ?? false,
        geoLocation: json['geoLocation'] == null
            ? null
            : GeoPose.fromJson(json['geoLocation'] as Map<String, dynamic>),
        streetViewPhotoId: json['streetViewPhotoId'] as String?,
        streetViewShareLink: json['streetViewShareLink'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'imageFileName': imageFileName,
        'width': width,
        'height': height,
        'frameCount': frameCount,
        'description': description,
        'watermarked': watermarked,
        if (geoLocation != null) 'geoLocation': geoLocation!.toJson(),
        'streetViewPhotoId': streetViewPhotoId,
        'streetViewShareLink': streetViewShareLink,
      };
}
