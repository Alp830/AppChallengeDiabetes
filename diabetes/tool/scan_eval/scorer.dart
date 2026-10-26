import 'dart:convert';
import 'dart:io';

/// Pure-Dart scoring of fridge-scan output against `answer_key.json`.
/// No Flutter or network imports, so it runs offline.

const tiers = ['readable', 'recognizable', 'hidden'];

class KeyItem {
  const KeyItem({
    required this.id,
    required this.names,
    required this.isFood,
    required this.tier,
    required this.visibleInBlurryPhoto,
    this.scene = defaultScene,
    this.zone = '',
  });

  factory KeyItem.fromJson(Map<String, dynamic> json) {
    return KeyItem(
      id: json['id'] as String,
      names: [for (final n in json['names'] as List<dynamic>) n as String],
      zone: (json['zone'] ?? '') as String,
      isFood: (json['isFood'] ?? true) as bool,
      tier: (json['tier'] ?? 'hidden') as String,
      visibleInBlurryPhoto: (json['visibleInBlurryPhoto'] ?? false) as bool,
      scene: (json['scene'] ?? defaultScene) as String,
    );
  }

  final String id;
  final List<String> names;
  final String zone;
  final bool isFood;
  final String tier;
  final bool visibleInBlurryPhoto;

  /// Which physical place this item is in. A photo is only scored against the
  /// items of its own scene (see [AnswerKey.photoScenes]).
  final String scene;
}

class AnswerKey {
  const AnswerKey({
    required this.photoFiles,
    required this.items,
    this.photoScenes = const {},
  });

  factory AnswerKey.fromJson(Map<String, dynamic> json) {
    final photos = json['photos'] as Map<String, dynamic>;
    return AnswerKey(
      photoFiles: {
        for (final entry in photos.entries)
          entry.key: (entry.value as Map<String, dynamic>)['file'] as String,
      },
      items: [
        for (final item in json['items'] as List<dynamic>)
          KeyItem.fromJson(item as Map<String, dynamic>),
      ],
      photoScenes: {
        for (final entry in photos.entries)
          entry.key:
              ((entry.value as Map<String, dynamic>)['scene'] ?? defaultScene)
                  as String,
      },
    );
  }

  static AnswerKey load(String path) =>
      AnswerKey.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);

  /// Photo id -> file path relative to tool/scan_eval/.
  final Map<String, String> photoFiles;
  final List<KeyItem> items;

  /// Photo id -> the scene it shows. Photos without one show [defaultScene].
  final Map<String, String> photoScenes;

  /// Only the items in [photo]'s scene.
  AnswerKey forPhoto(String photo) {
    final scene = photoScenes[photo] ?? defaultScene;
    return AnswerKey(
      photoFiles: photoFiles,
      photoScenes: photoScenes,
      items: [for (final k in items) if (k.scene == scene) k],
    );
  }
}

/// The scene of the original two eval photos (the owner's home fridge).
const defaultScene = 'home_fridge';

/// One item a scan returned. [confidence] is null for the baseline scan,
/// which has no such field; null counts as "sure".
class ScanOutputItem {
  const ScanOutputItem(
    this.name, {
    this.alternatives = const [],
    this.confidence,
  });

  final String name;
  final List<String> alternatives;
  final String? confidence;

  bool get isSure => confidence == null || confidence!.toLowerCase() == 'sure';
}

/// Lowercase, trim, and singularize every word ("ies" -> "y", "es" after
/// ch/sh/x/z/o/ss, else strip a trailing "s"). A singular "ie" ending also
/// becomes "y" so "cookie" and "cookies" agree. Short words are left alone.
List<String> nameTokens(String name) {
  final words = name
      .toLowerCase()
      .trim()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty);
  return [for (final w in words) _singular(w)];
}

