import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const review = ScanReview(
    confidence: ScanConfidence.guess,
    alternatives: ['Salsa', 'Hot sauce'],
  );

  StoredFoodItem stored(String id, String name, {ScanReview? scanReview}) =>
      StoredFoodItem(
        id: id,
        foodItem: FoodItem(
          name: name,
          amount: '1',
          foodType: FoodType.other,
          scanReview: scanReview,
        ),
      );

  Future<GlobalKey<FridgePageState>> pumpFridge(
    WidgetTester tester,
    List<StoredFoodItem> items,
    List<FridgeChangeSet> committed,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<FridgePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FridgePage(
            key: key,
            initialItems: items,
            onCommit: (changes) async => committed.add(changes),
          ),
        ),
      ),
    );
    return key;
  }

  group('tile', () {
    testWidgets('shows the Maybe badge with its semantic label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpFridge(tester, [
        stored('a', 'Ketchup', scanReview: review),
        stored('b', 'Milk'),
      ], []);

      expect(find.text('Maybe'), findsOneWidget);
      expect(
        // The tile merges its children's labels, so match within it.
        find.bySemanticsLabel(RegExp('Maybe Ketchup, check this item')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the tile ✕ deletes in one press', (tester) async {
      final committed = <FridgeChangeSet>[];
      final key = await pumpFridge(tester, [
        stored('a', 'Ketchup', scanReview: review),
      ], committed);

      await tester.tap(find.byKey(const Key('fridgeTileDelete_Ketchup')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fridgeTileDelete_Ketchup')), findsNothing);
      expect(key.currentState!.isDirty, isTrue);
    });
  });

  group('edit sheet', () {
    testWidgets('an alternative chip renames the item and clears the badge', (
      tester,
    ) async {
      await pumpFridge(tester, [stored('a', 'Ketchup', scanReview: review)], []);

      await tester.tap(find.text('Ketchup'));
      await tester.pumpAndSettle();
      expect(find.text('Or:'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scanAlternative_Salsa')));
      await tester.pumpAndSettle();

      expect(find.text('Salsa'), findsOneWidget);
      expect(find.text('Ketchup'), findsNothing);
      expect(find.text('Maybe'), findsNothing);
    });

    testWidgets('Looks right clears the badge and keeps the name', (
      tester,
    ) async {
      await pumpFridge(tester, [stored('a', 'Ketchup', scanReview: review)], []);

      await tester.tap(find.text('Ketchup'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scanLooksRight')));
      await tester.pumpAndSettle();

      expect(find.text('Ketchup'), findsOneWidget);
      expect(find.text('Maybe'), findsNothing);
    });

    testWidgets('editing the item clears the badge', (tester) async {
      await pumpFridge(tester, [stored('a', 'Ketchup', scanReview: review)], []);

      await tester.tap(find.text('Ketchup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Tomato sauce');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Tomato sauce'), findsOneWidget);
      expect(find.text('Maybe'), findsNothing);
    });

    testWidgets('a sure item has no review controls', (tester) async {
      await pumpFridge(tester, [stored('a', 'Milk')], []);

      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scanLooksRight')), findsNothing);
      expect(find.text('Or:'), findsNothing);
    });

    testWidgets('confirming a Maybe item is a saveable change', (tester) async {
      final committed = <FridgeChangeSet>[];
      final key = await pumpFridge(tester, [
        stored('a', 'Ketchup', scanReview: review),
      ], committed);

      await tester.tap(find.text('Ketchup'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scanLooksRight')));
      await tester.pumpAndSettle();

      expect(key.currentState!.isDirty, isTrue);
      await tester.tap(find.byKey(const Key('fridgeSaveBar')));
      await tester.pumpAndSettle();
      expect(committed.single.updates['a']!.scanReview, isNull);
    });
  });

  group('data', () {
    test('scanReview survives toFirestore → fromFirestore', () {
      const item = FoodItem(
        name: 'Ketchup',
        amount: '1',
        foodType: FoodType.other,
        scanReview: review,
      );
      final map = item.toFirestore();
      expect(map['scanReview'], {
        'confidence': 'guess',
        'alternatives': ['Salsa', 'Hot sauce'],
      });

      expect(FoodItem.fromFirestore(map).scanReview, review);
    });

    test('a cleared review is omitted from the document', () {
      const item = FoodItem(
        name: 'Ketchup',
        amount: '1',
        foodType: FoodType.other,
        scanReview: review,
      );
      final cleared = item.copyWith(clearScanReview: true);
      expect(cleared.scanReview, isNull);
      expect(cleared.toFirestore().containsKey('scanReview'), isFalse);
      expect(item.copyWith(name: 'Salsa').scanReview, review);
    });

    test('old documents without a review load as before', () {
      final item = FoodItem.fromFirestore({
        'name': 'Milk',
        'amount': '1',
        'foodType': 'Dairy',
        'expiryDate': Timestamp.fromDate(DateTime(2026, 7, 22)),
      });
      expect(item.scanReview, isNull);
      expect(item.name, 'Milk');
    });

    test('malformed review data is ignored or tolerated', () {
      Map<String, dynamic> doc(Object? scanReview) => {
        'name': 'Milk',
        'amount': '1',
        'foodType': 'Dairy',
        'scanReview': scanReview,
      };
      expect(FoodItem.fromFirestore(doc('nope')).scanReview, isNull);
      expect(FoodItem.fromFirestore(doc(null)).scanReview, isNull);
      final lenient = FoodItem.fromFirestore(
        doc({
          'confidence': 7,
          'alternatives': ['Oat milk', 3, ''],
        }),
      ).scanReview;
      expect(lenient!.confidence, ScanConfidence.likely);
      expect(lenient.alternatives, ['Oat milk']);
    });

    test('toFoodItem sets a review for likely and guess, not sure', () {
      ScannedItem scanned(ScanConfidence confidence) => ScannedItem(
        name: 'Ketchup',
        foodType: FoodType.other,
        confidence: confidence,
        alternatives: const ['Salsa'],
      );
      expect(scanned(ScanConfidence.sure).toFoodItem().scanReview, isNull);
      expect(
        scanned(ScanConfidence.likely).toFoodItem().scanReview,
        const ScanReview(
          confidence: ScanConfidence.likely,
          alternatives: ['Salsa'],
        ),
      );
      expect(
        scanned(ScanConfidence.guess).toFoodItem().scanReview?.confidence,
        ScanConfidence.guess,
      );
    });
  });

  group('scan snackbar', () {
    FoodItem food(ScanReview? scanReview) => FoodItem(
      name: 'x',
      amount: '1',
      foodType: FoodType.other,
      scanReview: scanReview,
    );

    test('counts the items to check', () {
      final foods = [
        for (var i = 0; i < 12; i++) food(null),
        for (var i = 0; i < 6; i++) food(review),
      ];
      expect(
        scanAddedMessage(foods),
        'Added 18 items, 6 to check \u2014 remember to save.',
      );
    });

    test('keeps the current text when none need checking', () {
      expect(
        scanAddedMessage([food(null), food(null)]),
        'Added 2 items \u2014 remember to save.',
      );
    });

    test('keeps the singular form for one item', () {
      expect(
        scanAddedMessage([food(null)]),
        'Added 1 item \u2014 remember to save.',
      );
      expect(
        scanAddedMessage([food(review)]),
        'Added 1 item, 1 to check \u2014 remember to save.',
      );
    });
  });

  test('the meal agent prompt marks Maybe items as unconfirmed', () {
    final prompt = GeminiMealService.buildPromptForTesting(
      AgentRequest(
        useFridgeItems: true,
        hasBudget: false,
        budget: null,
        hasTimeShortage: false,
        timeAvailable: null,
        foodPreferences: 'A quick lunch',
        mealType: MealType.lunch,
        cookingExperience: CookingExperience.beginner,
        recommendationCount: 1,
        fridgeItems: [
          const FoodItem(
            name: 'Ketchup',
            amount: '1 bottle',
            foodType: FoodType.other,
            scanReview: review,
          ),
          const FoodItem(
            name: 'Milk',
            amount: '1 carton',
            foodType: FoodType.dairy,
          ),
        ],
        feedbackHistory: const [],
        useMealBalance: false,
      ),
    );

    final lines = prompt.split('\n');
    expect(
      lines.singleWhere((line) => line.startsWith('- Ketchup')),
      endsWith('(unconfirmed)'),
    );
    expect(
      lines.singleWhere((line) => line.startsWith('- Milk')),
      isNot(contains('unconfirmed')),
    );
  });
}
