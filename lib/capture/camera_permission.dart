import 'package:permission_handler/permission_handler.dart';

/// Outcome of ensuring the camera runtime permission.
enum CameraPermissionOutcome {
  /// Permission granted — the camera can be opened.
  granted,

  /// The user denied the request (dialog dismissed or "Deny" tapped).
  /// Asking again is still possible.
  denied,

  /// The user denied twice or tapped "Don't ask again" — the OS will no
  /// longer show the dialog. The only way forward is the app settings page.
  permanentlyDenied,
}

/// Requests the camera runtime permission before the camera is opened.
///
/// The `CAMERA` entry in `AndroidManifest.xml` only *declares* the
/// permission; on Android 6.0+ the app must also request it at runtime,
/// and the `camera` plugin never triggers the OS dialog itself. Without a
/// grant, `CameraController.initialize()` can appear to succeed while the
/// preview surface never receives frames — the symptom is a black camera
/// screen with no error.
///
/// The check and request functions are injectable so the decision logic
/// can be unit-tested without a platform channel.
class CameraPermissionGate {
  CameraPermissionGate({
    Future<PermissionStatus> Function()? checkStatus,
    Future<PermissionStatus> Function()? request,
  })  : _checkStatus = checkStatus ?? _defaultCheck,
        _request = request ?? _defaultRequest;

  static Future<PermissionStatus> _defaultCheck() => Permission.camera.status;

  static Future<PermissionStatus> _defaultRequest() =>
      Permission.camera.request();

  final Future<PermissionStatus> Function() _checkStatus;
  final Future<PermissionStatus> Function() _request;

  /// Ensures the camera permission is granted, requesting it if needed.
  Future<CameraPermissionOutcome> ensure() async {
    var status = await _checkStatus();
    if (status.isGranted || status.isLimited) {
      return CameraPermissionOutcome.granted;
    }
    if (status.isPermanentlyDenied) {
      return CameraPermissionOutcome.permanentlyDenied;
    }
    status = await _request();
    if (status.isGranted || status.isLimited) {
      return CameraPermissionOutcome.granted;
    }
    return status.isPermanentlyDenied
        ? CameraPermissionOutcome.permanentlyDenied
        : CameraPermissionOutcome.denied;
  }
}
