import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/fridge/scan/fridge_scan_pipeline.dart';
import 'package:diabetes/fridge/scan/photo_prep.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:diabetes/fridge/scan/tile_planner.dart';
import 'package:diabetes/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

// 3200x2400 is just over 1.5 x 2048, so the planner tiles it (2x2) without
// the cost of encoding 12 MP tiles in every test.
const _bigW = 3200;
const _bigH = 2400;

late final PreparedPhoto _big;
late final PreparedPhoto _small;

PreparedPhoto _makePhoto(int w, int h) {
  final image = img.Image(width: w, height: h);
  final overview = img.Image(width: 64, height: 48);
  return PreparedPhoto(
    original: image,
    overviewJpeg: Uint8List.fromList(img.encodeJpg(overview)),
    originalWidth: w,
    originalHeight: h,
    overviewWidth: 64,
    overviewHeight: 48,
  );
}

Map<String, dynamic> _item(
  String name,
  List<int> box, {
  String conf = 'likely',
  String zone = 'shelf 1',
  int? photoIndex,
}) => {
  'name': name,
  'type': 'Produce',
  'conf': conf,
  'alts': <String>[],
  'zone': zone,
  'box': box,
  'food': true,
  'days': null,
  'photoIndex': ?photoIndex,
};

http.Response _ok(
  List<Map<String, dynamic>> items, {
  List<Map<String, dynamic>> zones = const [],
  double tilt = 0,
  int nonFood = 0,
}) {
  return http.Response(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {
                'text': jsonEncode({
                  'zones': zones,
                  'items': [
                    ...items,
                    for (var i = 0; i < nonFood; i++)
                      {..._item('Vitamins', [0, 0, 10, 10]), 'food': false},
                  ],
                  'tilt': tilt,
                }),
              },
            ],
          },
        },
      ],
      'usageMetadata': {
        'promptTokenCount': 100,
        'candidatesTokenCount': 50,
        'thoughtsTokenCount': 10,
        'totalTokenCount': 160,
      },
    }),
    200,
  );
}

/// The box in [rect]'s own 0-1000 grid for a photo-space [box].
List<int> _local(List<int> box, TileRect rect, int w, int h) {
  int y(int v) => ((v / 1000 * h - rect.top) / rect.height * 1000).round();
  int x(int v) => ((v / 1000 * w - rect.left) / rect.width * 1000).round();
  return [y(box[0]), x(box[1]), y(box[2]), x(box[3])];
}

void _expectNear(List<int>? actual, List<int> expected, {int tolerance = 3}) {
  expect(actual, isNotNull);
  for (var i = 0; i < 4; i++) {
    expect(
      (actual![i] - expected[i]).abs(),
      lessThanOrEqualTo(tolerance),
      reason: 'box $actual vs $expected',
    );
  }
}

