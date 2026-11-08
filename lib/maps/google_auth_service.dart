import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import 'streetview_publish_service.dart';

/// Wraps Google Sign-In with the Street View Publish scope.
///
/// NOTE: this requires an OAuth client configured in Google Cloud Console —
/// see docs/GOOGLE-MAPS-UPLOAD.md for the one-time setup. Sign-in failures
/// are surfaced as [GoogleAuthException] with actionable messages.
class GoogleAuthService extends ChangeNotifier {
  GoogleSignInAccount? _account;
  String? _lastToken;

  GoogleSignInAccount? get account => _account;
  bool get isSignedIn => _account != null;

  GoogleSignIn get _signIn => GoogleSignIn(
        scopes: [StreetViewPublishService.scope, 'email'],
      );

  Future<GoogleSignInAccount?> signIn() async {
    try {
      var account = await _signIn.signInSilently();
      account ??= await _signIn.signIn();
      _account = account;
      notifyListeners();
      return account;
    } on PlatformException catch (e) {
      throw GoogleAuthException(_explain(e));
    }
  }

  /// Returns a fresh OAuth access token, or null when not signed in.
  Future<String?> accessToken() async {
    final account = _account ?? await _signIn.signInSilently();
    if (account == null) return null;
    _account = account;
    final auth = await account.authentication;
    _lastToken = auth.accessToken;
    return _lastToken;
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    _account = null;
    _lastToken = null;
    notifyListeners();
  }

  String _explain(PlatformException e) {
    final code = e.code;
    switch (code) {
      case 'sign_in_failed':
        return 'Google Sign-In failed. Check the OAuth client configuration — '
            'see docs/GOOGLE-MAPS-UPLOAD.md.';
      case 'network_error':
        return 'Network error during sign-in. Check your connection.';
      default:
        return 'Sign-in error ($code): ${e.message}';
    }
  }
}

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
