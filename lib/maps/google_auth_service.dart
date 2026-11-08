import 'package:flutter/foundation.dart';
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
  bool _initialized = false;

  GoogleSignInAccount? get account => _account;
  bool get isSignedIn => _account != null;

  /// Scopes needed for Street View publishing.
  static const List<String> scopes = <String>[
    StreetViewPublishService.scope,
    'email',
  ];

  /// The v7 API exposes a singleton whose [GoogleSignIn.initialize] must be
  /// awaited exactly once before any other call.
  Future<GoogleSignIn> _signIn() async {
    final signIn = GoogleSignIn.instance;
    if (!_initialized) {
      await signIn.initialize();
      _initialized = true;
    }
    return signIn;
  }

  /// Interactive sign-in (completes without UI when a session is active).
  Future<GoogleSignInAccount?> signIn() async {
    try {
      final signIn = await _signIn();
      final account = await signIn.authenticate(scopeHint: scopes);
      _account = account;
      notifyListeners();
      return account;
    } on GoogleSignInException catch (e) {
      throw GoogleAuthException(_explain(e));
    }
  }

  /// Returns a fresh OAuth access token, or null when not signed in.
  Future<String?> accessToken() async {
    final account = _account;
    if (account == null) return null;
    try {
      // authorizationForScopes is silent but returns null when a prompt
      // would be needed; authorizeScopes then asks the user interactively.
      final authz =
          await account.authorizationClient.authorizationForScopes(scopes) ??
              await account.authorizationClient.authorizeScopes(scopes);
      _lastToken = authz.accessToken;
      return _lastToken;
    } on GoogleSignInException catch (e) {
      throw GoogleAuthException(_explain(e));
    }
  }

  Future<void> signOut() async {
    try {
      await (await _signIn()).signOut();
    } finally {
      _account = null;
      _lastToken = null;
      notifyListeners();
    }
  }

  String _explain(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Sign-in was canceled.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google Sign-In is misconfigured. Check the OAuth client '
            'setup — see docs/GOOGLE-MAPS-UPLOAD.md.';
      default:
        return 'Sign-in error (${e.code.name}): '
            '${e.description ?? 'unknown error'}';
    }
  }
}

class GoogleAuthException implements Exception {
  GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
