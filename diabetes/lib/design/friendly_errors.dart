import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Plain-language messages for errors shown to users. Raw errors go to the
/// debug log only, never on screen (NN/g error-message guidelines).
abstract final class FriendlyErrors {
  static const network =
      "Couldn't reach the server. Check your connection and try again.";
  static const generic = 'Something went wrong. Please try again.';

  /// Logs [error] under [context] and returns a message safe to show.
  static String describe(Object error, {String context = 'error'}) {
    debugPrint('$context: $error');
    if (error is TimeoutException) return network;
    if (error is FirebaseException) {
      return switch (error.code) {
        'unavailable' ||
        'deadline-exceeded' ||
        'network-request-failed' => network,
        'permission-denied' || 'unauthenticated' =>
          'Your session has expired. Sign in again to continue.',
        _ => generic,
      };
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Failed host lookup')) {
      return network;
    }
    return generic;
  }

  /// Maps Firebase Auth codes to plain sign-in messages.
  static String auth(FirebaseAuthException error) {
    debugPrint('auth: ${error.code} ${error.message}');
    return switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'invalid-email' =>
        "That email and password don't match. Try again or reset your password.",
      'email-already-in-use' =>
        'An account already exists for that email. Sign in instead.',
      'weak-password' => 'Choose a password with at least 6 characters.',
      'too-many-requests' => 'Too many attempts. Wait a minute and try again.',
      'network-request-failed' => network,
      'popup-closed-by-user' ||
      'cancelled-popup-request' ||
      'web-context-canceled' => 'Google sign-in was cancelled.',
      _ => "Couldn't sign you in. Please try again.",
    };
  }
}
