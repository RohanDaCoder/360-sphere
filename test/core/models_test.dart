import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/core/models.dart';

void main() {
  group('GeoPose', () {
    test('JSON round-trip keeps every field', () {
      final g = GeoPose(
        latitude: 37.75,
        longitude: -122.42,
        heading: 123.5,
        accuracy: 12.5,
      );
      final back = GeoPose.fromJson(g.toJson());
      expect(back.latitude, g.latitude);
      expect(back.longitude, g.longitude);
      expect(back.heading, g.heading);
      expect(back.accuracy, g.accuracy);
    });

    test('optional fields stay absent from JSON when null', () {
      final json = GeoPose(latitude: 1, longitude: 2).toJson();
      expect(json.containsKey('heading'), isFalse);
      expect(json.containsKey('accuracy'), isFalse);
    });
  });

  group('Photosphere — geo + Street View fields', () {
    Photosphere make() => Photosphere(
          id: 'sp_1',
          name: 'Living room',
          createdAt: DateTime.utc(2026, 11, 9),
          imageFileName: 'sp_1.jpg',
          width: 4096,
          height: 2048,
          frameCount: 33,
          geoLocation: GeoPose(latitude: 10.5, longitude: 20.25, heading: 90),
          streetViewPhotoId: 'abc',
          streetViewShareLink: 'https://www.google.com/maps/abc',
        );

    test('JSON round-trip preserves geoLocation and share link', () {
      final back = Photosphere.fromJson(make().toJson());
      expect(back.geoLocation, isNotNull);
      expect(back.geoLocation!.latitude, 10.5);
      expect(back.geoLocation!.longitude, 20.25);
      expect(back.geoLocation!.heading, 90);
      expect(back.streetViewPhotoId, 'abc');
      expect(back.streetViewShareLink, 'https://www.google.com/maps/abc');
    });

    test('older records without geo / share link still load', () {
      final back = Photosphere.fromJson({
        'id': 'sp_2',
        'name': 'Old',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'imageFileName': 'sp_2.jpg',
        'width': 2048,
        'height': 1024,
        'frameCount': 12,
      });
      expect(back.geoLocation, isNull);
      expect(back.streetViewShareLink, isNull);
    });
  });
}
