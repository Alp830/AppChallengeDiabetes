import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scan_models.dart';

/// A pixel rectangle in the coordinates of the kept original photo.
///
/// Rects are cut at native scale (see [cutTile]) and only shrunk to the
/// upload size by [encodeTile]. Gemini gives every image the same token
/// budget whatever its pixel size, so what buys detail is how much of the
/// fridge one tile covers. Tiles are kept to at most [defaultTileFraction] of
/// the photo's long side, so even after shrinking to 2048 px a tile shows
/// about 1.7x the overview's detail per item, and never less (the "no view
/// zooms out" rule from arXiv 2610.09313).
class TileRect {
  const TileRect({
    required this.id,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String id;
  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;
  int get area => width * height;

  @override
  String toString() => 'TileRect($id, $left,$top ${width}x$height)';

  @override
  bool operator ==(Object other) =>
      other is TileRect &&
      other.id == id &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(id, left, top, width, height);
}

/// Photos whose longest side is below this multiple of the overview side have
/// no pixels a tile could show that the overview doesn't.
const _minTilingRatio = 1.5;

/// Most pieces one axis is split into; guards against runaway grids.
const _maxSplitsPerAxis = 12;

/// Default longest tile side as a fraction of the photo's longest side. A 2x2
/// grid with 12% overlap is about 0.56, so it stays 2x2.
const defaultTileFraction = 0.6;

int _defaultMaxTileSide(int w, int h) =>
    (defaultTileFraction * math.max(w, h)).round();

bool _tilingWorthwhile(int w, int h, int overviewMaxSide) =>
    math.max(w, h) >= _minTilingRatio * overviewMaxSide;

class _Span {
  const _Span(this.start, this.size);
  final int start;
  final int size;
}

/// Splits [length] pixels starting at [start] into at least [minPieces]
/// equal-sized spans, each at most [maxSide] long where possible, adjacent
/// spans overlapping by at least [overlap] x [length] pixels.
List<_Span> _splitAxis(
  int start,
  int length,
  int maxSide,
  double overlap,
  int minPieces,
) {
  if (length <= 0) return const [];
  var pieces = minPieces;
  if (pieces <= 1 && length <= maxSide) return [_Span(start, length)];
  if (pieces < 2) pieces = 2;
  // One extra pixel absorbs the rounding of the span positions below.
  final overlapPx = (overlap * length).ceil() + 1;
  int sizeFor(int n) => math.min(length, ((length + (n - 1) * overlapPx) / n).ceil());
  while (sizeFor(pieces) > maxSide && pieces < _maxSplitsPerAxis) {
    pieces++;
  }
  final size = sizeFor(pieces);
  final spans = <_Span>[];
  for (var i = 0; i < pieces; i++) {
    final offset = pieces == 1 ? 0 : (i * (length - size) / (pieces - 1)).round();
    spans.add(_Span(start + offset, size));
  }
  return spans;
}

List<TileRect> _tileRegion(
  String idPrefix,
  int left,
  int top,
  int width,
  int height, {
  required double overlap,
  required int maxTileSide,
  required int minPieces,
}) {
  final cols = _splitAxis(left, width, maxTileSide, overlap, minPieces);
  final rows = _splitAxis(top, height, maxTileSide, overlap, minPieces);
  final single = cols.length == 1 && rows.length == 1;
  return [
    for (var r = 0; r < rows.length; r++)
      for (var c = 0; c < cols.length; c++)
        TileRect(
          id: single ? idPrefix : '${idPrefix}r${r}c$c',
          left: cols[c].start,
          top: rows[r].start,
          width: cols[c].size,
          height: rows[r].size,
        ),
  ];
}

/// Overlapping native-resolution tiles covering the whole photo, or `[]` when
/// the longest side is under 1.5 x [overviewMaxSide] (tiles would show no new
/// pixels).
///
/// The base is a 2x2 grid; an axis whose tiles would exceed [maxTileSide]
/// (default [defaultTileFraction] of the long side) gets more pieces. Adjacent tiles overlap by at least
/// [overlap] x the photo side along that axis, so an item cut by one tile edge
/// sits whole in its neighbour. Tiles stay inside the photo.
List<TileRect> planGridTiles(
  int w,
  int h, {
  int overviewMaxSide = 2048,
  double overlap = 0.12,
  int? maxTileSide,
}) {
  if (!_tilingWorthwhile(w, h, overviewMaxSide)) return const [];
  return _tileRegion(
    'g',
    0,
    0,
    w,
    h,
    overlap: overlap,
    maxTileSide: maxTileSide ?? _defaultMaxTileSide(w, h),
    minPieces: 2,
  );
}

/// A normalized-pixel union of [ScannedItem] boxes.
class _PxBox {
  _PxBox(this.left, this.top, this.right, this.bottom);
  double left, top, right, bottom;

  void include(_PxBox o) {
    left = math.min(left, o.left);
    top = math.min(top, o.top);
    right = math.max(right, o.right);
    bottom = math.max(bottom, o.bottom);
  }

  _PxBox copy() => _PxBox(left, top, right, bottom);
}

_PxBox? _pixelBox(List<int>? box, int w, int h) {
  if (box == null || box.length != 4) return null;
  final top = math.min(box[0], box[2]).clamp(0, 1000) / 1000 * h;
  final bottom = math.max(box[0], box[2]).clamp(0, 1000) / 1000 * h;
  final left = math.min(box[1], box[3]).clamp(0, 1000) / 1000 * w;
  final right = math.max(box[1], box[3]).clamp(0, 1000) / 1000 * w;
  return _PxBox(left, top, right, bottom);
}

_PxBox? _union(Iterable<_PxBox> boxes) {
  _PxBox? result;
  for (final box in boxes) {
    if (result == null) {
      result = box.copy();
    } else {
      result.include(box);
    }
  }
  return result;
}

/// Pads [box] by [pad] of its own size per side and rounds outwards to whole
/// pixels inside a [w] x [h] photo.
({int left, int top, int width, int height}) _padAndClamp(
  _PxBox box,
  double pad,
  int w,
  int h,
) {
  final padX = (box.right - box.left) * pad;
  final padY = (box.bottom - box.top) * pad;
  final left = (box.left - padX).floor().clamp(0, w - 1);
  final top = (box.top - padY).floor().clamp(0, h - 1);
  final right = (box.right + padX).ceil().clamp(left + 1, w);
  final bottom = (box.bottom + padY).ceil().clamp(top + 1, h);
  return (left: left, top: top, width: right - left, height: bottom - top);
}

/// Tiles around where pass 1 found food: one region for the door shelves
/// (items whose location contains "door") and one for the main compartment
/// (everything else). Each region is the union of its item boxes padded by
/// [pad] of its own size, clamped to the photo, and split like the grid when a
/// side exceeds [maxTileSide]. Regions without boxed items are skipped; with
/// no boxed item at all this falls back to [planGridTiles]. Returns `[]` under
/// the same 1.5x rule as [planGridTiles].
List<TileRect> planZoneTiles(
  int w,
  int h,
  List<ScannedItem> pass1Items, {
  double pad = 0.12,
  int? maxTileSide,
  int overviewMaxSide = 2048,
}) {
  if (!_tilingWorthwhile(w, h, overviewMaxSide)) return const [];
  final door = <_PxBox>[];
  final main = <_PxBox>[];
  for (final item in pass1Items) {
    final box = _pixelBox(item.box2d, w, h);
    if (box == null) continue;
    (item.location.toLowerCase().contains('door') ? door : main).add(box);
  }
  if (door.isEmpty && main.isEmpty) {
    return planGridTiles(
      w,
      h,
      overviewMaxSide: overviewMaxSide,
      maxTileSide: maxTileSide,
    );
  }
  final tiles = <TileRect>[];
  for (final family in [('door', door), ('main', main)]) {
    final union = _union(family.$2);
    if (union == null) continue;
    final r = _padAndClamp(union, pad, w, h);
    tiles.addAll(
      _tileRegion(
        family.$1,
        r.left,
        r.top,
        r.width,
        r.height,
        overlap: pad,
        maxTileSide: maxTileSide ?? _defaultMaxTileSide(w, h),
        minPieces: 1,
      ),
    );
  }
  return tiles;
}

bool _overlaps(_PxRect a, _PxRect b) =>
    a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

class _PxRect {
  _PxRect(this.left, this.top, this.right, this.bottom);
  int left, top, right, bottom;
  int get width => right - left;
  int get height => bottom - top;
  int get area => width * height;

  void include(_PxRect o) {
    left = math.min(left, o.left);
    top = math.min(top, o.top);
    right = math.max(right, o.right);
    bottom = math.max(bottom, o.bottom);
  }
}

/// Grows [lo, hi) to [minSize] around its centre, shifting inside [0, limit].
(int, int) _growAxis(int lo, int hi, int minSize, int limit) {
  final target = math.min(minSize, limit);
  if (hi - lo >= target) return (lo, hi);
  var newLo = ((lo + hi) / 2 - target / 2).round();
  newLo = newLo.clamp(0, limit - target);
  return (newLo, newLo + target);
}

/// Rectangles for a second, closer look at what pass 1 was unsure of: around
/// every `guess` item's box, plus the union box of each zone whose stated count
/// exceeds the number of items located there (case-insensitive). Each is padded
/// by [pad]; overlapping crops merge until none overlap; the [maxCrops]
/// largest are kept; any smaller than [minSide] grows around its centre
/// (clamped to the photo). These are rects only; [cutTile] never upscales.
List<TileRect> planZoomCrops(
  int w,
  int h,
  List<ScannedItem> items,
  List<ScanZone> zones, {
  double pad = 0.12,
  int maxCrops = 6,
  int minSide = 256,
}) {
  if (w <= 0 || h <= 0 || maxCrops <= 0) return const [];
  final crops = <_PxRect>[];

  void addBox(_PxBox box) {
    final r = _padAndClamp(box, pad, w, h);
    crops.add(_PxRect(r.left, r.top, r.left + r.width, r.top + r.height));
  }

  for (final item in items) {
    if (item.confidence != ScanConfidence.guess) continue;
    final box = _pixelBox(item.box2d, w, h);
    if (box != null) addBox(box);
  }

  String key(String s) => s.trim().toLowerCase();
  for (final zone in zones) {
    final zoneKey = key(zone.name);
    final inZone = items.where((i) => key(i.location) == zoneKey).toList();
    if (zone.count <= inZone.length) continue;
    final union = _union(
      inZone.map((i) => _pixelBox(i.box2d, w, h)).whereType<_PxBox>(),
    );
    if (union != null) addBox(union);
  }

  var merged = true;
  while (merged) {
    merged = false;
    outer:
    for (var i = 0; i < crops.length; i++) {
      for (var j = i + 1; j < crops.length; j++) {
        if (_overlaps(crops[i], crops[j])) {
          crops[i].include(crops[j]);
          crops.removeAt(j);
          merged = true;
          break outer;
        }
      }
    }
  }

  // Stable sort by area, largest first, so ties keep input order.
  final indexed = [for (var i = 0; i < crops.length; i++) (i, crops[i])];
  indexed.sort((a, b) {
    final byArea = b.$2.area.compareTo(a.$2.area);
    return byArea != 0 ? byArea : a.$1.compareTo(b.$1);
  });
  final kept = [for (final e in indexed.take(maxCrops)) e.$2];
  kept.sort((a, b) {
    final byTop = a.top.compareTo(b.top);
    return byTop != 0 ? byTop : a.left.compareTo(b.left);
  });

  return [
    for (var i = 0; i < kept.length; i++)
      () {
        final c = kept[i];
        final (l, r) = _growAxis(c.left, c.right, minSide, w);
        final (t, b) = _growAxis(c.top, c.bottom, minSide, h);
        return TileRect(
          id: 'zoom$i',
          left: l,
          top: t,
          width: r - l,
          height: b - t,
        );
      }(),
  ];
}

/// Cuts [r] out of [original] at native resolution (no resampling).
img.Image cutTile(img.Image original, TileRect r) {
  return img.copyCrop(
    original,
    x: r.left,
    y: r.top,
    width: r.width,
    height: r.height,
  );
}

/// JPEG-encodes a cut tile, shrinking it (never enlarging) so its longest
/// side is at most [maxSide], the same bound as the overview upload.
Uint8List encodeTile(img.Image tile, {int quality = 85, int maxSide = 2048}) {
  var out = tile;
  if (math.max(tile.width, tile.height) > maxSide) {
    out = img.copyResize(
      tile,
      width: tile.width >= tile.height ? maxSide : null,
      height: tile.height > tile.width ? maxSide : null,
      interpolation: img.Interpolation.average,
    );
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}

/// Maps a `[ymin, xmin, ymax, xmax]` box on a 0–1000 grid over tile [r] to the
/// 0–1000 grid over the whole [w] x [h] photo.
List<int> tileBoxToPhoto(List<int> box, TileRect r, int w, int h) {
  int y(int v) => ((r.top + v / 1000 * r.height) / h * 1000).round().clamp(0, 1000);
  int x(int v) => ((r.left + v / 1000 * r.width) / w * 1000).round().clamp(0, 1000);
  return [y(box[0]), x(box[1]), y(box[2]), x(box[3])];
}
