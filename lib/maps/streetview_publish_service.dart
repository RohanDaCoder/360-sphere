import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Client for the Google Street View Publish API
/// (https://developers.google.com/streetviewpublish/reference/rest).
///
/// Publishing a photo to Street View makes it eligible to appear on Google
/// Maps. The flow is three calls:
///   1. `photo:startUpload` → short-lived upload URL
///   2. `PUT` the JPEG bytes to that URL
///   3. `POST /v1/photo` with the upload reference + pose (lat/lng/heading)
class StreetViewPublishService {
  StreetViewPublishService({
    http.Client? client,
    required this.accessTokenProvider,
    http.Client? uploadClient,
  })  : _client = client ?? http.Client(),
        _uploadClient = uploadClient ?? http.Client();

  static const String _base = 'https://streetviewpublish.googleapis.com/v1';

  /// Scope required by the API.
  static const String scope =
      'https://www.googleapis.com/auth/streetviewpublish';

  final http.Client _client;
  final http.Client _uploadClient;
  final Future<String?> Function() accessTokenProvider;

  Future<Map<String, String>> _headers({String? contentType}) async => {
        'Authorization': 'Bearer ${await accessTokenProvider()}',
        if (contentType != null) 'Content-Type': contentType,
      };

  /// Step 1: request an upload session URL.
  Future<String> startUpload() async {
    final res = await _client.post(
      Uri.parse('$_base/photo:startUpload'),
      headers: await _headers(contentType: 'application/json'),
      body: '{}',
    );
    _check(res, 'photo:startUpload');
    final uploadUrl =
        (jsonDecode(res.body) as Map<String, dynamic>)['uploadUrl'] as String?;
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw StreetViewException('startUpload returned no uploadUrl');
    }
    return uploadUrl;
  }

  /// Step 2: upload the (equirectangular, 2:1) JPEG bytes.
  Future<void> uploadBytes(String uploadUrl, Uint8List jpeg) async {
    final res = await _uploadClient.put(
      Uri.parse(uploadUrl),
      headers: await _headers(contentType: 'application/octet-stream'),
      body: jpeg,
    );
    _check(res, 'upload');
  }

  /// Step 3: register the photo with its geographic pose.
  ///
  /// [headingDeg] is the compass heading of the photo center (0–360).
  /// Returns the new photo's resource name (id), e.g.
  /// `UsCYASnSYm6pVzgD4YqJdTbB`.
  Future<String> createPhoto({
    required String uploadUrl,
    required double latitude,
    required double longitude,
    double? headingDeg,
    DateTime? captureTime,
  }) async {
    final body = <String, dynamic>{
      'uploadReference': {'uploadUrl': uploadUrl},
      'pose': {
        'latLng': {'latitude': latitude, 'longitude': longitude},
        if (headingDeg != null) 'heading': headingDeg,
      },
      if (captureTime != null)
        'captureTimeSeconds': captureTime.millisecondsSinceEpoch ~/ 1000,
    };
    final res = await _client.post(
      Uri.parse('$_base/photo'),
      headers: await _headers(contentType: 'application/json'),
      body: jsonEncode(body),
    );
    _check(res, 'photo.create');
    final photo = jsonDecode(res.body) as Map<String, dynamic>;
    final id = photo['photoId']?['id'] as String?;
    if (id == null || id.isEmpty) {
      throw StreetViewException('photo.create returned no photoId');
    }
    return id;
  }

  /// Convenience: run the full three-step publish.
  Future<String> publish({
    required Uint8List jpeg,
    required double latitude,
    required double longitude,
    double? headingDeg,
  }) async {
    final url = await startUpload();
    await uploadBytes(url, jpeg);
    return createPhoto(
      uploadUrl: url,
      latitude: latitude,
      longitude: longitude,
      headingDeg: headingDeg,
      captureTime: DateTime.now(),
    );
  }

  void _check(http.Response res, String step) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw StreetViewException(
      '$step failed (HTTP ${res.statusCode}): ${_summarize(res.body)}',
    );
  }

  static String _summarize(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final err = map['error'] as Map<String, dynamic>?;
      if (err != null) {
        return '${err['status']}: ${err['message']}';
      }
      return body;
    } catch (_) {
      return body.length > 300 ? '${body.substring(0, 300)}…' : body;
    }
  }

  void dispose() {
    _client.close();
    _uploadClient.close();
  }
}

class StreetViewException implements Exception {
  StreetViewException(this.message);

  final String message;

  @override
  String toString() => message;
}
