/// Domain models for 360Sphere.
library;

/// Capture mode, mirroring the mode set offered by the original app
/// (panorama horizontal / vertical / wide-angle / fisheye + photosphere).
///
/// The recreation implements the two modes that drive the core pipeline:
/// the full-sphere photosphere and the single-row horizontal panorama.
enum CaptureMode {
  photosphere('360° Photosphere'),
  panoramaHorizontal('Panorama (horizontal)');

  const CaptureMode(this.label);
  final String label;

  /// Whether this mode expects full-sphere coverage (pitch sweep included).
  bool get wantsFullSphere => this == CaptureMode.photosphere;
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
    this.watermarked = false,
    this.streetViewPhotoId,
  });

  final String id;
  String name;
  final DateTime createdAt;

  /// File name of the equirectangular JPEG inside the app's sphere store.
  final String imageFileName;
  final int width;
  final int height;
  final int frameCount;
  final bool watermarked;

  /// Set once the photo has been published to Google Street View / Maps.
  String? streetViewPhotoId;

  factory Photosphere.fromJson(Map<String, dynamic> json) => Photosphere(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled 360°',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        imageFileName: json['imageFileName'] as String,
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        frameCount: json['frameCount'] as int? ?? 0,
        watermarked: json['watermarked'] as bool? ?? false,
        streetViewPhotoId: json['streetViewPhotoId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'imageFileName': imageFileName,
        'width': width,
        'height': height,
        'frameCount': frameCount,
        'watermarked': watermarked,
        'streetViewPhotoId': streetViewPhotoId,
      };
}
