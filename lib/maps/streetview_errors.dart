import 'dart:typed_data';

import '../capture/stitching/xmp_pano.dart';
import 'streetview_publish_service.dart';

/// Error classification for Google Street View publishing, mirroring the
/// original app's alert mapping (recovered from its decompiled bundle; see
/// docs/REVISION.md). Each case produces the same title + message the
/// original app showed.
enum StreetViewErrorKind {
  notA360Photo,
  locationRequired,
  photoTooLarge,
  alreadyUploaded,
  tokenExpired,
  permissionRequired,
  connection,
  uploadFailed,
}

/// A user-presentable Street View error (title + body), like the original
/// app's alert dialogs.
class StreetViewError {
  const StreetViewError(this.kind, this.title, this.message);

  final StreetViewErrorKind kind;
  final String title;
  final String message;
}

/// Classifies an error thrown while publishing. The matching rules follow
/// the original's `includes(...)` checks over the error text (which it built
/// from the API's `status` / `message` fields).
StreetViewError classifyStreetViewError(Object error) {
  final text = error.toString();

  if (error is StreetViewException) {
    if (_hasAny(text, ['location', 'latitude', 'longitude'])) {
      return const StreetViewError(
        StreetViewErrorKind.locationRequired,
        'Location Required',
        'Google Street View requires a valid GPS location. '
            'Please pick a location on the map and try again.',
      );
    }
    if (_hasAny(text, ['too large', 'size'])) {
      return const StreetViewError(
        StreetViewErrorKind.photoTooLarge,
        'Photo Too Large',
        'The photo file is too large. Please try with a smaller image.',
      );
    }
    if (_hasAny(text, ['already exists', 'ALREADY_EXISTS'])) {
      return const StreetViewError(
        StreetViewErrorKind.alreadyUploaded,
        'Already Uploaded',
        'This photo has already been uploaded to Google Street View.',
      );
    }
    if (_hasAny(text, [
      'network',
      'timeout',
      'ETIMEDOUT',
      'Failed host',
      'SocketException',
      'Connection'
    ])) {
      return const StreetViewError(
        StreetViewErrorKind.connection,
        'Connection Error',
        'Unable to connect to Google. Please check your internet '
            'connection and try again.',
      );
    }
    if (_hasAny(text, ['UNAUTHENTICATED', '401', 'token'])) {
      return const StreetViewError(
        StreetViewErrorKind.tokenExpired,
        'Google Account Token Expired',
        'Your Google account token has expired. Please sign out and '
            'sign in again to authorize access.',
      );
    }
    if (_hasAny(text, ['PERMISSION_DENIED', 'PERMISSION', '403'])) {
      return const StreetViewError(
        StreetViewErrorKind.permissionRequired,
        'Permission Required',
        'You need to grant Street View permission. Please sign in again.',
      );
    }
    if (_hasAny(text, ['INVALID_ARGUMENT'])) {
      return const StreetViewError(
        StreetViewErrorKind.notA360Photo,
        'Not a 360° Photo',
        "This image doesn't have the required 360° metadata. Only photos "
            'captured with the Photo 360 app or other 360° cameras can be '
            'uploaded to Google Street View.',
      );
    }
    return const StreetViewError(
      StreetViewErrorKind.uploadFailed,
      'Upload Failed',
      'Something went wrong while uploading to Google Street View. '
          'Please try again later.',
    );
  }

  if (_hasAny(text,
      ['SocketException', 'Failed host', 'timeout', 'ETIMEDOUT', 'network'])) {
    return const StreetViewError(
      StreetViewErrorKind.connection,
      'Connection Error',
      'Unable to connect to Google. Please check your internet '
          'connection and try again.',
    );
  }

  return const StreetViewError(
    StreetViewErrorKind.uploadFailed,
    'Upload Failed',
    'Something went wrong while uploading to Google Street View. '
        'Please try again later.',
  );
}

/// Client-side pre-flight used before uploading: Google rejects photos
/// without GPano XMP metadata with exactly the "Not a 360° Photo" error the
/// original maps — better to catch it before the upload.
StreetViewError? preflightCheck(Uint8List jpeg) {
  if (!hasGpanoXmp(jpeg) || gpanoProjectionType(jpeg) != 'equirectangular') {
    return const StreetViewError(
      StreetViewErrorKind.notA360Photo,
      'Not a 360° Photo',
      "This image doesn't have the required 360° metadata. Only photos "
          'captured with the Photo 360 app or other 360° cameras can be '
          'uploaded to Google Street View.',
    );
  }
  return null;
}

bool _hasAny(String text, List<String> needles) {
  final lower = text.toLowerCase();
  for (final n in needles) {
    if (lower.contains(n.toLowerCase())) return true;
  }
  return false;
}
