import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/maps/streetview_errors.dart';
import 'package:sphere360/maps/streetview_publish_service.dart';

void main() {
  group('classifyStreetViewError', () {
    test('location errors → Location Required', () {
      final e = classifyStreetViewError(
          StreetViewException('photo.create failed (HTTP 400): '
              'INVALID_ARGUMENT: pose.latitude is required'));
      expect(e.kind, StreetViewErrorKind.locationRequired);
      expect(e.title, 'Location Required');
      expect(e.message, contains('valid GPS location'));
    });

    test('size errors → Photo Too Large', () {
      final e = classifyStreetViewError(StreetViewException(
          'upload failed (HTTP 413): request entity too large'));
      expect(e.kind, StreetViewErrorKind.photoTooLarge);
      expect(e.title, 'Photo Too Large');
    });

    test('already-uploaded → Already Uploaded', () {
      final e = classifyStreetViewError(StreetViewException(
          'photo.create failed (HTTP 409): ALREADY_EXISTS: photo exists'));
      expect(e.kind, StreetViewErrorKind.alreadyUploaded);
      expect(e.title, 'Already Uploaded');
    });

    test('network / timeout → Connection Error', () {
      final e = classifyStreetViewError(StreetViewException(
          'upload failed: SocketException: connection reset'));
      expect(e.kind, StreetViewErrorKind.connection);
      expect(e.title, 'Connection Error');
      expect(e.message, contains('internet connection'));
    });

    test('unauthenticated → Token Expired', () {
      final e = classifyStreetViewError(StreetViewException(
          'photo.create failed (HTTP 401): UNAUTHENTICATED'));
      expect(e.kind, StreetViewErrorKind.tokenExpired);
      expect(e.title, 'Google Account Token Expired');
    });

    test('permission denied → Permission Required', () {
      final e = classifyStreetViewError(StreetViewException(
          'photo.create failed (HTTP 403): PERMISSION_DENIED: scope missing'));
      expect(e.kind, StreetViewErrorKind.permissionRequired);
      expect(e.title, 'Permission Required');
    });

    test('invalid argument without location → Not a 360° Photo', () {
      final e = classifyStreetViewError(StreetViewException(
          'photo.create failed (HTTP 400): INVALID_ARGUMENT: not a 360 photo'));
      expect(e.kind, StreetViewErrorKind.notA360Photo);
      expect(e.title, 'Not a 360° Photo');
    });

    test('anything else → Upload Failed', () {
      final e = classifyStreetViewError(
          StreetViewException('startUpload failed (HTTP 500): backend error'));
      expect(e.kind, StreetViewErrorKind.uploadFailed);
      expect(e.title, 'Upload Failed');
    });

    test('socket exception outside StreetViewException → Connection Error', () {
      final e = classifyStreetViewError(
          Exception('Failed host lookup: streetviewpublish.googleapis.com'));
      expect(e.kind, StreetViewErrorKind.connection);
    });
  });

  group('preflightCheck', () {
    test('rejects a JPEG without GPano metadata', () {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x10, 'JFIF'.codeUnits[0], // junk after
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
      ]);
      final e = preflightCheck(jpeg);
      expect(e, isNotNull);
      expect(e!.kind, StreetViewErrorKind.notA360Photo);
      expect(e.title, 'Not a 360° Photo');
    });

    test('accepts a JPEG with equirectangular GPano metadata', () {
      final b = BytesBuilder();
      b.add([0xFF, 0xD8]);
      final packet = utf8.encode('http://ns.adobe.com/xap/1.0/\x00<?xpacket?>'
          '<rdf:Description xmlns:GPano='
          '"http://ns.google.com/photos/1.0/panorama/" '
          'GPano:ProjectionType="equirectangular"/>');
      b.add([0xFF, 0xE1, (packet.length + 2) >> 8, (packet.length + 2) & 0xFF]);
      b.add(packet);
      final jpeg = b.toBytes();
      expect(preflightCheck(jpeg), isNull);
    });
  });
}
