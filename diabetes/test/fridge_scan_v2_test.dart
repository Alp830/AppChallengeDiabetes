import 'dart:convert';
import 'dart:typed_data';

import 'package:diabetes/ai/ai_retry.dart';
import 'package:diabetes/fridge/scan/scan_models.dart';
import 'package:diabetes/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _jpeg = Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);

/// Wraps a v2 payload in Gemini's `generateContent` response envelope.
http.Response _geminiResponse(Object payload) {
  return http.Response(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(payload)},
            ],
          },
        },
      ],
      'usageMetadata': {'promptTokenCount': 1500, 'totalTokenCount': 2000},
    }),
    200,
  );
}

Future<ScanResponse> _scan(Object payload) => FridgeScanService.scanV2(
  _jpeg,
  client: MockClient((_) async => _geminiResponse(payload)),
  apiKey: 'test-token',
);

void main() {
  group('scanV2 request', () {
    late http.Request captured;
    Future<Map<String, dynamic>> send({
      bool perPartUltraHigh = false,
      String thinkingLevel = 'low',
    }) async {
      await FridgeScanService.scanV2(
        _jpeg,
        client: MockClient((request) async {
          captured = request;
          return _geminiResponse({'zones': [], 'items': [], 'tiltDegrees': 0});
        }),
        apiKey: 'test-token',
        perPartUltraHigh: perPartUltraHigh,
        thinkingLevel: thinkingLevel,
      );
      return jsonDecode(captured.body) as Map<String, dynamic>;
    }

    test('uses the same model, endpoint and key header as v1', () async {
      await send();

      expect(captured.url.toString(), FridgePhotoFoodAgent.endpoint);
      expect(captured.headers['x-goog-api-key'], 'test-token');
    });

    test('prompt no longer tells the model to omit uncertain items', () async {
      final body = await send();
      final parts = (body['contents'] as List).single['parts'] as List;
      final prompt = (parts.last as Map)['text'] as String;

      expect(prompt, isNot(contains('OMIT')));
      expect(prompt, contains('"guess"'));
      expect(prompt, contains('zone by zone'));
      expect(prompt, contains('tomato stew'));
      expect(prompt, contains('tiltDegrees'));
    });

    test('schema has confidence, alternatives, box_2d, isFood and tilt',
        () async {
      final body = await send();
      final schema =
          (body['generationConfig'] as Map)['responseSchema'] as Map;
      final top = schema['properties'] as Map;
      final item = (top['items'] as Map)['items'] as Map;
      final props = item['properties'] as Map;

      expect(top.keys, containsAll(['zones', 'items', 'tiltDegrees']));
      expect(
        props.keys,
        containsAll([
          'confidence',
          'alternatives',
          'box_2d',
          'isFood',
          'location',
          'photoIndex',
          'expiryEstimateDays',
        ]),
      );
      expect((props['confidence'] as Map)['enum'], [
        'sure',
        'likely',
        'guess',
      ]);
      expect((props['foodType'] as Map)['enum'], contains('Produce'));
    });

    test('default body: global HIGH resolution, low thinking, camelCase part',
        () async {
      final body = await send();
      final config = body['generationConfig'] as Map;
      final part =
          ((body['contents'] as List).single['parts'] as List).first as Map;

      expect(config['mediaResolution'], 'MEDIA_RESOLUTION_HIGH');
      expect(config['thinkingConfig'], {'thinkingLevel': 'low'});
      expect(config.containsKey('temperature'), isFalse);
      expect(part['inlineData'], {
        'mimeType': 'image/jpeg',
        'data': base64Encode(_jpeg),
      });
      expect(part.containsKey('mediaResolution'), isFalse);
    });

    test('per-part ULTRA_HIGH sits on the image part, not in the config',
        () async {
      final body = await send(perPartUltraHigh: true);
      final config = body['generationConfig'] as Map;
      final part =
          ((body['contents'] as List).single['parts'] as List).first as Map;

      expect(part['mediaResolution'], {'level': 'MEDIA_RESOLUTION_ULTRA_HIGH'});
      expect(config.containsKey('mediaResolution'), isFalse);
    });

    test('thinking level is passed through', () async {
      final body = await send(thinkingLevel: 'medium');

      expect(
        (body['generationConfig'] as Map)['thinkingConfig'],
        {'thinkingLevel': 'medium'},
      );
    });
  });

  group('scanV2 parsing', () {
    test('keeps guess items with their alternatives and metadata', () async {
      final response = await _scan({
        'zones': [
          {'name': 'shelf 1', 'count': 2},
        ],
        'items': [
          {
            'name': 'Tomato stew',
            'amount': '1 dish',
            'foodType': 'Protein',
            'confidence': 'guess',
            'alternatives': ['Red pepper sauce', 'Ratatouille'],
            'location': 'shelf 1',
            'box_2d': [100, 200, 300, 400],
            'photoIndex': 0,
            'isFood': true,
            'description': '',
            'expiryEstimateDays': 3,
          },
          {'name': 'Milk', 'foodType': 'Dairy', 'confidence': 'sure'},
        ],
        'tiltDegrees': -4.5,
      });

      expect(response.zones.single.name, 'shelf 1');
      expect(response.zones.single.count, 2);
      expect(response.tiltDegrees, -4.5);
      expect(response.droppedNonFood, 0);
      expect(response.usage.promptTokenCount, 1500);
      expect(response.items, hasLength(2));

      final stew = response.items.first;
      expect(stew.name, 'Tomato stew');
      expect(stew.confidence, ScanConfidence.guess);
      expect(stew.alternatives, ['Red pepper sauce', 'Ratatouille']);
      expect(stew.location, 'shelf 1');
      expect(stew.box2d, [100, 200, 300, 400]);
      expect(stew.toFoodItem().expiryDate, isNotNull);

      // Optional fields missing: defaults, not a crash.
      final milk = response.items.last;
      expect(milk.alternatives, isEmpty);
      expect(milk.box2d, isNull);
      expect(milk.photoIndex, 0);
      expect(milk.isFood, isTrue);
      expect(milk.toFoodItem().amount, '1 Milk');
      expect(milk.toFoodItem().expiryDate, isNull);
    });

    test('drops isFood:false items and counts them', () async {
      final response = await _scan({
        'zones': [],
        'items': [
          {'name': 'Vitamin D', 'foodType': 'Other', 'isFood': false},
          {'name': 'Basil plant', 'foodType': 'Produce', 'isFood': false},
          {'name': 'Eggs', 'foodType': 'Protein', 'isFood': true},
        ],
        'tiltDegrees': 0,
      });

      expect(response.items.map((item) => item.name), ['Eggs']);
      expect(response.droppedNonFood, 2);
    });

    test('drops placeholder and empty names', () async {
      final response = await _scan({
        'zones': [],
        'items': [
          {'name': 'Unknown', 'foodType': 'Other'},
          {'name': 'Unidentified jar', 'foodType': 'Other'},
          {'name': '  ', 'foodType': 'Other'},
          {'name': 'Butter', 'foodType': 'Dairy'},
        ],
        'tiltDegrees': 0,
      });

      expect(response.items.map((item) => item.name), ['Butter']);
      expect(response.droppedNonFood, 0);
    });

    test('clamps alternatives to two and boxes to 0-1000', () async {
      final response = await _scan({
        'zones': [],
        'items': [
          {
            'name': 'Jam',
            'foodType': 'Other',
            'confidence': 'guess',
            'alternatives': ['Honey', 'Syrup', 'Marmalade', 'Chutney'],
            'box_2d': [-20, 50, 1200, 990],
          },
          {
            'name': 'Cheese',
            'foodType': 'Dairy',
            'box_2d': [500, 600, 100, 200],
          },
          {
            'name': 'Olives',
            'foodType': 'Produce',
            'box_2d': [1, 2, 3],
          },
        ],
        'tiltDegrees': 0,
      });

      expect(response.items[0].alternatives, ['Honey', 'Syrup']);
      expect(response.items[0].box2d, [0, 50, 1000, 990]);
      // Reversed corners are put in min/max order.
      expect(response.items[1].box2d, [100, 200, 500, 600]);
      // Not four numbers: no box rather than a wrong one.
      expect(response.items[2].box2d, isNull);
    });

    test('accepts a bare item list and defaults tilt to 0', () async {
      final response = await _scan([
        {'name': 'Apples', 'foodType': 'Produce'},
      ]);

      expect(response.items.single.name, 'Apples');
      expect(response.zones, isEmpty);
      expect(response.tiltDegrees, 0);
    });
  });

  group('scanV2 errors', () {
    test('a blocked prompt is not retryable', () async {
      final blocked = http.Response(
        jsonEncode({
          'promptFeedback': {'blockReason': 'SAFETY'},
        }),
        200,
      );

      await expectLater(
        FridgeScanService.scanV2(
          _jpeg,
          client: MockClient((_) async => blocked),
          apiKey: 'test-token',
        ),
        throwsA(
          isA<AiRequestException>().having(
            (error) => error.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
    });

    test('no candidates is a FormatException', () async {
      await expectLater(
        FridgeScanService.scanV2(
          _jpeg,
          client: MockClient(
            (_) async => http.Response(jsonEncode({'candidates': []}), 200),
          ),
          apiKey: 'test-token',
        ),
        throwsFormatException,
      );
    });

    test('a missing key is not retryable', () async {
      await expectLater(
        FridgeScanService.scanV2(_jpeg, apiKey: ''),
        throwsA(
          isA<AiRequestException>().having(
            (error) => error.retryable,
            'retryable',
            isFalse,
          ),
        ),
      );
    });

    for (final reason in [
      'SAFETY',
      'BLOCKLIST',
      'PROHIBITED_CONTENT',
      'SPII',
      'IMAGE_SAFETY',
    ]) {
      test('a $reason candidate refusal is not retryable', () async {
        final refused = http.Response(
          jsonEncode({
            'candidates': [
              {'finishReason': reason},
            ],
          }),
          200,
        );
        await expectLater(
          FridgeScanService.scanV2(
            _jpeg,
            client: MockClient((_) async => refused),
            apiKey: 'test-token',
          ),
          throwsA(
            isA<AiRequestException>().having(
              (error) => error.retryable,
              'retryable',
              isFalse,
            ),
          ),
        );
      });
    }
  });
}
