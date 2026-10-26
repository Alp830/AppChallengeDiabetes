import 'package:diabetes/fridge/scan/scan_merge.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:diabetes/main.dart';
import 'package:flutter_test/flutter_test.dart';

ScannedItem item(
  String name,
  List<int>? box, {
  ScanConfidence confidence = ScanConfidence.likely,
  List<String> alternatives = const [],
  String location = 'shelf 1',
}) => ScannedItem(
  name: name,
  foodType: FoodType.other,
  confidence: confidence,
  alternatives: alternatives,
  location: location,
  box2d: box,
);

void main() {
  group('iou', () {
    test('identical boxes are 1', () {
      expect(iou([0, 0, 100, 100], [0, 0, 100, 100]), 1);
    });

    test('disjoint and touching boxes are 0', () {
      expect(iou([0, 0, 100, 100], [200, 200, 300, 300]), 0);
      expect(iou([0, 0, 100, 100], [0, 100, 100, 200]), 0);
    });

    test('half overlap is 1/3', () {
      expect(iou([0, 0, 100, 100], [0, 50, 100, 150]), closeTo(1 / 3, 1e-9));
    });

    test('degenerate boxes are 0', () {
      expect(iou([10, 10, 10, 10], [10, 10, 10, 10]), 0);
    });
  });

  group('mergeScans', () {
    test('the same object seen in two overlapping tiles counts once', () {
      final base = [item('Milk', [100, 100, 300, 300])];
      final tileA = [item('milk', [110, 105, 305, 300])];
      final tileB = [item('Milks', [100, 100, 300, 310])];
      final merged = mergeScans(base, [tileA, tileB]);
      expect(merged, hasLength(1));
    });

    test('an item only a tile saw is appended after the base', () {
      final merged = mergeScans(
        [item('Milk', [0, 0, 100, 100])],
        [
          [item('Butter', [500, 500, 600, 600])],
        ],
      );
      expect(merged.map((i) => i.name), ['Milk', 'Butter']);
    });

    test('same name far apart stays two (two egg cartons)', () {
      final merged = mergeScans(
        [item('Eggs', [100, 100, 200, 200])],
        [
          [item('Eggs', [100, 600, 200, 700])],
        ],
      );
      expect(merged, hasLength(2));
    });

    test('items from one list never merge with each other', () {
      final merged = mergeScans(
        const [],
        [
          [
            item('Eggs', [100, 100, 200, 200]),
            item('Eggs', [100, 110, 200, 210]),
          ],
        ],
      );
      expect(merged, hasLength(2));
    });

    // Identical boxes from two tiles are one object even when named
    // differently (see the cross-tile group); partly overlapping ones aren't.
    test('partly overlapping boxes with different names stay two', () {
      final merged = mergeScans(
        [item('Milk', [100, 100, 300, 300])],
        [
          [item('Orange juice', [200, 200, 400, 400])],
        ],
      );
      expect(merged, hasLength(2));
    });

    test('token subset matches either way', () {
      final merged = mergeScans(
        [item('Oat milk', [100, 100, 300, 300])],
        [
          [item('milk', [100, 100, 300, 300])],
        ],
      );
      expect(merged, hasLength(1));
    });

    test('an alternative name matches', () {
      final merged = mergeScans(
        [
          item(
            'Yogurt',
            [100, 100, 300, 300],
            alternatives: const ['Sour cream'],
          ),
        ],
        [
          [item('Sour cream', [100, 100, 300, 300])],
        ],
      );
      expect(merged, hasLength(1));
    });

    test('higher confidence wins and alternatives are unioned, max 2', () {
      final merged = mergeScans(
        [
          item(
            'Yogurt',
            [100, 100, 300, 300],
            confidence: ScanConfidence.guess,
            alternatives: const ['Sour cream', 'Cream cheese'],
          ),
        ],
        [
          [
            item(
              'Sour cream',
              [100, 100, 300, 300],
              confidence: ScanConfidence.sure,
              alternatives: const ['Yogurt', 'Mayonnaise'],
            ),
          ],
        ],
      );
      expect(merged, hasLength(1));
      expect(merged.single.name, 'Sour cream');
      expect(merged.single.confidence, ScanConfidence.sure);
      // Kept item's own list first, the kept name never repeated.
      expect(merged.single.alternatives, ['Yogurt', 'Mayonnaise']);
    });

    test('a tie keeps the earlier item', () {
      final merged = mergeScans(
        [
          item(
            'Milk',
            [100, 100, 300, 300],
            alternatives: const ['Cream'],
          ),
        ],
        [
          [
            item(
              'milk',
              [100, 100, 300, 300],
              alternatives: const ['Kefir'],
            ),
          ],
        ],
      );
      expect(merged.single.name, 'Milk');
      expect(merged.single.alternatives, ['Cream', 'Kefir']);
    });

    test('boxless items merge only on equal name and location', () {
      final merged = mergeScans(
        [
          item('Milk', null, location: 'Shelf 1'),
          item('Butter', null, location: 'Shelf 1'),
        ],
        [
          [
            item('milk', null, location: 'shelf 1'),
            item('Butter', null, location: 'Shelf 2'),
          ],
        ],
      );
      expect(merged.map((i) => i.name), ['Milk', 'Butter', 'Butter']);
    });

    test('a boxless item does not merge into a boxed one by overlap', () {
      final merged = mergeScans(
        [item('Milk', [100, 100, 300, 300], location: 'Shelf 1')],
        [
          [item('Milk', null, location: 'Shelf 2')],
        ],
      );
      expect(merged, hasLength(2));
    });

    test('a part-box inside a whole-box from another tile merges', () {
      // IoU is 0.12, but the part lies fully inside the whole.
      final merged = mergeScans(
        [item('Mushrooms', [100, 100, 400, 400])],
        [
          [item('mushrooms', [100, 300, 200, 400])],
        ],
      );
      expect(merged, hasLength(1));
    });

    test('touching boxes from different tiles with the same name merge', () {
      final merged = mergeScans(
        [item('Cucumber', [100, 100, 300, 300])],
        [
          // 10 apart on the 0-1000 grid, within 2%.
          [item('Cucumber', [100, 310, 300, 500])],
          // 100 apart: a separate object.
          [item('Cucumber', [100, 600, 300, 800])],
        ],
      );
      expect(merged, hasLength(2));
      expect(merged[0].box2d, [100, 100, 300, 300]);
      expect(merged[1].box2d, [100, 600, 300, 800]);
    });

    test('boxes just over 2% apart stay two', () {
      final merged = mergeScans(
        [item('Cucumber', [100, 100, 300, 300])],
        [
          [item('Cucumber', [100, 321, 300, 500])],
        ],
      );
      expect(merged, hasLength(2));
    });

    test('touching boxes in one list stay two (two egg cartons)', () {
      final merged = mergeScans(
        const [],
        [
          [
            item('Eggs', [100, 100, 300, 300]),
            item('Eggs', [100, 300, 300, 500]),
          ],
        ],
      );
      expect(merged, hasLength(2));
    });

    test('touching boxes with different names stay two', () {
      final merged = mergeScans(
        [item('Milk', [100, 100, 300, 300])],
        [
          [item('Butter', [100, 300, 300, 500])],
        ],
      );
      expect(merged, hasLength(2));
    });

    test('boxless same-name items across lists merge', () {
      final merged = mergeScans(
        [item('Milk', null, location: 'Shelf 1')],
        [
          [item('milks', null, location: '')],
        ],
      );
      expect(merged, hasLength(1));
    });

    test('is deterministic', () {
      List<String> run() => mergeScans(
        [item('A', [0, 0, 100, 100]), item('B', [200, 200, 300, 300])],
        [
          [item('C', [400, 400, 500, 500]), item('A', [0, 0, 100, 100])],
          [item('D', [600, 600, 700, 700])],
        ],
      ).map((i) => i.name).toList();
      expect(run(), ['A', 'B', 'C', 'D']);
      expect(run(), run());
    });
  });

  group('applyZoom', () {
    test('replaces only on strictly higher confidence', () {
      final base = [
        item(
          'Jar',
          [100, 100, 300, 300],
          confidence: ScanConfidence.guess,
          alternatives: const ['Pickles'],
        ),
        item('Milk', [500, 500, 700, 700], confidence: ScanConfidence.likely),
      ];
      final zoomed = [
        item(
          'Salsa',
          [100, 100, 300, 300],
          confidence: ScanConfidence.sure,
          alternatives: const ['Jar', 'Tomato sauce'],
        ),
        item('Milk', [500, 500, 700, 700], confidence: ScanConfidence.likely),
      ];
      // 'Jar' and 'Salsa' differ, but 'Jar' is among Salsa's alternatives.
      final result = applyZoom(base, zoomed);
      expect(result, hasLength(2));
      expect(result[0].name, 'Salsa');
      expect(result[0].confidence, ScanConfidence.sure);
      expect(result[0].alternatives, ['Jar', 'Tomato sauce']);
      expect(identical(result[1], base[1]), isTrue);
    });

    test('lower or equal confidence leaves the base item untouched', () {
      final base = [
        item(
          'Milk',
          [100, 100, 300, 300],
          confidence: ScanConfidence.sure,
          alternatives: const ['Cream'],
        ),
      ];
      final result = applyZoom(base, [
        item('Milk', [100, 100, 300, 300], confidence: ScanConfidence.guess),
      ]);
      expect(result, hasLength(1));
      expect(identical(result.single, base.single), isTrue);
    });

    test('unmatched zoom items are added, base items never removed', () {
      final base = [item('Milk', [100, 100, 300, 300])];
      final result = applyZoom(base, [
        item('Butter', [600, 600, 700, 700], confidence: ScanConfidence.sure),
      ]);
      expect(result.map((i) => i.name), ['Milk', 'Butter']);
    });

    test('an empty zoom changes nothing', () {
      final base = [item('Milk', [100, 100, 300, 300]), item('Jam', null)];
      final result = applyZoom(base, const []);
      expect(result, hasLength(2));
      expect(identical(result[0], base[0]), isTrue);
      expect(identical(result[1], base[1]), isTrue);
    });

    test('boxless zoom items follow the name-and-location rule', () {
      final base = [
        item('Jam', null, confidence: ScanConfidence.guess, location: 'Door'),
      ];
      final result = applyZoom(base, [
        item('jam', null, confidence: ScanConfidence.sure, location: 'door'),
      ]);
      expect(result, hasLength(1));
      expect(result.single.confidence, ScanConfidence.sure);
    });
  });

  group('cross-tile merge without a name match', () {
    ScannedItem it(String name, List<int> box,
            {ScanConfidence c = ScanConfidence.likely}) =>
        ScannedItem(
          name: name,
          foodType: FoodType.other,
          confidence: c,
          alternatives: const [],
          location: 'shelf 2',
          box2d: box,
          photoIndex: 0,
          isFood: true,
        );

    test('nearly identical boxes from two tiles merge; other name kept', () {
      final merged = mergeScans(
        [it('Tomato stew', [100, 100, 300, 300], c: ScanConfidence.sure)],
        [
          [it('Salsa', [105, 102, 298, 300])],
        ],
      );
      expect(merged, hasLength(1));
      expect(merged.single.name, 'Tomato stew');
      expect(merged.single.alternatives.first, 'Salsa');
    });

    test('a small jar inside a big pot stays two items', () {
      final merged = mergeScans(
        [it('Pot of soup', [100, 100, 500, 500])],
        [
          [it('Jam', [200, 200, 260, 260])],
        ],
      );
      expect(merged, hasLength(2));
    });

    test('different names in the same call never merge', () {
      final merged = mergeScans([
        it('Tomato stew', [100, 100, 300, 300]),
        it('Salsa', [105, 102, 298, 300]),
      ], const []);
      expect(merged, hasLength(2));
    });
  });
}
