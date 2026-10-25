import 'package:flutter_test/flutter_test.dart';

import '../tool/scan_eval/scorer.dart';

AnswerKey _key() => AnswerKey.fromJson({
  'photos': {
    'blurry': {'file': 'photos/blurry.jpg'},
    'clear': {'file': 'photos/clear.jpg'},
  },
  'items': [
    {
      'id': 'cheese',
      'names': ['knik white cheese', 'white cheese', 'feta'],
      'isFood': true,
      'tier': 'readable',
      'visibleInBlurryPhoto': true,
    },
    {
      'id': 'eggs',
      'names': ['egg'],
      'isFood': true,
      'tier': 'recognizable',
      'visibleInBlurryPhoto': true,
    },
    {
      'id': 'tomato',
      'names': ['tomato'],
      'isFood': true,
      'tier': 'recognizable',
      'visibleInBlurryPhoto': false,
    },
    {
      'id': 'flour',
      'names': ['flour'],
      'isFood': true,
      'tier': 'hidden',
      'visibleInBlurryPhoto': false,
    },
    {
      'id': 'tray',
      'names': ['ice tray'],
      'isFood': false,
      'tier': 'recognizable',
      'visibleInBlurryPhoto': true,
    },
  ],
});

KeyItem _item(
  String id,
  List<String> names, {
  bool food = true,
  String tier = 'recognizable',
  bool blurry = true,
}) => KeyItem(
  id: id,
  names: names,
  isFood: food,
  tier: tier,
  visibleInBlurryPhoto: blurry,
);

/// Small key that reproduces the real answer_key.json collisions.
AnswerKey _collisionKey() => AnswerKey(
  photoFiles: const {'blurry': 'b.jpg', 'clear': 'c.jpg'},
  items: [
    _item('knik_cheese', ['knik white cheese', 'white cheese', 'feta', 'cheese']),
    _item('white_eggs', ['eggs', 'white eggs', 'egg carton']),
    _item('brown_eggs', ['brown eggs', 'eggs', 'egg carton']),
    _item('dark_sauce', ['dark sauce', 'syrup']),
    _item('orange_lid_tub', ['cottage cheese', 'labneh', 'cream cheese', 'ricotta']),
    _item('brown_jar', ['date syrup', 'jam', 'honey']),
    _item(
      'philadelphia',
      ['philadelphia cream cheese', 'cream cheese', 'philadelphia'],
      tier: 'readable',
      blurry: false,
    ),
    _item('honey', ['honey', 'honey jar']),
    _item('tie_food', ['gel']),
    _item('nf_liquid_medicine', ['liquid medicine', 'cough syrup'], food: false),
    _item('nf_tie', ['gel'], food: false, blurry: false),
  ],
);

ScanOutputItem _o(
  String name, {
  List<String> alt = const [],
  String? confidence,
}) => ScanOutputItem(name, alternatives: alt, confidence: confidence);

