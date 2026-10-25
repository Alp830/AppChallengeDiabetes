import 'package:diabetes/fridge/selectable_fridge_grid.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Changing an item's food type moves its tile into another group's grid.
/// Each group is its own SliverGrid, so the tile must not carry a GlobalKey
/// across grids: re-parenting a keyed child mid-layout throws.
void main() {
  for (final direction in ['up', 'down']) {
    testWidgets('a tile moving $direction to another group rebuilds cleanly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Snack is laid out before Other (FoodType order).
      final from = direction == 'up' ? FoodType.other : FoodType.snack;
      final to = direction == 'up' ? FoodType.snack : FoodType.other;
      var movingType = from;
      late StateSetter rebuild;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return SelectableFridgeGrid(
                  items: [
                    const MapEntry(
                      0,
                      FoodItem(
                        name: 'Oats',
                        amount: '1',
                        foodType: FoodType.grain,
                      ),
                    ),
                    const MapEntry(
                      1,
                      FoodItem(
                        name: 'Cashews',
                        amount: '1',
                        foodType: FoodType.snack,
                      ),
                    ),
                    MapEntry(
                      2,
                      FoodItem(
                        name: 'Shredded',
                        amount: '1',
                        foodType: movingType,
                      ),
                    ),
                    const MapEntry(
                      3,
                      FoodItem(
                        name: 'Mystery',
                        amount: '1',
                        foodType: FoodType.other,
                      ),
                    ),
                  ],
                  onEdit: (_) {},
                  onRemoveSelected: (_) async {},
                  onBulkAction: (_, _) async {},
                  onDelete: (_) {},
                );
              },
            ),
          ),
        ),
      );

      // On web a mouse hover shows the delete button's tooltip, which puts
      // the tile's overlay child in the tree.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('fridgeTileDelete_Shredded'))),
      );
      await tester.pump(const Duration(seconds: 1));

      rebuild(() => movingType = to);
      await tester.pump();

      expect(tester.takeException(), isNull);
      final toHeader = find.byKey(Key('fridgeGroupHeader_${to.name}'));
      expect(
        tester.getTopLeft(find.text('Shredded')).dy,
        greaterThan(tester.getTopLeft(toHeader).dy),
      );
    });
  }
}
