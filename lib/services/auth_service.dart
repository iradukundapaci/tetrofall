import 'package:firebase_auth/firebase_auth.dart';

import 'analytics_service.dart' show logAnalyticsFailure;
import 'firebase_bootstrap.dart';

/// A silent anonymous Firebase account, so Firestore rules can require a
/// signed-in writer.
abstract final class AuthService {
  static Future<String?>? _signIn;

  /// The current uid, or null when signed out or Firebase is not up.
  static String? get uid {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (error) {
      logAnalyticsFailure('reading the auth user', error);
      return null;
    }
  }

  /// Signs in anonymously if nobody is signed in; safe to call concurrently.
  /// Null when it cannot (offline, no Firebase).
  static Future<String?> ensureAnonymous() {
    final existing = uid;
    if (existing != null) return Future.value(existing);
    return _signIn ??= _doSignIn().whenComplete(() => _signIn = null);
  }

  static Future<String?> _doSignIn() async {
    await FirebaseBootstrap.init();
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final credential = await FirebaseAuth.instance.signInAnonymously();
      return credential.user?.uid;
    } catch (error) {
      logAnalyticsFailure('anonymous sign-in', error);
      return null;
    }
  }
}
