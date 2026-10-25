import 'dart:math';

import 'package:diabetes/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays seeded random edit sequences (mouse-clicked tile deletes, Undo,
/// food type changes) that used to crash the grouped fridge grid with
/// "_RenderLayoutBuilder was mutated in RenderSliverGrid.performLayout".
/// Each seed below failed before the fix; the sequence is fixed by its seed.
void main() {
  for (final seed in const [3, 7, 9, 10, 23, 31]) {
    testWidgets('edit sequence $seed leaves every tile intact', (tester) async {
      tester.view.physicalSize = const Size(625, 1032);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rng = Random(seed);
      final now = DateTime.now();
      final types = [
        FoodType.grain,
        FoodType.snack,
        FoodType.other,
        FoodType.dairy,
      ];
      final names = ['Oats', 'Cashews', 'Shredded', 'Mystery', 'Milk', 'Rice'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FridgePage(
              initialItems: [
                for (var i = 0; i < names.length; i++)
                  StoredFoodItem(
                    id: 'id$i',
                    foodItem: FoodItem(
                      name: names[i],
                      amount: '1',
                      foodType: types[rng.nextInt(types.length)],
                      expiryDate: now.add(Duration(days: 5 + rng.nextInt(20))),
                    ),
                  ),
              ],
              onCommit: (_) async {},
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final log = <String>[];
      for (var step = 0; step < 12; step++) {
        final present = names
            .where((n) => find.text(n).evaluate().isNotEmpty)
            .toList();
        final op = rng.nextInt(3);
        if (op == 0 && present.isNotEmpty) {
          final n = present[rng.nextInt(present.length)];
          final x = find.byKey(Key('fridgeTileDelete_$n'));
          if (x.evaluate().isEmpty) continue;
          log.add('delete $n');
          await mouse.moveTo(tester.getCenter(x));
          await tester.pump(const Duration(milliseconds: 500));
          await mouse.down(tester.getCenter(x));
          await mouse.up();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        } else if (op == 1 && find.text('Undo').evaluate().isNotEmpty) {
          log.add('undo');
          await tester.tap(find.text('Undo').first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        } else if (present.isNotEmpty) {
          final n = present[rng.nextInt(present.length)];
          final t = types[rng.nextInt(types.length)];
          log.add('type $n -> ${t.label}');
          await mouse.moveTo(tester.getCenter(find.text(n)));
          await mouse.down(tester.getCenter(find.text(n)));
          await mouse.up();
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButtonFormField<FoodType>));
          await tester.pumpAndSettle();
          await tester.tap(find.text(t.label).last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save changes'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
        final e = tester.takeException();
        if (e != null || find.byType(ErrorWidget).evaluate().isNotEmpty) {
          fail('seed $seed broke after: ${log.join(', ')}\n$e');
        }
      }
      await tester.pumpAndSettle();
    });
  }
}
