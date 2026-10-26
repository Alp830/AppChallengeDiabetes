import 'dart:convert';
import 'dart:typed_data';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/fridge/scan/fridge_scan_service.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:diabetes/fridge/scan/scan_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _item(String name, {bool food = true, String? zone}) => {
  'name': name,
  'type': 'Produce',
  'conf': 'sure',
  'alts': <String>[],
  'zone': zone ?? 'shelf 1',
  'box': [10, 20, 30, 40],
  'food': food,
  'days': 5,
};

final _items = [
  _item('Milk "2%" {organic}'),
  _item('Vitamins', food: false),
  _item('Eggs', zone: r'back\slash [x]'),
  _item('Unknown'),
  _item('Apples'),
];

final _json = jsonEncode({
  'zones': [
    {'name': 'shelf 1', 'count': 5},
  ],
  'items': _items,
  'tilt': 2.5,
});

/// [text] cut into slices of [size] characters.
List<String> _slices(String text, int size) => [
  for (var i = 0; i < text.length; i += size)
    text.substring(i, i + size > text.length ? text.length : i + size),
];

String _event(Map<String, dynamic> data) => 'data: ${jsonEncode(data)}\n\n';

Map<String, dynamic> _chunk(
  String text, {
  Map<String, dynamic>? usage,
  String? finishReason,
}) => {
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': text},
        ],
      },
      'finishReason': ?finishReason,
    },
  ],
  'usageMetadata': ?usage,
};

Stream<List<int>> _body(List<String> events) =>
    Stream.fromIterable([for (final e in events) utf8.encode(e)]);

List<String> _sseOf(String text, int size, {Map<String, dynamic>? usage}) {
  final slices = _slices(text, size);
  return [
    for (var i = 0; i < slices.length; i++)
      _event(
        _chunk(
          slices[i],
          usage: i == slices.length - 1 ? usage : null,
          finishReason: i == slices.length - 1 ? 'STOP' : null,
        ),
      ),
  ];
}

const _usage = {
  'promptTokenCount': 100,
  'candidatesTokenCount': 50,
  'thoughtsTokenCount': 10,
  'totalTokenCount': 160,
};

