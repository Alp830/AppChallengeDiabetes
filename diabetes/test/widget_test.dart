// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diabetes/main.dart';

void main() {
  testWidgets('Page circles navigate between blank pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.bySemanticsLabel('Home'), findsWidgets);

    await tester.tap(find.bySemanticsLabel('Fridge'));
    await tester.pumpAndSettle();

    expect(find.text('Fridge'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Agent'));
    await tester.pumpAndSettle();

    expect(find.text('Agent'), findsOneWidget);
  });

  testWidgets('Fridge page can add, edit, and remove food items', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.bySemanticsLabel('Fridge'));
    await tester.pumpAndSettle();

    expect(find.text('No food added yet.'), findsOneWidget);

    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food name'),
      'Eggs',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '12');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Measurement'),
      'pieces',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description (optional)'),
      'Breakfast food',
    );

    await tester.tap(find.text('Save Food'));
    await tester.pumpAndSettle();

    expect(find.text('Eggs'), findsOneWidget);
    expect(find.text('12 pieces'), findsOneWidget);
    expect(find.text('Breakfast food'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit food'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food name'),
      'Milk',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '1');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Measurement'),
      'carton',
    );

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Eggs'), findsNothing);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('1 carton'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove food'));
    await tester.pumpAndSettle();

    expect(find.text('Milk'), findsNothing);
    expect(find.text('No food added yet.'), findsOneWidget);
  });

  testWidgets('Agent page asks Gemini instead of showing hardcoded meals', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.bySemanticsLabel('Agent'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'What kind of foods do you like?'),
      'bananas and drinks',
    );

    await tester.tap(find.text('Snack'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Intermediate'));
    await tester.pumpAndSettle();

    final recommendButton = find.byKey(const Key('recommendMealButton'));
    await tester.ensureVisible(recommendButton);
    tester.widget<FilledButton>(recommendButton).onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Healthy Chicken Rice Bowl'), findsNothing);
    expect(find.text('Veggie Egg Fried Rice'), findsNothing);
    expect(find.text('Turkey Bean Chili Bowl'), findsNothing);
  });
}
