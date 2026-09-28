import 'dart:async';

import 'package:diabetes/ai/ai_retry.dart';
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

  group('FriendlyErrors.ai', () {
    test('a used-up set of attempts blames the connection, not the user', () {
      const busy = AiRequestException(
        'Gemini request failed: 503',
        statusCode: 503,
        retryable: true,
      );
      expect(
        FriendlyErrors.ai(busy, action: 'a meal idea'),
        "Couldn't get a meal idea after a few tries. "
        'Check your connection and try again.',
      );
      expect(
        FriendlyErrors.ai(TimeoutException('slow'), action: 'an answer'),
        contains('an answer after a few tries'),
      );
    });

    test('a missing key is a setup problem, not a retry problem', () {
      expect(
        FriendlyErrors.ai(
          const AiRequestException('Missing GEMINI_API_KEY', retryable: false),
          action: 'a meal idea',
        ),
        "Meal ideas aren't set up on this device yet.",
      );
    });

    test('a 4xx asks the user to change the request', () {
      expect(
        FriendlyErrors.ai(
          AiRequestException.fromStatus(400, 'bad'),
          action: 'a meal idea',
        ),
        "That request didn't work. Try changing it and try again.",
      );
      expect(
        FriendlyErrors.ai(
          const AiRequestException(
            'Gemini blocked the request: SAFETY',
            retryable: false,
          ),
          action: 'an answer',
        ),
        "That request didn't work. Try changing it and try again.",
      );
    });

    test('never leaks the raw error text', () {
      for (final error in <Object>[
        AiRequestException.fromStatus(500, 'stack trace inside'),
        const AiRequestException('Missing GEMINI_API_KEY', retryable: false),
        AiRequestException.fromStatus(404, 'no such model'),
        const FormatException('candidates[0] is null'),
      ]) {
        final message = FriendlyErrors.ai(error, action: 'a meal idea');
        expect(message, isNot(contains('Gemini')));
        expect(message, isNot(contains('API_KEY')));
        expect(message, isNot(contains('Exception')));
      }
    });
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