void main() {
  group('ScanItemScanner', () {
    test('finds every item for any slice size, in order', () {
      for (final size in [1, 2, 3, 5, 7, 11, 64, _json.length]) {
        final scanner = ScanItemScanner();
        final names = [
          for (final slice in _slices(_json, size))
            for (final item in scanner.add(slice)) item['name'],
        ];
        expect(names, [for (final item in _items) item['name']], reason: '$size');
      }
    });

    test('emits an item before the rest of the reply has arrived', () {
      final scanner = ScanItemScanner();
      final cut = _json.indexOf('Vitamins');
      final early = scanner.add(_json.substring(0, cut));
      expect(early.map((i) => i['name']), ['Milk "2%" {organic}']);
      expect(scanner.add(_json.substring(cut)), hasLength(4));
    });

    test('does not emit a half-written object', () {
      final scanner = ScanItemScanner();
      expect(scanner.add('{"items": [{"name": "Mi'), isEmpty);
      expect(scanner.add('lk"}, {"name": "Egg'), hasLength(1));
    });

    test('ignores braces, brackets and quotes inside strings', () {
      final scanner = ScanItemScanner();
      final found = scanner.add(
        r'{"items": [{"name": "a } ] \" {"}, {"name": "b\\"}]}',
      );
      expect(found.map((i) => i['name']), [r'a } ] " {', r'b\']);
    });

    test('ignores arrays under other keys and nested arrays in items', () {
      final scanner = ScanItemScanner();
      final found = scanner.add(
        '{"zones": [{"name": "z", "count": 1}], "items": '
        '[{"name": "x", "box": [1, 2, 3, 4], "alts": ["y"]}], '
        '"other": [{"name": "no"}]}',
      );
      expect(found.map((i) => i['name']), ['x']);
    });

    test('reads a bare array and skips a Markdown fence', () {
      final scanner = ScanItemScanner();
      final found = [
        ...scanner.add('```json\n[{"name": "a"}, '),
        ...scanner.add('{"name": "b"}]\n```'),
      ];
      expect(found.map((i) => i['name']), ['a', 'b']);
    });

    test('items written before a later "items" key do not confuse it', () {
      final scanner = ScanItemScanner();
      final found = scanner.add(
        '{"note": "items", "tilt": 0, "items": [{"name": "a"}]}',
      );
      expect(found.map((i) => i['name']), ['a']);
    });
  });

  group('readScanStream', () {
    test('emits kept items in order; the response equals the plain parse',
        () async {
      for (final size in [1, 3, 9, 50, 1000]) {
        final emitted = <String>[];
        final response = await FridgeScanService.readScanStream(
          _body(_sseOf(_json, size, usage: _usage)),
          style: ScanStyle.lean,
          onItem: (item) => emitted.add(item.name),
        );
        final plain = FridgeScanService.parseScanResponse(
          jsonDecode(_json),
          style: ScanStyle.lean,
        );

        // Vitamins (food: false) and Unknown (placeholder) never show up.
        expect(emitted, ['Milk "2%" {organic}', 'Eggs', 'Apples'], reason: '$size');
        expect(response.items.map((i) => i.name), plain.items.map((i) => i.name));
        expect(response.items[1].location, r'back\slash [x]');
        expect(response.droppedNonFood, 1);
        expect(response.droppedNonFood, plain.droppedNonFood);
        expect(response.tiltDegrees, 2.5);
        expect(response.zones.single.count, 5);
      }
    });

    test('splits inside a UTF-8 character and an event line', () async {
      const text = '{"items": [{"name": "Crème fraîche 🥛"}]}';
      final bytes = utf8.encode(_event(_chunk(text)));
      final cut = bytes.indexOf(0xC3) + 1; // between the bytes of "è"
      final emitted = <String>[];
      final response = await FridgeScanService.readScanStream(
        Stream.fromIterable([bytes.sublist(0, cut), bytes.sublist(cut)]),
        style: ScanStyle.lean,
        onItem: (item) => emitted.add(item.name),
      );
      expect(emitted, ['Crème fraîche 🥛']);
      expect(response.items.single.name, 'Crème fraîche 🥛');
    });

    test('usage comes from the last chunk that has it', () async {
      final events = [
        _event(_chunk(_json.substring(0, 20), usage: {'promptTokenCount': 1})),
        _event(
          _chunk(
            _json.substring(20),
            usage: _usage,
            finishReason: 'STOP',
          ),
        ),
      ];
      final response = await FridgeScanService.readScanStream(
        _body(events),
        style: ScanStyle.lean,
      );
      expect(response.usage.promptTokenCount, 100);
      expect(response.usage.candidatesTokenCount, 50);
      expect(response.usage.totalTokenCount, 160);
    });

    test('thought parts are not part of the JSON', () async {
      final events = [
        _event({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'thinking about {fridges', 'thought': true},
                ],
              },
            },
          ],
        }),
        ..._sseOf(_json, 40),
      ];
      final response = await FridgeScanService.readScanStream(
        _body(events),
        style: ScanStyle.lean,
      );
      expect(response.items, hasLength(3));
    });

    test('truncated JSON is a retryable FormatException', () async {
      final emitted = <String>[];
      final future = FridgeScanService.readScanStream(
        _body(_sseOf(_json.substring(0, _json.length - 30), 25)),
        style: ScanStyle.lean,
        onItem: (item) => emitted.add(item.name),
      );
      await expectLater(future, throwsFormatException);
      expect(isRetryableAiError(const FormatException()), isTrue);
    });

    test('an empty reply is a FormatException', () async {
      await expectLater(
        FridgeScanService.readScanStream(_body([])),
        throwsFormatException,
      );
    });

    test('a promptFeedback block is not retryable', () async {
      final events = [
        _event({
          'promptFeedback': {'blockReason': 'PROHIBITED_CONTENT'},
        }),
      ];
      await expectLater(
        FridgeScanService.readScanStream(_body(events)),
        throwsA(
          isA<AiRequestException>()
              .having((e) => e.retryable, 'retryable', isFalse)
              .having((e) => e.message, 'message', contains('PROHIBITED')),
        ),
      );
    });

    test('a refusal finishReason is not retryable', () async {
      final events = [
        ..._sseOf(_json.substring(0, 30), 30),
        _event({
          'candidates': [
            {'finishReason': 'IMAGE_SAFETY'},
          ],
        }),
      ];
      await expectLater(
        FridgeScanService.readScanStream(_body(events)),
        throwsA(
          isA<AiRequestException>().having(
            (e) => e.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
    });
  });

  group('scanV2Stream', () {
    final photo = Uint8List.fromList([1, 2, 3]);

    test('posts the v2 body to streamGenerateContent?alt=sse', () async {
      late http.BaseRequest seen;
      late Map<String, dynamic> body;
      final client = MockClient.streaming((request, bodyStream) async {
        seen = request;
        body =
            jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
        return http.StreamedResponse(_body(_sseOf(_json, 30)), 200);
      });
      final emitted = <String>[];
      final response = await FridgeScanService.scanV2Stream(
        photo,
        client: client,
        apiKey: 'k',
        style: ScanStyle.lean,
        onItem: (item) => emitted.add(item.name),
      );

      expect(seen.url.path, endsWith(':streamGenerateContent'));
      expect(seen.url.queryParameters['alt'], 'sse');
      expect(
        body,
        FridgeScanService.buildRequestBody(photo, style: ScanStyle.lean),
      );
      expect(emitted, hasLength(3));
      expect(response.items, hasLength(3));
    });

    test('an HTTP error status maps like scanV2', () async {
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(utf8.encode('busy')),
          503,
        ),
      );
      await expectLater(
        FridgeScanService.scanV2Stream(photo, client: client, apiKey: 'k'),
        throwsA(
          isA<AiRequestException>()
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );

      final bad = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.value(utf8.encode('bad image')),
          400,
        ),
      );
      await expectLater(
        FridgeScanService.scanV2Stream(photo, client: bad, apiKey: 'k'),
        throwsA(
          isA<AiRequestException>().having(
            (e) => e.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
    });

    test('a missing key is not retryable', () async {
      await expectLater(
        FridgeScanService.scanV2Stream(photo, apiKey: ''),
        throwsA(
          isA<AiRequestException>().having(
            (e) => e.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
    });
  });
}
