import 'package:diabetes/ai/ai_retry_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpStatus(WidgetTester tester, int attempt) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiRetryStatus(attempt: attempt, maxAttempts: 5)),
      ),
    );
  }

  testWidgets('the first attempt looks like an ordinary load', (tester) async {
    await pumpStatus(tester, 1);
    expect(find.byKey(const Key('aiRetryStatus')), findsNothing);
    expect(find.textContaining('Retrying'), findsNothing);
  });

  testWidgets('later attempts count themselves out loud', (tester) async {
    await pumpStatus(tester, 3);
    expect(find.byKey(const Key('aiRetryStatus')), findsOneWidget);
    expect(find.text('AI request failed. Retrying 3/5'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('screen readers hear a spelled-out live announcement', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpStatus(tester, 2);

    expect(
      tester.getSemantics(find.byKey(const Key('aiRetryStatus'))),
      matchesSemantics(
        label: 'AI request failed. Retrying, attempt 2 of 5',
        isLiveRegion: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the spinner stays small enough to sit inline', (tester) async {
    await pumpStatus(tester, 2);
    final size = tester.getSize(find.byType(CircularProgressIndicator));
    expect(size.width, lessThanOrEqualTo(20));
    expect(size.height, lessThanOrEqualTo(20));
  });
}
