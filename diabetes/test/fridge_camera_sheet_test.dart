import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('camera sheet opens on a two-option chooser', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FridgeCameraSheet())),
    );
    await tester.pump();

    // The chooser offers both a live-capture and an upload path. It does not
    // touch the camera plugin until "Take a picture" is tapped, so simply
    // rendering it is safe in a widget test.
    expect(
      find.widgetWithText(FilledButton, 'Take a picture'),
      findsOneWidget,
    );
    expect(find.text('Upload a screenshot/picture'), findsOneWidget);
  });
}