Map<String, dynamic> _bodyOf(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

List<Map<String, dynamic>> _partsOf(Map<String, dynamic> body) =>
    (((body['contents'] as List).single as Map)['parts'] as List)
        .cast<Map<String, dynamic>>();

int _imageCount(Map<String, dynamic> body) =>
    _partsOf(body).where((p) => p.containsKey('inlineData')).length;

String _promptOf(Map<String, dynamic> body) =>
    _partsOf(body).last['text'] as String;

bool _isTile(Map<String, dynamic> body) =>
    _promptOf(body).contains(tileContextNote);

bool _isZoom(Map<String, dynamic> body) =>
    _promptOf(body).contains(zoomContextNote);

/// A client that records every request body and answers through [answer],
/// which gets the request's index in arrival order.
class _Recorder {
  _Recorder(FutureOr<http.Response> Function(int index, Map<String, dynamic>) answer)
    : bodies = [] {
    client = MockClient((request) async {
      final body = _bodyOf(request);
      final index = bodies.length;
      bodies.add(body);
      return answer(index, body);
    });
  }

  final List<Map<String, dynamic>> bodies;
  late final MockClient client;
}

Future<PipelineResult> _scan(
  PreparedPhoto photo,
  ScanPlan plan,
  _Recorder recorder, {
  Duration? deadline,
  int maxParallel = 4,
}) => FridgeScanPipeline.scan(
  photo,
  plan: plan,
  client: recorder.client,
  apiKey: 'test-token',
  deadline: deadline,
  maxParallel: maxParallel,
);

void main() {
  setUpAll(() {
    _big = _makePhoto(_bigW, _bigH);
    _small = _makePhoto(1000, 800);
  });

  final gridRects = planGridTiles(_bigW, _bigH);
  const milkBox = [450, 450, 550, 550]; // in the overlap of all four tiles

  group('overviewOnly and small photos', () {
    test('overviewOnly makes one call on the overview', () async {
      final recorder = _Recorder(
        (_, _) => _ok([_item('Milk', [10, 10, 100, 100])], tilt: 4),
      );
      final result = await _scan(_big, ScanPlan.overviewOnly, recorder);

      expect(recorder.bodies, hasLength(1));
      expect(
        _partsOf(recorder.bodies.single).first['inlineData']['data'],
        base64Encode(_big.overviewJpeg),
      );
      expect(_promptOf(recorder.bodies.single), isNot(contains(tileContextNote)));
      expect(result.calls, 1);
      expect(result.callTimings, hasLength(1));
      expect(result.items.single.name, 'Milk');
      expect(result.tiltDegrees, 4);
      expect(result.droppedTiles, isEmpty);
    });

    for (final plan in ScanPlan.values) {
      test('${plan.name} on a small photo falls back to the overview', () async {
        final recorder = _Recorder((_, _) => _ok([_item('Milk', [10, 10, 100, 100])]));
        final result = await _scan(_small, plan, recorder);

        expect(recorder.bodies, hasLength(1));
        expect(_isTile(recorder.bodies.single), isFalse);
        expect(
          _partsOf(recorder.bodies.single).first['inlineData']['data'],
          base64Encode(_small.overviewJpeg),
        );
        expect(result.items.map((i) => i.name), ['Milk']);
      });
    }
  });

  group('grid', () {
    test('sends one tile request per tile', () {
      expect(gridRects, hasLength(4));
    });

    test('maps boxes to the photo and merges the overlap', () async {
      final recorder = _Recorder((index, _) {
        final rect = gridRects[index];
        return _ok([
          _item('Milk', _local(milkBox, rect, _bigW, _bigH)),
          if (index == 0) _item('Eggs', [50, 50, 150, 150]),
        ]);
      });
      final result = await _scan(_big, ScanPlan.grid, recorder);

      expect(recorder.bodies, hasLength(4));
      for (final body in recorder.bodies) {
        expect(_imageCount(body), 1);
        expect(_promptOf(body), contains(tileContextNote));
      }
      expect(result.calls, 4);
      expect(result.callTimings, hasLength(4));
      expect(result.items.map((i) => i.name).toSet(), {'Milk', 'Eggs'});
      expect(result.items, hasLength(2));

      final milk = result.items.firstWhere((i) => i.name == 'Milk');
      _expectNear(milk.box2d, milkBox);
      // Tile 0 starts at the photo's top-left, so only the scale changes.
      final eggs = result.items.firstWhere((i) => i.name == 'Eggs');
      expect(
        eggs.box2d,
        tileBoxToPhoto([50, 50, 150, 150], gridRects[0], _bigW, _bigH),
      );
      expect(result.droppedTiles, isEmpty);
    });

    test('never runs more than maxParallel calls at once', () async {
      var running = 0;
      var peak = 0;
      final recorder = _Recorder((_, _) async {
        running++;
        peak = running > peak ? running : peak;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        running--;
        return _ok([]);
      });
      await _scan(_big, ScanPlan.grid, recorder, maxParallel: 2);

      expect(recorder.bodies, hasLength(4));
      expect(peak, 2);
    });

    test('sums usage and non-food drops across calls', () async {
      final recorder = _Recorder((_, _) => _ok([], nonFood: 1));
      final result = await _scan(_big, ScanPlan.grid, recorder);

      expect(result.usage.promptTokenCount, 400);
      expect(result.usage.candidatesTokenCount, 200);
      expect(result.usage.thoughtsTokenCount, 40);
      expect(result.usage.totalTokenCount, 640);
      expect(result.droppedNonFood, 4);
    });
  });

  group('failures and deadline', () {
    test('one failing tile does not fail the scan', () async {
      final recorder = _Recorder(
        (index, _) => index == 2
            ? http.Response('boom', 500)
            : _ok([_item('Milk $index', [0, 0, 1000, 1000])]),
      );
      final result = await _scan(_big, ScanPlan.grid, recorder);

      expect(result.items, hasLength(3));
      expect(result.droppedTiles, [gridRects[2].id]);
      expect(result.calls, 4);
      expect(result.usage.promptTokenCount, 300);
    });

    test('every call failing rethrows the first error', () async {
      final recorder = _Recorder((_, _) => http.Response('nope', 500));
      await expectLater(
        _scan(_big, ScanPlan.grid, recorder),
        throwsA(isA<AiRequestException>()),
      );
    });

    test('a failed overview in overviewOnly rethrows', () async {
      final recorder = _Recorder((_, _) => http.Response('nope', 500));
      await expectLater(
        _scan(_big, ScanPlan.overviewOnly, recorder),
        throwsA(isA<AiRequestException>()),
      );
    });

    test('the deadline drops a slow tile and keeps the rest', () async {
      final recorder = _Recorder((index, _) async {
        if (index == 0) {
          await Future<void>.delayed(const Duration(seconds: 8));
        }
        return _ok([_item('Milk $index', [0, 0, 1000, 1000])]);
      });
      final watch = Stopwatch()..start();
      final result = await _scan(
        _big,
        ScanPlan.grid,
        recorder,
        deadline: const Duration(seconds: 4),
      );
      watch.stop();

      expect(result.droppedTiles, [gridRects[0].id]);
      expect(result.items, hasLength(3));
      expect(watch.elapsed, lessThan(const Duration(seconds: 7)));
    });

    test('the deadline never drops the overview', () async {
      final recorder = _Recorder((index, body) async {
        if (!_isTile(body)) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          return _ok([_item('Milk', milkBox)]);
        }
        return _ok([]);
      });
      final result = await _scan(
        _big,
        ScanPlan.gridPlusOverview,
        recorder,
        deadline: const Duration(milliseconds: 1),
      );

      expect(result.items.map((i) => i.name), ['Milk']);
      expect(result.droppedTiles, unorderedEquals(gridRects.map((r) => r.id)));
    });
  });

  group('gridPlusOverview', () {
    test('sends the overview and four tiles and merges onto the overview',
        () async {
      var tileIndex = 0;
      final recorder = _Recorder((_, body) {
        if (!_isTile(body)) {
          return _ok(
            [_item('Milk', milkBox, conf: 'sure')],
            zones: [
              {'name': 'shelf 1', 'count': 1},
            ],
            tilt: 3,
          );
        }
        final rect = gridRects[tileIndex++];
        return _ok([
          _item('Milk', _local(milkBox, rect, _bigW, _bigH), conf: 'guess'),
        ]);
      });
      final result = await _scan(_big, ScanPlan.gridPlusOverview, recorder);

      expect(recorder.bodies, hasLength(5));
      expect(recorder.bodies.where(_isTile), hasLength(4));
      expect(result.calls, 5);
      expect(result.items, hasLength(1));
      expect(result.items.single.confidence, ScanConfidence.sure);
      expect(result.tiltDegrees, 3);
      expect(result.zones.single.name, 'shelf 1');
    });
  });

  group('zones', () {
    test('plans tiles from the pass-1 boxes and maps them back', () async {
      final pass1 = [
        _item('Milk', [100, 100, 300, 300], conf: 'sure'),
        _item('Eggs', [600, 500, 800, 900], conf: 'sure', zone: 'shelf 3'),
      ];
      final pass1Items = [
        for (final json in pass1)
          ScannedItem(
            name: json['name'] as String,
            foodType: FoodType.fromLabel('Produce'),
            location: json['zone'] as String,
            box2d: (json['box'] as List).cast<int>(),
          ),
      ];
      final rects = planZoneTiles(_bigW, _bigH, pass1Items);
      expect(rects, isNotEmpty);

      var tileIndex = 0;
      final recorder = _Recorder((_, body) {
        if (!_isTile(body)) return _ok(pass1);
        return _ok([
          _item('Tile${tileIndex++}', [0, 0, 1000, 1000]),
        ]);
      });
      final result = await _scan(_big, ScanPlan.zones, recorder);

      expect(recorder.bodies, hasLength(1 + rects.length));
      expect(_isTile(recorder.bodies.first), isFalse);
      expect(result.calls, 1 + rects.length);
      for (var i = 0; i < rects.length; i++) {
        final tile = result.items.firstWhere((item) => item.name == 'Tile$i');
        expect(
          tile.box2d,
          tileBoxToPhoto([0, 0, 1000, 1000], rects[i], _bigW, _bigH),
        );
      }
      expect(result.items.map((i) => i.name), containsAll(['Milk', 'Eggs']));
    });

    test('keeps the overview result when every tile fails', () async {
      final recorder = _Recorder(
        (_, body) => _isTile(body)
            ? http.Response('nope', 500)
            : _ok([_item('Milk', [100, 100, 300, 300])]),
      );
      final result = await _scan(_big, ScanPlan.zones, recorder);

      expect(result.items.map((i) => i.name), ['Milk']);
      expect(result.droppedTiles, isNotEmpty);
    });
  });

  group('zoom', () {
    test('sends the crops in one call and maps them by photoIndex', () async {
      final base = [
        _item('Jar', [100, 100, 200, 200], conf: 'guess'),
        _item('Bottle', [700, 700, 800, 800], conf: 'guess'),
        _item('Milk', [450, 450, 550, 550], conf: 'sure'),
      ];
      final baseItems = [
        for (final json in base)
          ScannedItem(
            name: json['name'] as String,
            foodType: FoodType.fromLabel('Produce'),
            confidence: ScanConfidence.fromLabel(json['conf']),
            box2d: (json['box'] as List).cast<int>(),
          ),
      ];
      final crops = planZoomCrops(_bigW, _bigH, baseItems, const []);
      expect(crops, hasLength(2));

      final recorder = _Recorder((_, body) {
        if (!_isZoom(body)) return _ok(base);
        return _ok([
          // Crop 0 upgrades the Jar; crop 1 finds something new.
          _item(
            'Jar',
            _local([100, 100, 200, 200], crops[0], _bigW, _bigH),
            conf: 'sure',
            photoIndex: 0,
          ),
          _item('Pickles', [0, 0, 1000, 1000], conf: 'sure', photoIndex: 1),
          _item('Ghost', [0, 0, 1000, 1000], photoIndex: 7),
        ]);
      });
      final result = await _scan(_big, ScanPlan.zoom, recorder);

      expect(recorder.bodies, hasLength(2));
      final zoomBody = recorder.bodies.last;
      expect(_imageCount(zoomBody), 2);
      expect(_promptOf(zoomBody), contains('close-ups'));
      expect(_promptOf(zoomBody), contains('photoIndex'));
      final schema = (zoomBody['generationConfig'] as Map)['responseSchema'];
      final itemProps =
          ((((schema as Map)['properties'] as Map)['items'] as Map)['items']
                  as Map)['properties']
              as Map;
      expect(itemProps, contains('photoIndex'));

      expect(result.calls, 2);
      final names = result.items.map((i) => i.name).toList();
      expect(names, isNot(contains('Ghost')));
      expect(names, hasLength(4));
      expect(
        result.items.firstWhere((i) => i.name == 'Jar').confidence,
        ScanConfidence.sure,
      );
      expect(
        result.items.firstWhere((i) => i.name == 'Pickles').box2d,
        tileBoxToPhoto([0, 0, 1000, 1000], crops[1], _bigW, _bigH),
      );
    });

    test('with nothing doubtful it makes no zoom call', () async {
      final recorder = _Recorder(
        (_, _) => _ok([_item('Milk', [450, 450, 550, 550], conf: 'sure')]),
      );
      final result = await _scan(_big, ScanPlan.zoom, recorder);

      expect(recorder.bodies, hasLength(1));
      expect(result.items.map((i) => i.name), ['Milk']);
    });

    test('a failed zoom call keeps the overview items', () async {
      final recorder = _Recorder(
        (_, body) => _isZoom(body)
            ? http.Response('nope', 500)
            : _ok([_item('Jar', [100, 100, 200, 200], conf: 'guess')]),
      );
      final result = await _scan(_big, ScanPlan.zoom, recorder);

      expect(result.items.single.name, 'Jar');
      expect(result.droppedTiles, ['zoom']);
    });
  });

  group('gridPlusZoom', () {
    test('zooms on a guess from the merged grid', () async {
      var tileIndex = 0;
      final recorder = _Recorder((_, body) {
        if (_isTile(body)) {
          final rect = gridRects[tileIndex++];
          return _ok([
            if (tileIndex == 1)
              _item(
                'Jar',
                _local([100, 100, 200, 200], rect, _bigW, _bigH),
                conf: 'guess',
              ),
          ]);
        }
        return _ok([_item('Jar', [0, 0, 1000, 1000], conf: 'sure', photoIndex: 0)]);
      });
      final result = await _scan(_big, ScanPlan.gridPlusZoom, recorder);

      expect(recorder.bodies, hasLength(5));
      expect(result.calls, 5);
      expect(result.tiltDegrees, 0);
      expect(result.items.where((i) => i.name == 'Jar').length, 1);
      expect(result.items.single.confidence, ScanConfidence.sure);
    });
  });

  group('contextNote and multi-image request', () {
    final jpeg = Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);

    test('the note is put in front of the prompt', () {
      final plain = FridgeScanService.buildPrompt(style: ScanStyle.lean);
      final noted = FridgeScanService.buildPrompt(
        style: ScanStyle.lean,
        contextNote: tileContextNote,
      );

      expect(noted, startsWith(tileContextNote));
      expect(noted, endsWith(plain));
      expect(
        tileContextNote,
        'This image is one part of a larger fridge photo; list only what is '
        'in this part, including items cut off at its edges.',
      );
    });

    test('the default body is the single-image body', () {
      for (final style in ScanStyle.values) {
        final body = FridgeScanService.buildRequestBody(jpeg, style: style);
        final parts = _partsOf(body);

        expect(parts, hasLength(2));
        expect(parts.first['inlineData'], {
          'mimeType': 'image/jpeg',
          'data': base64Encode(jpeg),
        });
        expect(parts.last, {'text': FridgeScanService.buildPrompt(style: style)});
        expect(
          (body['generationConfig'] as Map)['responseSchema'],
          style == ScanStyle.lean
              ? leanScanResponseSchema()
              : scanResponseSchema(),
        );
        expect(
          jsonEncode(body),
          jsonEncode(
            FridgeScanService.buildRequestBody(
              jpeg,
              style: style,
              contextNote: null,
              extraImages: const [],
            ),
          ),
        );
      }
    });

    test('extra images follow the first, before the prompt', () {
      final second = Uint8List.fromList(const [1, 2, 3]);
      final body = FridgeScanService.buildRequestBody(
        jpeg,
        style: ScanStyle.lean,
        contextNote: zoomContextNote,
        extraImages: [second],
      );
      final parts = _partsOf(body);

      expect(parts, hasLength(3));
      expect(parts[1]['inlineData']['data'], base64Encode(second));
      expect(parts.last['text'], startsWith(zoomContextNote));
    });

    test('the lean prompt asks for labels and a generic drink guess', () {
      final prompt = FridgeScanService.buildPrompt(style: ScanStyle.lean);

      expect(prompt, contains('bottles, jars and cartons'));
      expect(prompt, contains('"juice"'));
      expect(
        FridgeScanService.buildPrompt(style: ScanStyle.full),
        isNot(contains('bottles, jars and cartons')),
      );
    });
  });

  group('onProgress', () {
    http.StreamedResponse sse(String text) {
      final events = <String>[];
      for (var i = 0; i < text.length; i += 40) {
        final slice = text.substring(i, i + 40 > text.length ? text.length : i + 40);
        events.add(
          'data: ${jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': slice},
                  ],
                },
              },
            ],
          })}\n\n',
        );
      }
      return http.StreamedResponse(
        Stream.fromIterable([for (final e in events) utf8.encode(e)]),
        200,
      );
    }

    test('counts items and calls across 4 tiles', () async {
      final urls = <Uri>[];
      var next = 0;
      final client = MockClient.streaming((request, _) async {
        urls.add(request.url);
        final index = next++;
        return sse(
          jsonEncode({
            'zones': <Object>[],
            'items': [
              _item('A$index', [100, 100, 200, 200]),
              _item('B$index', [600, 600, 700, 700]),
            ],
            'tilt': 0,
          }),
        );
      });
      final updates = <ScanProgress>[];
      final result = await FridgeScanPipeline.scan(
        _big,
        plan: ScanPlan.grid,
        client: client,
        apiKey: 'test-token',
        onProgress: updates.add,
      );

      expect(urls, hasLength(4));
      expect(urls.every((u) => u.path.endsWith(':streamGenerateContent')), isTrue);
      expect(urls.every((u) => u.queryParameters['alt'] == 'sse'), isTrue);
      expect(result.calls, 4);

      final last = updates.last;
      expect(last.itemsSoFar, 8);
      expect(last.callsDone, 4);
      expect(last.callsTotal, 4);
      expect(last.latestNames, hasLength(3));
      for (var i = 1; i < updates.length; i++) {
        expect(updates[i].itemsSoFar, greaterThanOrEqualTo(updates[i - 1].itemsSoFar));
        expect(updates[i].callsDone, greaterThanOrEqualTo(updates[i - 1].callsDone));
        expect(updates[i].latestNames.length, lessThanOrEqualTo(3));
      }
      expect(updates.first.callsTotal, 4);
      expect(updates.first.itemsSoFar, 0);
    });

    test('without onProgress the plain request is used', () async {
      final recorder = _Recorder((_, _) => _ok([_item('Milk', [10, 10, 100, 100])]));
      await _scan(_small, ScanPlan.grid, recorder);
      expect(recorder.bodies, hasLength(1));
    });
  });

  group('scanPhotos', () {
    // Two small photos told apart by the colour of their overview.
    PreparedPhoto tinted(int shade) {
      final base = _makePhoto(1000, 800);
      final overview = img.Image(width: 64, height: 48)
        ..clear(img.ColorRgb8(shade, shade, shade));
      return PreparedPhoto(
        original: base.original,
        overviewJpeg: Uint8List.fromList(img.encodeJpg(overview)),
        originalWidth: 1000,
        originalHeight: 800,
        overviewWidth: 64,
        overviewHeight: 48,
      );
    }

    final first = tinted(40);
    final second = tinted(200);

    int photoOf(Map<String, dynamic> body) =>
        _partsOf(body).first['inlineData']['data'] ==
            base64Encode(first.overviewJpeg)
        ? 0
        : 1;

    test('merges the same name and zone once, keeps zones apart', () async {
      final recorder = _Recorder((_, body) {
        if (photoOf(body) == 0) {
          return _ok([
            _item('Milk', [10, 10, 100, 100], zone: 'door'),
            _item('Eggs', [200, 200, 300, 300], zone: 'shelf 1'),
          ]);
        }
        return _ok([
          // Different box, same name and zone: the same milk.
          _item('milk', [600, 600, 700, 700], zone: 'door'),
          // Same name in another zone: a second jar.
          _item('Eggs', [200, 200, 300, 300], zone: 'shelf 2'),
          _item('Butter', [400, 400, 500, 500], zone: 'shelf 2'),
        ]);
      });
      final result = await FridgeScanPipeline.scanPhotos(
        [first, second],
        client: recorder.client,
        apiKey: 'test-token',
      );

      expect(recorder.bodies, hasLength(2));
      expect(result.calls, 2);
      expect(result.items.where((i) => i.name.toLowerCase() == 'milk'), hasLength(1));
      expect(result.items.where((i) => i.name == 'Eggs'), hasLength(2));
      expect(result.items, hasLength(4));
      final milk = result.items.firstWhere((i) => i.name.toLowerCase() == 'milk');
      expect(milk.photoIndex, 0);
      final butter = result.items.firstWhere((i) => i.name == 'Butter');
      expect(butter.photoIndex, 1);
    });

    test('runs a grid on a big photo and shares the parallel limit', () async {
      var running = 0;
      var peak = 0;
      final recorder = _Recorder((_, _) async {
        running++;
        peak = running > peak ? running : peak;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        running--;
        return _ok([]);
      });
      final result = await FridgeScanPipeline.scanPhotos(
        [_big, first],
        client: recorder.client,
        apiKey: 'test-token',
        maxParallel: 2,
      );

      // Four tiles of the big photo plus one overview of the small one.
      expect(recorder.bodies, hasLength(5));
      expect(result.calls, 5);
      expect(peak, 2);
    });
  });
}