String _singular(String word) {
  if (word.length <= 3) return word;
  if (word.endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
  if (word.endsWith('ss')) return word;
  if (RegExp(r'(ch|sh|x|z|o|ss)es$').hasMatch(word)) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s')) return word.substring(0, word.length - 1);
  if (word.endsWith('ie')) return '${word.substring(0, word.length - 2)}y';
  return word;
}

/// 0 when [a] and [b] do not match, else a score in (0, 1]. They match when
/// every token of one is a token of the other ("feta cheese" ~ "feta").
double nameMatchScore(String a, String b) {
  final ta = nameTokens(a).toSet();
  final tb = nameTokens(b).toSet();
  if (ta.isEmpty || tb.isEmpty) return 0;
  final shared = ta.intersection(tb).length;
  if (shared != ta.length && shared != tb.length) return 0;
  return shared / ta.union(tb).length;
}

/// How strongly an output matches a key item. Ordered by: exact normalized
/// name equality, then shared token count, then overlap ratio, then an earlier
/// position in the key item's `names` (earlier = more canonical).
class MatchStrength implements Comparable<MatchStrength> {
  const MatchStrength(this.exact, this.shared, this.ratio, this.nameIndex);

  final bool exact;
  final int shared;
  final double ratio;
  final int nameIndex;

  @override
  int compareTo(MatchStrength other) {
    if (exact != other.exact) return exact ? 1 : -1;
    if (shared != other.shared) return shared.compareTo(other.shared);
    if (ratio != other.ratio) return ratio.compareTo(other.ratio);
    return other.nameIndex.compareTo(nameIndex);
  }

  /// Like [compareTo] without the name-position tie-break. Name position
  /// only orders an output's candidates; it never removes one, so "eggs"
  /// still reaches both egg cartons even when it is the second name of one.
  int compareIgnoringNameIndex(MatchStrength other) {
    if (exact != other.exact) return exact ? 1 : -1;
    if (shared != other.shared) return shared.compareTo(other.shared);
    return ratio.compareTo(other.ratio);
  }
}

MatchStrength? _pairStrength(String out, String accepted, int nameIndex) {
  final ta = nameTokens(out);
  final tb = nameTokens(accepted);
  final sa = ta.toSet();
  final sb = tb.toSet();
  if (sa.isEmpty || sb.isEmpty) return null;
  final shared = sa.intersection(sb).length;
  if (shared != sa.length && shared != sb.length) return null;
  final exact = sa.length == sb.length && shared == sa.length;
  return MatchStrength(exact, shared, shared / sa.union(sb).length, nameIndex);
}

/// Best strength of any of [outputNames] against any name of [key]; null when
/// nothing matches.
MatchStrength? _itemStrength(Iterable<String> outputNames, KeyItem key) {
  MatchStrength? best;
  for (final out in outputNames) {
    for (var i = 0; i < key.names.length; i++) {
      final s = _pairStrength(out, key.names[i], i);
      if (s != null && (best == null || s.compareTo(best) > 0)) best = s;
    }
  }
  return best;
}

class TierRecall {
  const TierRecall(this.hits, this.total);

  final int hits;
  final int total;

  /// Null when the tier has no items in scope.
  double? get recall => total == 0 ? null : hits / total;
}

class PhotoScore {
  const PhotoScore({
    required this.photo,
    required this.tierRecall,
    required this.combinedRecall,
    required this.hits,
    required this.misses,
    required this.falseItems,
    required this.leaks,
    required this.duplicates,
    required this.outOfScope,
    required this.sureHits,
    required this.sureCount,
  });

  final String photo;
  final Map<String, TierRecall> tierRecall;

  /// readable + recognizable together.
  final TierRecall combinedRecall;
  final List<String> hits;
  final List<String> misses;

  /// Output names matching no food key item.
  final List<String> falseItems;

  /// Output names matching an isFood=false key item (and no food item).
  final List<String> leaks;

  /// Output names matching only food items that were already hit.
  final List<String> duplicates;

  /// Output names matching a food item the blurry photo cannot show. Neutral:
  /// neither a hit nor a false item.
  final List<String> outOfScope;
  final int sureHits;
  final int sureCount;

  /// Null when the scan returned no "sure" items.
  double? get surePrecision => sureCount == 0 ? null : sureHits / sureCount;
}

/// Splits a hedged name such as "Salsa or Hot Sauce" or "jam/preserves"
/// into its guesses; a plain name comes back as itself.
List<String> splitNameGuesses(String name) {
  final parts = name
      .split(RegExp(r'\s+or\s+|\s*/\s*', caseSensitive: false))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  return parts.isEmpty ? [name] : parts;
}

PhotoScore scorePhoto(
  AnswerKey fullKey,
  String photo,
  List<ScanOutputItem> output,
) {
  final key = fullKey.forPhoto(photo);
  bool inScope(KeyItem k) =>
      k.isFood && (!_blurryScope(photo) || k.visibleInBlurryPhoto);
  final scoped = key.items.where(inScope).toList();
  final blurry = _blurryScope(photo);

  // 1. Identity: each output's candidates are the key items (food or not,
  // visible or not) at its single best strength.
  final candidates = <List<KeyItem>>[];
  for (final item in output) {
    // "Salsa or hot sauce" names two guesses; each half is tried. Only the
    // name can make a leak: a food whose alternatives mention "supplement"
    // was still added as food by its main guess.
    final nameParts = splitNameGuesses(item.name);
    final names = [...nameParts, ...item.alternatives];
    MatchStrength? best;
    var set = <KeyItem>[];
    final strengths = <String, MatchStrength>{};
    for (final k in key.items) {
      final s = _itemStrength(k.isFood ? names : nameParts, k);
      if (s == null) continue;
      strengths[k.id] = s;
      final cmp = best == null ? 1 : s.compareIgnoringNameIndex(best);
      if (cmp > 0) {
        best = s;
        set = [k];
      } else if (cmp == 0) {
        set.add(k);
      }
    }
    // Most canonical name first (stable), so a lone "honey" goes to the
    // honey jar rather than the jar that lists honey as its third guess.
    _stableSort(
      set,
      compare: (a, b) =>
          strengths[a.id]!.nameIndex.compareTo(strengths[b.id]!.nameIndex),
    );
    candidates.add(set);
  }

  // 2. A non-food in the best set is a leak; the rest are matched globally
  // against their food candidates only. On the blurry photo, candidates the
  // photo cannot show are tried last.
  final foodCandidates = <int, List<int>>{};
  final keyIndex = {for (var i = 0; i < key.items.length; i++) key.items[i].id: i};
  for (var i = 0; i < output.length; i++) {
    final set = candidates[i];
    if (set.isEmpty || set.any((k) => !k.isFood)) continue;
    // Keeps the name-position order from step 1; on the blurry photo,
    // candidates it cannot show go last (stable).
    final indexes = [for (final k in set) keyIndex[k.id]!];
    if (blurry) {
      _stableSort(
        indexes,
        compare: (a, b) {
          final va = key.items[a].visibleInBlurryPhoto ? 0 : 1;
          final vb = key.items[b].visibleInBlurryPhoto ? 0 : 1;
          return va.compareTo(vb);
        },
      );
    }
    foodCandidates[i] = indexes;
  }

  // Maximum-cardinality bipartite matching (augmenting paths), outputs in
  // order, so the result is deterministic.
  final ownerOfKey = <int, int>{};
  bool augment(int out, Set<int> seen) {
    for (final k in foodCandidates[out]!) {
      if (!seen.add(k)) continue;
      final owner = ownerOfKey[k];
      if (owner == null || augment(owner, seen)) {
        ownerOfKey[k] = out;
        return true;
      }
    }
    return false;
  }

  for (var i = 0; i < output.length; i++) {
    if (foodCandidates.containsKey(i)) augment(i, <int>{});
  }
  final keyOfOutput = {
    for (final e in ownerOfKey.entries) e.value: key.items[e.key],
  };

  // 3. Classify.
  final hitIds = <String>{};
  final hits = <String>[];
  final falseItems = <String>[];
  final leaks = <String>[];
  final duplicates = <String>[];
  final outOfScope = <String>[];
  var sureHits = 0;
  var sureCount = 0;

  for (var i = 0; i < output.length; i++) {
    final item = output[i];
    if (item.isSure) sureCount++;

    if (candidates[i].isEmpty) {
      falseItems.add(item.name);
    } else if (!foodCandidates.containsKey(i)) {
      leaks.add(item.name);
    } else {
      final matched = keyOfOutput[i];
      final neutral = matched != null
          ? !inScope(matched)
          : foodCandidates[i]!.every((k) => !inScope(key.items[k]));
      if (neutral) {
        outOfScope.add(item.name);
        if (item.isSure) sureCount--;
      } else if (matched != null) {
        hitIds.add(matched.id);
        hits.add(matched.id);
        if (item.isSure) sureHits++;
      } else {
        duplicates.add(item.name);
      }
    }
  }

  TierRecall recall(Iterable<String> tierNames) {
    final inTier = scoped.where((k) => tierNames.contains(k.tier)).toList();
    return TierRecall(inTier.where((k) => hitIds.contains(k.id)).length, inTier.length);
  }

  return PhotoScore(
    photo: photo,
    tierRecall: {for (final t in tiers) t: recall([t])},
    combinedRecall: recall(const ['readable', 'recognizable']),
    hits: hits,
    misses: [for (final k in scoped) if (!hitIds.contains(k.id)) k.id],
    falseItems: falseItems,
    leaks: leaks,
    duplicates: duplicates,
    outOfScope: outOfScope,
    sureHits: sureHits,
    sureCount: sureCount,
  );
}

/// Median of [values]; null when empty.
double? median(Iterable<num> values) {
  final sorted = values.map((v) => v.toDouble()).toList()..sort();
  if (sorted.isEmpty) return null;
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Insertion sort: stable, and the lists here are a few items long.
void _stableSort<T>(List<T> list, {required int Function(T, T) compare}) {
  for (var i = 1; i < list.length; i++) {
    final value = list[i];
    var j = i - 1;
    while (j >= 0 && compare(list[j], value) > 0) {
      list[j + 1] = list[j];
      j--;
    }
    list[j + 1] = value;
  }
}

/// Photos of the blurry webcam shot: the still, and frames from the same
/// clip (ids starting "blurry"), share its visibility flags.
bool _blurryScope(String photo) => photo.startsWith('blurry');
