import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StoredFoodItem stored(String id, String name) => StoredFoodItem(
    id: id,
    foodItem: FoodItem(name: name, amount: '1', foodType: FoodType.other),
  );

  Widget wrap(
    GlobalKey<FridgePageState> key,
    List<StoredFoodItem> initial,
    List<FridgeChangeSet> committed,
  ) {
    return MaterialApp(
      home: Scaffold(
        body: FridgePage(
          key: key,
          initialItems: initial,
          onCommit: (changes) async => committed.add(changes),
        ),
      ),
    );
  }

  testWidgets('edits stage locally and only commit when saved', (tester) async {
    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(wrap(key, [stored('a', 'Milk')], committed));

    // Add a new item through the add sheet.
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food name'),
      'Eggs',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '12');
    await tester.tap(find.text('Save Food'));
    await tester.pumpAndSettle();

    // Staged, but nothing has been written yet.
    expect(find.text('Eggs'), findsOneWidget);
    expect(committed, isEmpty);
    expect(key.currentState!.isDirty, isTrue);
    expect(find.byKey(const Key('fridgeSaveBar')), findsOneWidget);

    // Save commits the whole change set at once.
    await tester.tap(find.byKey(const Key('fridgeSaveBar')));
    await tester.pumpAndSettle();

    expect(committed, hasLength(1));
    expect(committed.single.additions, hasLength(1));
    expect(committed.single.additions.single.name, 'Eggs');
    expect(committed.single.deletions, isEmpty);
    expect(key.currentState!.isDirty, isFalse);
    expect(find.byKey(const Key('fridgeSaveBar')), findsNothing);
  });

  testWidgets('deleting an existing item stages a deletion until saved', (
    tester,
  ) async {
    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(wrap(key, [stored('a', 'Milk')], committed));

    await tester.tap(find.byTooltip('Delete item'));
    await tester.pumpAndSettle();
    expect(find.text('No food added yet.'), findsOneWidget);
    expect(committed, isEmpty);

    await tester.tap(find.byKey(const Key('fridgeSaveBar')));
    await tester.pumpAndSettle();
    expect(committed.single.deletions, ['a']);
  });

  testWidgets('discarding reverts staged edits without committing', (
    tester,
  ) async {
    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(wrap(key, [stored('a', 'Milk')], committed));

    await tester.tap(find.byTooltip('Delete item'));
    await tester.pumpAndSettle();
    expect(key.currentState!.isDirty, isTrue);

    await tester.tap(find.byKey(const Key('fridgeDiscardBar')));
    await tester.pumpAndSettle();

    expect(committed, isEmpty);
    expect(find.text('Milk'), findsOneWidget);
    expect(key.currentState!.isDirty, isFalse);
  });

  testWidgets('confirmLeave prompts and discards on the leaving guard', (
    tester,
  ) async {
    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(wrap(key, [stored('a', 'Milk')], committed));

    await tester.tap(find.byTooltip('Delete item'));
    await tester.pumpAndSettle();

    final leaving = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    expect(find.text('Save fridge changes?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fridgeDiscardChanges')));
    await tester.pumpAndSettle();

    expect(await leaving, isTrue);
    expect(committed, isEmpty);
    expect(find.text('Milk'), findsOneWidget);
  });

  testWidgets('confirmLeave can cancel and stay on the tab', (tester) async {
    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(wrap(key, [stored('a', 'Milk')], committed));

    await tester.tap(find.byTooltip('Delete item'));
    await tester.pumpAndSettle();

    final leaving = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(await leaving, isFalse);
    expect(key.currentState!.isDirty, isTrue);
  });
}
