import 'dart:math' as math;

import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:diabetes/fridge/scan/tile_planner.dart';
import 'package:diabetes/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

ScannedItem item(
  String name,
  List<int>? box, {
  String location = 'shelf 1',
  ScanConfidence confidence = ScanConfidence.sure,
}) => ScannedItem(
  name: name,
  foodType: FoodType.other,
  confidence: confidence,
  location: location,
  box2d: box,
);

void expectCovers(List<TileRect> tiles, int w, int h) {
  for (var y = 0; y < h; y += 8) {
    for (var x = 0; x < w; x += 8) {
      final inside = tiles.any(
        (t) => x >= t.left && x < t.right && y >= t.top && y < t.bottom,
      );
      if (!inside) fail('uncovered $x,$y');
    }
  }
}

void main() {
  group('planGridTiles', () {
    test('skips photos that are not at least 1.5x the overview', () {
      expect(planGridTiles(1920, 1080), isEmpty);
      expect(planGridTiles(2048, 1536), isEmpty);
      expect(planGridTiles(3000, 2000), isEmpty);
      expect(planGridTiles(2000, 3071), isEmpty);
    });

    test('tiles a 3072px photo as a 2x2 grid', () {
      final tiles = planGridTiles(3072, 2304);
      expect(tiles, hasLength(4));
      expectCovers(tiles, 3072, 2304);
      for (final t in tiles) {
        expect(math.max(t.width, t.height), lessThanOrEqualTo(0.6 * 3072));
      }
    });

    // 2x2 even at 24 MP: each tile is at most 0.6 of the long side, so it
    // still shows ~1.7x the overview's detail after shrinking to 2048 px.
    test('covers a 4284x5712 photo with a 2x2 grid and 12% overlap', () {
      const w = 4284, h = 5712;
      final tiles = planGridTiles(w, h);
      expect(tiles, hasLength(4));
      expect({for (final t in tiles) t.id}, hasLength(tiles.length));
      for (final t in tiles) {
        expect(math.max(t.width, t.height), lessThanOrEqualTo(0.6 * h));
        expect(t.left, greaterThanOrEqualTo(0));
        expect(t.top, greaterThanOrEqualTo(0));
        expect(t.right, lessThanOrEqualTo(w));
        expect(t.bottom, lessThanOrEqualTo(h));
      }
      expectCovers(tiles, w, h);

      // Adjacent columns / rows overlap by at least 12% of that side.
      final lefts = ({for (final t in tiles) t.left}.toList()..sort());
      final tops = ({for (final t in tiles) t.top}.toList()..sort());
      final tileW = tiles.first.width;
      final tileH = tiles.first.height;
      for (var i = 0; i + 1 < lefts.length; i++) {
        expect(
          lefts[i] + tileW - lefts[i + 1],
          greaterThanOrEqualTo((0.12 * w).ceil()),
        );
      }
      for (var i = 0; i + 1 < tops.length; i++) {
        expect(
          tops[i] + tileH - tops[i + 1],
          greaterThanOrEqualTo((0.12 * h).ceil()),
        );
      }
    });
  });

  group('planZoneTiles', () {
    test('skips small photos', () {
      expect(
        planZoneTiles(3000, 2000, [item('milk', [0, 0, 500, 500])]),
        isEmpty,
      );
    });

    test('separates door from main compartment', () {
      const w = 4000, h = 4000;
      final tiles = planZoneTiles(w, h, [
        item('milk', [100, 100, 300, 300], location: 'main shelf'),
        item('eggs', [400, 200, 500, 400], location: 'Shelf 2'),
        item('ketchup', [100, 800, 300, 900], location: 'Door bin 1'),
      ]);
      expect(tiles.map((t) => t.id), ['door', 'main']);
      final door = tiles[0], main = tiles[1];
      // Door union x 3200..3600, y 400..1200, padded 12% of its size.
      expect(door.left, closeTo(3200 - 48, 1));
      expect(door.top, closeTo(400 - 96, 1));
      expect(door.width, closeTo(400 + 96, 2));
      expect(door.height, closeTo(800 + 192, 2));
      // Main union x 400..1600, y 400..2000 (under 2048 once padded).
      expect(main.left, closeTo(400 - 144, 1));
      expect(main.top, closeTo(400 - 192, 1));
      expect(main.right, closeTo(1600 + 144, 1));
      expect(main.bottom, closeTo(2000 + 192, 1));
    });

    test('skips a family without boxes and clamps to the photo', () {
      final tiles = planZoneTiles(4000, 4000, [
        item('milk', [0, 0, 1000, 1000], location: 'main'),
        item('jam', null, location: 'door'),
      ]);
      expect(tiles, isNotEmpty);
      expect(tiles.every((t) => t.id.startsWith('main')), isTrue);
      for (final t in tiles) {
        expect(t.left, greaterThanOrEqualTo(0));
        expect(t.right, lessThanOrEqualTo(4000));
        expect(t.bottom, lessThanOrEqualTo(4000));
        expect(math.max(t.width, t.height), lessThanOrEqualTo(2400));
      }
      expectCovers(tiles, 4000, 4000);
    });

    test('falls back to the grid when no item has a box', () {
      final tiles = planZoneTiles(4000, 3000, [item('milk', null)]);
      expect(tiles, planGridTiles(4000, 3000));
      expect(tiles, isNotEmpty);
    });
  });

  group('planZoomCrops', () {
    test('crops guess items only, padded', () {
      final crops = planZoomCrops(
        4000,
        4000,
        [
          item('jar', [100, 100, 200, 200], confidence: ScanConfidence.guess),
          item('milk', [600, 600, 700, 700]),
        ],
        const [],
      );
      expect(crops, hasLength(1));
      // Box 400..800 px, padded 48 px each side.
      expect(crops.single.left, closeTo(352, 1));
      expect(crops.single.top, closeTo(352, 1));
      expect(crops.single.width, closeTo(496, 2));
      expect(crops.single.height, closeTo(496, 2));
    });

    test('crops the union of an under-counted zone', () {
      final crops = planZoomCrops(
        4000,
        4000,
        [
          item('a', [100, 100, 200, 200], location: 'Shelf 1'),
          item('b', [100, 300, 200, 400], location: 'shelf 1'),
          item('c', [800, 100, 900, 200], location: 'shelf 2'),
        ],
        const [
          ScanZone(name: 'SHELF 1', count: 3),
          ScanZone(name: 'shelf 2', count: 1),
        ],
      );
      expect(crops, hasLength(1));
      final c = crops.single;
      // Union x 400..1600, y 400..800; padded 144 / 48.
      expect(c.left, closeTo(256, 1));
      expect(c.top, closeTo(352, 1));
      expect(c.right, closeTo(1744, 1));
      expect(c.bottom, closeTo(848, 1));
    });

    test('merges overlapping crops until stable', () {
      final crops = planZoomCrops(
        4000,
        4000,
        [
          item('a', [100, 100, 200, 200], confidence: ScanConfidence.guess),
          item('b', [150, 190, 250, 290], confidence: ScanConfidence.guess),
          item('c', [200, 280, 300, 380], confidence: ScanConfidence.guess),
        ],
        const [],
      );
      expect(crops, hasLength(1));
      expect(crops.single.left, lessThanOrEqualTo(400));
      expect(crops.single.right, greaterThanOrEqualTo(1520));
    });

    test('keeps only the largest maxCrops', () {
      final guesses = [
        for (var i = 0; i < 8; i++)
          item(
            'g$i',
            [0, i * 120, 50 + i * 10, i * 120 + 50],
            confidence: ScanConfidence.guess,
          ),
      ];
      final crops = planZoomCrops(4000, 4000, guesses, const []);
      expect(crops, hasLength(6));
      // The two shortest (leftmost) boxes are the ones dropped.
      expect(crops.first.left, greaterThan(900));
      expect(planZoomCrops(4000, 4000, guesses, const [], maxCrops: 3), hasLength(3));
    });

    test('grows tiny crops to minSide around the centre, in bounds', () {
      final crops = planZoomCrops(
        4000,
        4000,
        [
          item('a', [500, 500, 502, 502], confidence: ScanConfidence.guess),
          item('b', [0, 0, 2, 2], confidence: ScanConfidence.guess),
        ],
        const [],
      );
      expect(crops, hasLength(2));
      for (final c in crops) {
        expect(c.width, 256);
        expect(c.height, 256);
        expect(c.left, greaterThanOrEqualTo(0));
        expect(c.top, greaterThanOrEqualTo(0));
      }
      final middle = crops.firstWhere((c) => c.left > 0);
      expect(middle.left + 128, closeTo(2004, 2));
    });

    test('never exceeds the photo when it is smaller than minSide', () {
      final crops = planZoomCrops(
        200,
        100,
        [item('a', [0, 0, 500, 500], confidence: ScanConfidence.guess)],
        const [],
      );
      expect(crops.single.width, lessThanOrEqualTo(200));
      expect(crops.single.height, lessThanOrEqualTo(100));
    });
  });

  group('cutTile / encodeTile', () {
    test('cuts at native scale and encodes a JPEG', () {
      final photo = img.Image(width: 400, height: 300);
      const rect = TileRect(id: 't', left: 100, top: 50, width: 200, height: 120);
      final tile = cutTile(photo, rect);
      expect(tile.width, 200);
      expect(tile.height, 120);
      final bytes = encodeTile(tile);
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);
    });
  });

  group('tileBoxToPhoto', () {
    test('maps a tile box into full-photo space', () {
      const tile = TileRect(id: 't', left: 1000, top: 2000, width: 2000, height: 1000);
      expect(
        tileBoxToPhoto([0, 0, 1000, 1000], tile, 4000, 4000),
        [500, 250, 750, 750],
      );
      expect(
        tileBoxToPhoto([500, 500, 600, 600], tile, 4000, 4000),
        [625, 500, 650, 550],
      );
    });

    test('whole-photo tile is the identity', () {
      const tile = TileRect(id: 't', left: 0, top: 0, width: 800, height: 600);
      expect(tileBoxToPhoto([10, 20, 30, 40], tile, 800, 600), [10, 20, 30, 40]);
    });
  });

  test('encodeTile shrinks big tiles to 2048 and leaves small ones alone', () {
    final big = img.Image(width: 3000, height: 1500);
    final small = img.Image(width: 800, height: 600);
    final a = img.decodeJpg(encodeTile(big))!;
    final b = img.decodeJpg(encodeTile(small))!;
    expect([a.width, a.height], [2048, 1024]);
    expect([b.width, b.height], [800, 600]);
  });
}
