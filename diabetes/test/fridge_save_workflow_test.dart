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

  Future<void> deleteViaEditSheet(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('fridgeEditDelete')));
    await tester.tap(find.byKey(const Key('fridgeEditDelete')));
    await tester.pumpAndSettle();
  }

  /// Opens [name]'s edit sheet, switches its food type to [typeLabel] and
  /// saves the sheet.
  Future<void> changeTypeViaEditSheet(
    WidgetTester tester,
    String name,
    String typeLabel,
  ) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<FoodType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(typeLabel).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
  }

  testWidgets('changing an item type moves it to that group straight away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(wrap(key, [stored('a', 'Rice')], committed));

    expect(find.byKey(const Key('fridgeGroupHeader_other')), findsOneWidget);

    await changeTypeViaEditSheet(tester, 'Rice', 'Grain');

    expect(find.byKey(const Key('fridgeGroupHeader_grain')), findsOneWidget);
    // Other is now empty, so its header goes away.
    expect(find.byKey(const Key('fridgeGroupHeader_other')), findsNothing);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('1 unsaved change'), findsOneWidget);
    expect(committed, isEmpty);

    // Discard puts it back under its saved type.
    await tester.tap(find.byKey(const Key('fridgeDiscardBar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fridgeGroupHeader_other')), findsOneWidget);
    expect(find.byKey(const Key('fridgeGroupHeader_grain')), findsNothing);
    expect(key.currentState!.isDirty, isFalse);
    expect(committed, isEmpty);
  });

  testWidgets('the edit sheet keeps Delete in its top area', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrap(GlobalKey<FridgePageState>(), [stored('a', 'Milk')], []),
    );

    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();

    final delete = find.byKey(const Key('fridgeEditDelete'));
    expect(delete, findsOneWidget);
    // Top right: above the first field, right of the sheet title.
    final nameField = find.widgetWithText(TextFormField, 'Food name');
    expect(
      tester.getTopLeft(delete).dy,
      lessThan(tester.getTopLeft(nameField).dy),
    );
    expect(
      tester.getCenter(delete).dx,
      greaterThan(tester.getCenter(find.text('Edit food')).dx),
    );
    // Still reads as a delete to a screen reader, and stays tappable.
    expect(find.bySemanticsLabel('Delete item'), findsOneWidget);
    expect(tester.getSize(delete).height, greaterThanOrEqualTo(48));
    handle.dispose();
  });

  testWidgets('adding a food shows no delete control', (tester) async {
    await tester.pumpWidget(wrap(GlobalKey<FridgePageState>(), const [], []));
    await tester.tap(find.byKey(const Key('fridgeEmptyAdd')));
    await tester.pumpAndSettle();
    expect(find.text('Add food'), findsWidgets);
    expect(find.byKey(const Key('fridgeEditDelete')), findsNothing);
  });

  testWidgets('deleting from the edit sheet is staged and can be undone', (
    tester,
  ) async {
    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(wrap(key, [stored('a', 'Milk')], committed));

    await deleteViaEditSheet(tester, 'Milk');

    expect(find.text('Milk'), findsNothing);
    expect(find.text('1 unsaved change'), findsOneWidget);
    expect(committed, isEmpty);
    expect(find.text('Removed Milk. Save to make it final.'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // The item is back and the fridge matches what is stored again.
    expect(find.text('Milk'), findsOneWidget);
    expect(key.currentState!.isDirty, isFalse);
    expect(find.byKey(const Key('fridgeSaveBar')), findsNothing);
    expect(committed, isEmpty);
  });

  testWidgets('undo puts the item back in its original position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(
      wrap(key, [
        stored('a', 'Milk'),
        stored('b', 'Rice'),
        stored('c', 'Kale'),
      ], committed),
    );

    await deleteViaEditSheet(tester, 'Rice');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // Editing Rice still addresses Rice's draft, so the indices lined up again.
    await changeTypeViaEditSheet(tester, 'Rice', 'Grain');
    await tester.tap(find.byKey(const Key('fridgeSaveBar')));
    await tester.pumpAndSettle();

    expect(committed.single.deletions, isEmpty);
    expect(committed.single.additions, isEmpty);
    expect(committed.single.updates.keys.single, 'b');
    expect(committed.single.updates['b']!.foodType, FoodType.grain);
  });

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
    await tester.tap(find.text('Save food'));
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

    await deleteViaEditSheet(tester, 'Milk');
    expect(find.text('Your fridge is empty'), findsOneWidget);
    expect(committed, isEmpty);
    expect(find.text('1 unsaved change'), findsOneWidget);

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

    await deleteViaEditSheet(tester, 'Milk');
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

    await deleteViaEditSheet(tester, 'Milk');

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

    await deleteViaEditSheet(tester, 'Milk');

    final leaving = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    expect(await leaving, isFalse);
    expect(key.currentState!.isDirty, isTrue);
  });

  testWidgets('the leave dialog counts the pending changes', (tester) async {
    final key = GlobalKey<FridgePageState>();
    await tester.pumpWidget(
      wrap(key, [stored('a', 'Milk'), stored('b', 'Rice')], []),
    );

    await deleteViaEditSheet(tester, 'Milk');
    final one = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You have 1 unsaved change to your fridge. Save it before leaving?',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(await one, isFalse);

    await changeTypeViaEditSheet(tester, 'Rice', 'Grain');
    final two = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'You have 2 unsaved changes to your fridge. Save them before leaving?',
      ),
      findsOneWidget,
    );
    // The three choices keep their keys.
    expect(find.text('Keep editing'), findsOneWidget);
    expect(find.byKey(const Key('fridgeDiscardChanges')), findsOneWidget);
    expect(find.byKey(const Key('fridgeSaveChanges')), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(await two, isFalse);
  });

  testWidgets('an add, an edit and a delete across groups commit as one set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(
      wrap(key, [stored('a', 'Milk'), stored('b', 'Rice')], committed),
    );

    // Add Eggs (new group), move Rice to Grain, delete Milk.
    await tester.tap(find.byTooltip('Add food'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Food name'),
      'Eggs',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '12');
    await tester.tap(find.text('Save food'));
    await tester.pumpAndSettle();

    await changeTypeViaEditSheet(tester, 'Rice', 'Grain');
    await deleteViaEditSheet(tester, 'Milk');

    final leaving = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fridgeSaveChanges')));
    await tester.pumpAndSettle();

    expect(await leaving, isTrue);
    expect(committed, hasLength(1));
    expect(committed.single.additions.single.name, 'Eggs');
    expect(committed.single.updates.keys.single, 'b');
    expect(committed.single.deletions, ['a']);
    expect(key.currentState!.isDirty, isFalse);
  });

  testWidgets('discard restores every group', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(
      wrap(key, [stored('a', 'Milk'), stored('b', 'Rice')], committed),
    );

    await changeTypeViaEditSheet(tester, 'Rice', 'Grain');
    await deleteViaEditSheet(tester, 'Milk');

    final leaving = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fridgeDiscardChanges')));
    await tester.pumpAndSettle();

    expect(await leaving, isTrue);
    expect(committed, isEmpty);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.byKey(const Key('fridgeGroupHeader_other')), findsOneWidget);
    expect(find.byKey(const Key('fridgeGroupHeader_grain')), findsNothing);
    expect(key.currentState!.isDirty, isFalse);
  });

  testWidgets('a failed save keeps the drafts and stays on the fridge', (
    tester,
  ) async {
    final key = GlobalKey<FridgePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FridgePage(
            key: key,
            initialItems: [stored('a', 'Milk')],
            onCommit: (_) async => throw Exception('offline'),
          ),
        ),
      ),
    );

    await deleteViaEditSheet(tester, 'Milk');

    final leaving = key.currentState!.confirmLeave();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fridgeSaveChanges')));
    await tester.pumpAndSettle();

    expect(await leaving, isFalse);
    expect(key.currentState!.isDirty, isTrue);
    expect(find.byKey(const Key('fridgeSaveBar')), findsOneWidget);
  });

  testWidgets('bulk delete across groups stages until save', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey<FridgePageState>();
    final committed = <FridgeChangeSet>[];
    await tester.pumpWidget(
      wrap(key, [stored('a', 'Milk'), stored('b', 'Rice')], committed),
    );
    await changeTypeViaEditSheet(tester, 'Rice', 'Grain');

    await tester.longPress(find.text('Milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rice'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deleteSelectedFridgeItems')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete 2 items'));
    await tester.pumpAndSettle();

    expect(find.text('Your fridge is empty'), findsOneWidget);
    expect(committed, isEmpty);

    await tester.tap(find.byKey(const Key('fridgeSaveBar')));
    await tester.pumpAndSettle();
    expect(committed.single.deletions, unorderedEquals(['a', 'b']));
    expect(committed.single.updates, isEmpty);
  });

  testWidgets('empty fridge explains itself and offers scan and add', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(GlobalKey<FridgePageState>(), const [], []));
    expect(find.text('Your fridge is empty'), findsOneWidget);
    expect(find.byKey(const Key('fridgeEmptyScan')), findsOneWidget);
    expect(find.byKey(const Key('fridgeEmptyAdd')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('one extended Scan fridge FAB plus a small add FAB', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(GlobalKey<FridgePageState>(), [stored('a', 'Milk')], []),
    );
    expect(
      find.widgetWithText(FloatingActionButton, 'Scan fridge'),
      findsOneWidget,
    );
    expect(find.byTooltip('Add food'), findsOneWidget);
  });
}
