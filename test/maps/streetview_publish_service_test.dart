import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sphere360/maps/streetview_publish_service.dart';

/// A [MockClient] whose responses come from a fixed sequence: the first
/// request gets the first handler, the second the second, and so on.
/// Any extra request fails loudly.
http.Client sequenceClient(
    List<http.Response Function(http.Request)> behaviors) {
  var i = 0;
  return MockClient((request) async {
    if (i >= behaviors.length) {
      throw StateError('unexpected request #${i + 1}: ${request.url}');
    }
    final fn = behaviors[i++];
    return fn(request);
  });
}

void main() {
  const token = 'tok';

  group('StreetViewPublishService.createPhoto — request shape', () {
    test('uses pose.latLngPair (the API field name, like the original)',
        () async {
      Map<String, dynamic>? body;
      final client = sequenceClient([
        (req) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'photoId': {'id': 'abc123'},
              'shareLink': 'https://www.google.com/maps/abc123',
            }),
            200,
          );
        },
      ]);
      final api = StreetViewPublishService(
        client: client,
        uploadClient: client,
        accessTokenProvider: () async => token,
      );

      final photo = await api.createPhoto(
        uploadUrl: 'https://upload/here',
        latitude: 37.75,
        longitude: -122.42,
        headingDeg: 123,
        captureTime:
            DateTime.fromMillisecondsSinceEpoch(1731024000 * 1000, isUtc: true),
      );

      final pose = body!['pose'] as Map<String, dynamic>;
      // The API documents the field as Pose.latLngPair; the original app
      // sends exactly this. (`latLng` would silently drop the position.)
      final latLngPair = pose['latLngPair'] as Map<String, dynamic>;
      expect(latLngPair['latitude'], 37.75);
      expect(latLngPair['longitude'], -122.42);
      expect(pose.containsKey('latLng'), isFalse);
      expect(pose['heading'], 123);

      // captureTime is a Timestamp object, not a flat field.
      final captureTime = body!['captureTime'] as Map<String, dynamic>;
      expect(captureTime['seconds'], 1731024000);

      // The original keeps both the id and Google's shareLink.
      expect(photo.id, 'abc123');
      expect(photo.shareLink, 'https://www.google.com/maps/abc123');
    });

    test('omits heading and captureTime when not provided', () async {
      Map<String, dynamic>? body;
      final client = sequenceClient([
        (req) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'photoId': {'id': 'x'},
            }),
            200,
          );
        },
      ]);
      final api = StreetViewPublishService(
        client: client,
        uploadClient: client,
        accessTokenProvider: () async => token,
      );

      await api.createPhoto(
        uploadUrl: 'u',
        latitude: 1,
        longitude: 2,
      );

      final pose = body!['pose'] as Map<String, dynamic>;
      expect(pose.containsKey('heading'), isFalse);
      expect(body!.containsKey('captureTime'), isFalse);
    });

    test('create response without photoId fails', () async {
      final client = sequenceClient([
        (_) => http.Response(jsonEncode({}), 200),
      ]);
      final api = StreetViewPublishService(
        client: client,
        uploadClient: client,
        accessTokenProvider: () async => token,
      );

      expect(
        () => api.createPhoto(
          uploadUrl: 'u',
          latitude: 1,
          longitude: 2,
        ),
        throwsA(isA<StreetViewException>()),
      );
    });
  });

  group('StreetViewPublishService.publish — full flow', () {
    test('runs startUpload → upload → create and returns id + shareLink',
        () async {
      final calls = <String>[];
      http.Response respond(String label, http.Request req) {
        calls.add(label);
        switch (label) {
          case 'start':
            return http.Response(
              jsonEncode({'uploadUrl': 'https://gcs/upload-session'}),
              200,
            );
          case 'upload':
            expect(req.method, 'PUT');
            expect(req.url.toString(), 'https://gcs/upload-session');
            expect(req.bodyBytes, Uint8List.fromList([1, 2, 3]));
            return http.Response('', 200);
          case 'create':
            expect(req.url.toString(), endsWith('/v1/photo'));
            return http.Response(
              jsonEncode({
                'photoId': {'id': 'final-id'},
                'shareLink': 'https://maps.link',
              }),
              200,
            );
        }
        throw StateError('unreachable');
      }

      final client = sequenceClient([
        (r) => respond('start', r),
        (r) => respond('upload', r),
        (r) => respond('create', r),
      ]);
      final api = StreetViewPublishService(
        client: client,
        uploadClient: client,
        accessTokenProvider: () async => token,
      );

      final photo = await api.publish(
        jpeg: Uint8List.fromList([1, 2, 3]),
        latitude: 10,
        longitude: 20,
        headingDeg: 90,
        captureTime: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

      expect(calls, ['start', 'upload', 'create']);
      expect(photo.id, 'final-id');
      expect(photo.shareLink, 'https://maps.link');
    });

    test('surfaces HTTP errors as StreetViewException with status text',
        () async {
      final client = sequenceClient([
        (_) => http.Response(
              jsonEncode({
                'error': {'status': 'INVALID_ARGUMENT', 'message': 'no pose'}
              }),
              400,
            ),
      ]);
      final api = StreetViewPublishService(
        client: client,
        uploadClient: client,
        accessTokenProvider: () async => token,
      );

      expect(
        () => api.startUpload(),
        throwsA(isA<StreetViewException>()
            .having((e) => e.message, 'message', contains('INVALID_ARGUMENT'))),
      );
    });
  });
}