void main() {
  final key = _key();

  group('name matching', () {
    test('accepted names and token overlap', () {
      final s = scorePhoto(key, 'clear', [_o('Feta Cheese')]);
      expect(s.hits, ['cheese']);
      final s2 = scorePhoto(key, 'clear', [_o('  WHITE cheese ')]);
      expect(s2.hits, ['cheese']);
    });

    test('plurals', () {
      expect(scorePhoto(key, 'clear', [_o('Eggs')]).hits, ['eggs']);
      expect(scorePhoto(key, 'clear', [_o('Tomatoes')]).hits, ['tomato']);
      expect(nameTokens('Berries'), ['berry']);
      expect(nameTokens('cookies'), nameTokens('cookie'));
      expect(nameTokens('cheeses'), nameTokens('cheese'));
    });

    test('unrelated names do not match', () {
      final s = scorePhoto(key, 'clear', [_o('Orange juice')]);
      expect(s.hits, isEmpty);
      expect(s.falseItems, ['Orange juice']);
    });

    test('alternatives count toward a hit', () {
      final s = scorePhoto(key, 'clear', [
        _o('Mystery spread', alt: ['feta']),
      ]);
      expect(s.hits, ['cheese']);
      expect(s.falseItems, isEmpty);
    });
  });

  group('recall', () {
    test('per tier and combined on the clear photo', () {
      final s = scorePhoto(key, 'clear', [_o('feta'), _o('flour')]);
      expect(s.tierRecall['readable']!.hits, 1);
      expect(s.tierRecall['readable']!.total, 1);
      expect(s.tierRecall['recognizable']!.hits, 0);
      expect(s.tierRecall['recognizable']!.total, 2);
      expect(s.tierRecall['hidden']!.recall, 1.0);
      expect(s.combinedRecall.hits, 1);
      expect(s.combinedRecall.total, 3);
      expect(s.misses, ['eggs', 'tomato']);
    });

    test('blurry photo only counts visibleInBlurryPhoto items', () {
      final s = scorePhoto(key, 'blurry', [_o('feta')]);
      expect(s.tierRecall['recognizable']!.total, 1);
      expect(s.tierRecall['hidden']!.total, 0);
      expect(s.tierRecall['hidden']!.recall, isNull);
      expect(s.combinedRecall.total, 2);
      expect(s.misses, ['eggs']);
    });

    test('an out-of-scope blurry match is neutral', () {
      final s = scorePhoto(key, 'blurry', [_o('tomato'), _o('feta')]);
      expect(s.hits, ['cheese']);
      expect(s.outOfScope, ['tomato']);
      expect(s.falseItems, isEmpty);
      expect(s.surePrecision, 1.0);
    });
  });

  group('duplicates, leaks, false items', () {
    test('a key item is hit at most once', () {
      final s = scorePhoto(key, 'clear', [_o('Eggs'), _o('egg'), _o('eggs')]);
      expect(s.hits, ['eggs']);
      expect(s.duplicates, ['egg', 'eggs']);
      expect(s.falseItems, isEmpty);
      expect(s.combinedRecall.hits, 1);
    });

    test('non-food key items are leaks, not hits or false items', () {
      final s = scorePhoto(key, 'clear', [_o('Ice tray'), _o('Napkin')]);
      expect(s.leaks, ['Ice tray']);
      expect(s.falseItems, ['Napkin']);
      expect(s.hits, isEmpty);
    });
  });

  group('sure precision', () {
    test('baseline items without confidence all count as sure', () {
      final s = scorePhoto(key, 'clear', [_o('feta'), _o('Napkin')]);
      expect(s.sureCount, 2);
      expect(s.sureHits, 1);
      expect(s.surePrecision, 0.5);
    });

    test('only sure items are in the denominator', () {
      final s = scorePhoto(key, 'clear', [
        _o('feta', confidence: 'sure'),
        _o('Napkin', confidence: 'unsure'),
        _o('flour', confidence: 'unsure'),
        _o('Pickles', confidence: 'sure'),
      ]);
      expect(s.sureCount, 2);
      expect(s.sureHits, 1);
      expect(s.surePrecision, 0.5);
      expect(s.hits, ['cheese', 'flour']);
    });

    test('is null when nothing is sure', () {
      final s = scorePhoto(key, 'clear', [_o('feta', confidence: 'unsure')]);
      expect(s.surePrecision, isNull);
    });
  });

  group('identity first, global assignment', () {
    final k = _collisionKey();

    List<String> sorted(List<String> l) => [...l]..sort();

    test('shared name: two cartons both match "eggs" (rules 1, 3)', () {
      final s = scorePhoto(k, 'clear', [_o('eggs'), _o('eggs')]);
      expect(sorted(s.hits), ['brown_eggs', 'white_eggs']);
      expect(s.duplicates, isEmpty);
    });

    test('three "eggs" over two cartons: 2 hits, 1 duplicate (rule 5)', () {
      final s = scorePhoto(k, 'clear', [_o('eggs'), _o('eggs'), _o('eggs')]);
      expect(s.hits, hasLength(2));
      expect(s.duplicates, ['eggs']);
    });

    test('a specific name cannot fall back to the other carton (rule 3)', () {
      final s = scorePhoto(k, 'clear', [_o('white eggs'), _o('white eggs')]);
      expect(s.hits, ['white_eggs']);
      expect(s.duplicates, ['white eggs']);
      expect(s.falseItems, isEmpty);
    });

    test('cream cheese + labneh hit two items in either order (rules 1, 3)', () {
      for (final names in [
        ['cream cheese', 'labneh'],
        ['labneh', 'cream cheese'],
      ]) {
        final s = scorePhoto(k, 'clear', [for (final n in names) _o(n)]);
        expect(sorted(s.hits), ['orange_lid_tub', 'philadelphia'], reason: '$names');
        expect(s.duplicates, isEmpty);
      }
    });

    // Both rows accept "cream cheese" exactly, like the two egg cartons, so
    // two outputs fill both; a third is a duplicate, never a weaker
    // "cheese" hit on knik_cheese.
    test('cream cheese three times: 2 exact rows, then a duplicate (rule 5)', () {
      final s = scorePhoto(k, 'clear', [
        _o('cream cheese'),
        _o('Cream Cheese'),
        _o('cream cheeses'),
      ]);
      expect(sorted(s.hits), ['orange_lid_tub', 'philadelphia']);
      expect(s.duplicates, ['cream cheeses']);
    });

    test('a generic "cheese" does not steal from stronger matches (rule 1)', () {
      final s = scorePhoto(k, 'clear', [_o('cream cheese'), _o('cheese')]);
      expect(sorted(s.hits), ['knik_cheese', 'philadelphia']);
    });

    test('earlier key name wins: honey -> honey, not brown_jar (rule 1)', () {
      final s = scorePhoto(k, 'clear', [_o('honey')]);
      expect(s.hits, ['honey']);
      expect(s.misses, contains('brown_jar'));
    });

    test('more shared tokens beat fewer (rule 1)', () {
      final s = scorePhoto(k, 'clear', [_o('Philadelphia Cream Cheese Spread')]);
      expect(s.hits, ['philadelphia']);
    });

    test('cough syrup is a leak, not dark_sauce (rule 2)', () {
      final s = scorePhoto(k, 'clear', [_o('Cough Syrup')]);
      expect(s.leaks, ['Cough Syrup']);
      expect(s.hits, isEmpty);
      expect(s.misses, contains('dark_sauce'));
    });

    test('a plain "syrup" still hits dark_sauce (rule 1)', () {
      final s = scorePhoto(k, 'clear', [_o('syrup')]);
      expect(s.hits, ['dark_sauce']);
      expect(s.leaks, isEmpty);
    });

    test('non-food wins an exact tie with a food (rule 2)', () {
      final s = scorePhoto(k, 'clear', [_o('gel')]);
      expect(s.leaks, ['gel']);
      expect(s.hits, isEmpty);
    });

    // Root decision (2026-10-25): only the name decides a leak. The live
    // v2 runs listed foods like "Spice jar" with "supplement" as an
    // alternative, which are not medicine reaching the meal agent.
    test('a non-food alternative alone is not a leak', () {
      final s = scorePhoto(k, 'clear', [
        _o('Brown liquid', alt: ['cough syrup']),
      ]);
      expect(s.leaks, isEmpty);
      expect(s.hits, ['dark_sauce']); // via "syrup"
    });

    test('repeated leaks are each leaks, never duplicates (rule 5)', () {
      final s = scorePhoto(k, 'clear', [_o('cough syrup'), _o('liquid medicine')]);
      expect(s.leaks, hasLength(2));
      expect(s.duplicates, isEmpty);
    });

    test('unmatched output is a false item (rule 5)', () {
      final s = scorePhoto(k, 'clear', [_o('Napkin')]);
      expect(s.falseItems, ['Napkin']);
    });

    test('output order does not change the result', () {
      final names = [
        'eggs',
        'eggs',
        'cream cheese',
        'labneh',
        'honey',
        'cheese',
        'cough syrup',
        'Napkin',
      ];
      PhotoScore score(List<String> n) =>
          scorePhoto(k, 'clear', [for (final x in n) _o(x)]);
      final forward = score(names);
      final reversed = score(names.reversed.toList());
      expect(sorted(reversed.hits), sorted(forward.hits));
      expect(reversed.leaks, forward.leaks);
      expect(reversed.falseItems, forward.falseItems);
      expect(reversed.duplicates.length, forward.duplicates.length);
      expect(forward.hits, hasLength(6)); // all but the leak and Napkin
      expect(forward.combinedRecall.hits, reversed.combinedRecall.hits);
    });
  });

  group('visibility after identity (blurry)', () {
    final k = _collisionKey();

    test('exact out-of-scope match is neutral, not a weaker hit (rule 4)', () {
      final s = scorePhoto(k, 'blurry', [_o('Philadelphia cream cheese')]);
      expect(s.outOfScope, ['Philadelphia cream cheese']);
      expect(s.hits, isEmpty);
      expect(s.misses, contains('orange_lid_tub'));
      expect(s.falseItems, isEmpty);
      expect(s.sureCount, 0);
      expect(s.surePrecision, isNull);
    });

    test('cream cheese is neutral and labneh still hits (rule 4)', () {
      final s = scorePhoto(k, 'blurry', [_o('cream cheese'), _o('labneh')]);
      expect(s.hits, ['orange_lid_tub']);
      expect(s.outOfScope, ['cream cheese']);
      expect(s.sureCount, 1);
      expect(s.surePrecision, 1.0);
    });

    test('a repeat of a neutral output is neutral, not a duplicate (rule 4)', () {
      final s = scorePhoto(k, 'blurry', [_o('philadelphia'), _o('philadelphia')]);
      expect(s.outOfScope, hasLength(2));
      expect(s.duplicates, isEmpty);
    });

    test('leaks stay leaks on blurry even for invisible non-food (rule 2)', () {
      final s = scorePhoto(k, 'blurry', [_o('cough syrup')]);
      expect(s.leaks, ['cough syrup']);
    });

    test('the same cream cheese outputs on clear are two hits', () {
      final s = scorePhoto(k, 'clear', [_o('cream cheese'), _o('labneh')]);
      expect(s.hits, hasLength(2));
    });
  });

  test('median', () {
    expect(median([3, 1, 2]), 2.0);
    expect(median([1, 2, 3, 4]), 2.5);
    expect(median(<num>[]), isNull);
  });

  group('hedged names and alternatives', () {
    final k = AnswerKey.fromJson({
      'photos': {'clear': {'file': 'x.jpg'}},
      'items': [
        {'id': 'dark_sauce', 'names': ['dark sauce', 'syrup', 'sauce'], 'zone': 'z', 'isFood': true, 'tier': 'recognizable', 'visibleInBlurryPhoto': true},
        {'id': 'spices', 'names': ['spices', 'spice'], 'zone': 'z', 'isFood': true, 'tier': 'recognizable', 'visibleInBlurryPhoto': true},
        {'id': 'nf_supp', 'names': ['supplement bottle', 'supplements'], 'zone': 'z', 'isFood': false, 'tier': 'readable', 'visibleInBlurryPhoto': true},
        {'id': 'nf_med', 'names': ['medicine', 'cough syrup'], 'zone': 'z', 'isFood': false, 'tier': 'readable', 'visibleInBlurryPhoto': true},
      ],
    });

    test('an "A or B" name tries both halves', () {
      final s = scorePhoto(k, 'clear', [_o('Salsa or Dark Sauce')]);
      expect(s.hits, ['dark_sauce']);
    });

    test('a non-food alternative does not make a food guess a leak', () {
      final s = scorePhoto(k, 'clear', [
        _o('Spice jar', alt: ['supplements']),
      ]);
      expect(s.leaks, isEmpty);
      expect(s.hits, ['spices']);
    });

    test('a non-food main name is still a leak', () {
      final s = scorePhoto(k, 'clear', [_o('Cough syrup')]);
      expect(s.leaks, ['Cough syrup']);
    });

    test('a hedged name naming medicine stays a leak when it is the best match', () {
      final s = scorePhoto(k, 'clear', [_o('Supplements or vitamins')]);
      expect(s.leaks, ['Supplements or vitamins']);
    });
  });
}
