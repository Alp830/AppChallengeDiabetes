import 'package:diabetes/design/friendly_errors.dart';
import 'package:diabetes/design/load_error.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firestore outages map to the network message, never raw text', () {
    final message = FriendlyErrors.describe(
      FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'raw internals',
      ),
    );
    expect(message, FriendlyErrors.network);
  });

  test('unknown errors get the generic message', () {
    expect(FriendlyErrors.describe(StateError('boom')), FriendlyErrors.generic);
  });

  test('auth codes map to plain sentences', () {
    expect(
      FriendlyErrors.auth(FirebaseAuthException(code: 'email-already-in-use')),
      contains('already exists'),
    );
    expect(
      FriendlyErrors.auth(FirebaseAuthException(code: 'invalid-credential')),
      isNot(contains('invalid-credential')),
    );
  });

  testWidgets('LoadErrorView shows the message and retries', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoadErrorView(message: 'Nope.', onRetry: () => retried++),
        ),
      ),
    );
    expect(find.text('Nope.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });
}
