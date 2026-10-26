import 'dart:math' as math;

import 'scan_models.dart';

/// Boxes must overlap at least this much (IoU) to be the same object.
const _sameObjectIou = 0.3;

/// Most alternative names a merged item keeps.
const _maxAlternatives = 2;

/// Intersection over union of two `[ymin, xmin, ymax, xmax]` boxes. 0 when
/// they don't overlap or either has no area.
double iou(List<int> a, List<int> b) {
  final interH = math.min(a[2], b[2]) - math.max(a[0], b[0]);
  final interW = math.min(a[3], b[3]) - math.max(a[1], b[1]);
  if (interH <= 0 || interW <= 0) return 0;
  final inter = interH * interW;
  final areaA = (a[2] - a[0]) * (a[3] - a[1]);
  final areaB = (b[2] - b[0]) * (b[3] - b[1]);
  final union = areaA + areaB - inter;
  if (areaA <= 0 || areaB <= 0 || union <= 0) return 0;
  return inter / union;
}

String _singular(String token) {
  if (token.length > 3 && token.endsWith('ies')) {
    return '${token.substring(0, token.length - 3)}y';
  }
  if (token.length > 4 &&
      (token.endsWith('oes') ||
          token.endsWith('ches') ||
          token.endsWith('shes') ||
          token.endsWith('sses') ||
          token.endsWith('xes'))) {
    return token.substring(0, token.length - 2);
  }
  if (token.length > 3 && token.endsWith('s') && !token.endsWith('ss')) {
    return token.substring(0, token.length - 1);
  }
  return token;
}

List<String> _tokens(String name) => [
  for (final t in name.toLowerCase().trim().split(RegExp(r'[^a-z0-9]+')))
    if (t.isNotEmpty) _singular(t),
];

String _normalize(String name) => _tokens(name).join(' ');

bool _namesMatch(String a, String b) {
  final ta = _tokens(a).toSet();
  final tb = _tokens(b).toSet();
  if (ta.isEmpty || tb.isEmpty) return false;
  return ta.containsAll(tb) || tb.containsAll(ta);
}

bool _inAlternatives(String name, ScannedItem other) {
  final normalized = _normalize(name);
  if (normalized.isEmpty) return false;
  return other.alternatives.any((alt) => _normalize(alt) == normalized);
}

bool _hasBox(ScannedItem item) {
  final box = item.box2d;
  return box != null && box.length == 4;
}

String _locationKey(String location) => location.trim().toLowerCase();

/// Whether [a] and [b] are the same physical object. Returns the IoU used to
/// rank candidates, or null when they aren't the same.
double? _matchScore(ScannedItem a, ScannedItem b) {
  if (a.photoIndex != b.photoIndex) return null;
  if (!_hasBox(a) || !_hasBox(b)) {
    final sameName = _normalize(a.name) == _normalize(b.name);
    final sameLocation = _locationKey(a.location) == _locationKey(b.location);
    return sameName && sameLocation && _normalize(a.name).isNotEmpty ? 0 : null;
  }
  final overlap = iou(a.box2d!, b.box2d!);
  if (overlap < _sameObjectIou) return null;
  final named =
      _namesMatch(a.name, b.name) ||
      _inAlternatives(a.name, b) ||
      _inAlternatives(b.name, a);
  return named ? overlap : null;
}

/// Strictly more trusted? [ScanConfidence] is declared most-trusted first.
bool _moreConfident(ScannedItem a, ScannedItem b) =>
    a.confidence.index < b.confidence.index;

/// [primary]'s alternatives first, then [secondary]'s, without duplicates or
/// [primary]'s own name, at most two.
List<String> _unionAlternatives(ScannedItem primary, ScannedItem secondary) {
  final seen = <String>{_normalize(primary.name)};
  final result = <String>[];
  for (final alt in [...primary.alternatives, ...secondary.alternatives]) {
    if (seen.add(_normalize(alt))) result.add(alt);
    if (result.length == _maxAlternatives) break;
  }
  return result;
}

ScannedItem _combine(ScannedItem kept, ScannedItem other) {
  return ScannedItem(
    name: kept.name,
    foodType: kept.foodType,
    confidence: kept.confidence,
    alternatives: _unionAlternatives(kept, other),
    location: kept.location,
    box2d: kept.box2d ?? other.box2d,
    photoIndex: kept.photoIndex,
    isFood: kept.isFood,
    amount: kept.amount,
    description: kept.description,
    expiryEstimateDays: kept.expiryEstimateDays,
  );
}

/// Folds the items from extra tile scans into [base]; all boxes must already
/// be in full-photo space.
///
/// An extra item is the same object as an existing one when their boxes reach
/// IoU 0.3 and the names match (case, plural and word-subset tolerant) or one
/// name is among the other's alternatives. Items without a box match only on
/// the same name and location. The more confident of the pair is kept (the
/// earlier on a tie) with the alternatives of both, at most two. Unmatched
/// items are appended, so an item seen in two overlapping tiles counts once.
///
/// Two items from the same list never merge with each other (two egg cartons
/// side by side stay two). Output order: [base], then new items in input order.
List<ScannedItem> mergeScans(
  List<ScannedItem> base,
  List<List<ScannedItem>> extra,
) {
  final result = List<ScannedItem>.of(base);
  // Which lists have already contributed to each result entry; -1 is [base].
  final sources = <Set<int>>[for (var i = 0; i < base.length; i++) {-1}];
  for (var k = 0; k < extra.length; k++) {
    for (final item in extra[k]) {
      var bestIndex = -1;
      var bestScore = -1.0;
      for (var i = 0; i < result.length; i++) {
        if (sources[i].contains(k)) continue;
        final score = _matchScore(result[i], item);
        if (score != null && score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }
      if (bestIndex < 0) {
        result.add(item);
        sources.add({k});
        continue;
      }
      final existing = result[bestIndex];
      result[bestIndex] = _moreConfident(item, existing)
          ? _combine(item, existing)
          : _combine(existing, item);
      sources[bestIndex].add(k);
    }
  }
  return result;
}

/// Folds a closer look ([zoomed], boxes in full-photo space) into [base].
///
/// A zoomed item replaces its matching base item only when its confidence is
/// strictly higher, taking the union of both alternative lists. Matches that
/// aren't an upgrade leave the base item untouched. Unmatched zoomed items
/// are added. Base items are never removed.
List<ScannedItem> applyZoom(List<ScannedItem> base, List<ScannedItem> zoomed) {
  final result = List<ScannedItem>.of(base);
  final claimed = <int>{};
  for (final item in zoomed) {
    var bestIndex = -1;
    var bestScore = -1.0;
    for (var i = 0; i < base.length; i++) {
      if (claimed.contains(i)) continue;
      final score = _matchScore(base[i], item);
      if (score != null && score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) {
      result.add(item);
      continue;
    }
    claimed.add(bestIndex);
    if (_moreConfident(item, base[bestIndex])) {
      result[bestIndex] = _combine(item, base[bestIndex]);
    }
  }
  return result;
}
