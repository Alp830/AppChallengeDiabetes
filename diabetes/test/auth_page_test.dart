import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Portrait phone, not the default 800×600 landscape test window.
  Future<void> pump(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(const MaterialApp(home: AuthPage()));
  }

  testWidgets('says what the app is and offers recovery', (tester) async {
    await pump(tester);
    expect(find.text('Replate'), findsOneWidget);
    expect(
      find.text("Turn what's in your fridge into meal ideas."),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('password can be shown and hidden', (tester) async {
    await pump(tester);
    EditableText field() => tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Password'),
        matching: find.byType(EditableText),
      ),
    );
    expect(field().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(field().obscureText, isFalse);
  });

  testWidgets('length rule applies to sign-up only', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'a@b.co',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your password'), findsOneWidget);
    expect(find.text('Use at least 6 characters'), findsNothing);

    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      '123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.text('Use at least 6 characters'), findsOneWidget);
  });

  testWidgets('forgot password without an email asks for it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.textContaining('Enter your email above'), findsOneWidget);
  });
}
