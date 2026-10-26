import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../ai/ai_retry.dart';
// FoodItem, FoodType and AppEnvironment still live in main.dart. main.dart
// re-exports this file, so the import is circular, which Dart allows.
import '../../main.dart';
import 'scan_models.dart';

/// Gemini `usageMetadata` token counts for one scan call. Missing fields are 0.
class FridgeScanUsage {
  const FridgeScanUsage({
    this.promptTokenCount = 0,
    this.candidatesTokenCount = 0,
    this.thoughtsTokenCount = 0,
    this.totalTokenCount = 0,
  });

  factory FridgeScanUsage.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const FridgeScanUsage();
    int count(String key) {
      final value = json[key];
      return value is num ? value.toInt() : 0;
    }

    return FridgeScanUsage(
      promptTokenCount: count('promptTokenCount'),
      candidatesTokenCount: count('candidatesTokenCount'),
      thoughtsTokenCount: count('thoughtsTokenCount'),
      totalTokenCount: count('totalTokenCount'),
    );
  }

  final int promptTokenCount;
  final int candidatesTokenCount;
  final int thoughtsTokenCount;
  final int totalTokenCount;
}

/// The items a scan found plus what the call cost in tokens.
class FoodScanReading {
  const FoodScanReading({required this.items, required this.usage});

  final List<FoodItem> items;
  final FridgeScanUsage usage;
}

class FridgePhotoFoodAgent {
  static String get _apiKey => AppEnvironment.geminiApiKey;

  /// Gemini 4 Argon at thinking level low. It replaced gemini-3.1-pro-preview
  /// (thinking high): it is a stable release instead of a preview, and on
  /// Roboflow's real-world OCR eval Argon low scored 85.7% in 7.7 s at
  /// ~$0.005 a sample against Pro high's 73.1% in 18.6 s at ~$0.026. That eval
  /// reads labels; it doesn't test unlabelled foods, so check new prompts
  /// against the dried linden flowers photo that flash-tier models once
  /// called "bread". Argon has no free tier, and its price doubles on
  /// Dec 1, 2026 ($4 / $20 per 1M tokens). If it fails that photo, go back to
  /// 'gemini-3.1-pro-preview' with thinkingLevel low.
  static const model = 'gemini-4-argon';
  static const endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  /// [abortTrigger] stops the request when the retry loop gives up on this
  /// attempt (see `runWithAbortableAiRetry`).
  static Future<List<FoodItem>> detectFoods(
    Uint8List imageBytes, {
    http.Client? client,
    String? apiKey,
    Future<void>? abortTrigger,
  }) async {
    final result = await detectFoodsWithUsage(
      imageBytes,
      client: client,
      apiKey: apiKey,
      abortTrigger: abortTrigger,
    );
    return result.items;
  }

  /// Same scan as [detectFoods], also returning Gemini's token counts.
  static Future<FoodScanReading> detectFoodsWithUsage(
    Uint8List imageBytes, {
    http.Client? client,
    String? apiKey,
    Future<void>? abortTrigger,
  }) async {
    final token = apiKey ?? _apiKey;
    if (token.isEmpty) {
      throw const AiRequestException(
        'Missing GEMINI_API_KEY',
        retryable: false,
      );
    }

    final request =
        http.AbortableRequest(
            'POST',
            Uri.parse(endpoint),
            abortTrigger: abortTrigger,
          )
          ..headers.addAll({
            'Content-Type': 'application/json',
            'x-goog-api-key': token,
          })
          ..body = jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    'inline_data': {
                      'mime_type': 'image/jpeg',
                      'data': base64Encode(imageBytes),
                    },
                  },
                  {'text': _buildPrompt()},
                ],
              },
            ],
            // No temperature: Argon ignores sampling parameters.
            'generationConfig': {
              // 1120 image tokens, the default and what Google recommends for
              // image analysis: fine texture (rice grains vs flour powder) and
              // small label text stay visible.
              'mediaResolution': 'MEDIA_RESOLUTION_HIGH',
              // Thinking is billed as output and is most of a scan's time and
              // cost. Low is enough for reading labels.
              'thinkingConfig': {'thinkingLevel': 'low'},
              // A ceiling, not a target: only generated tokens are billed. Google
              // asks for at least 32K on Argon, which may spend more of the
              // limit thinking than older models did, and a cut-off JSON array
              // would cost a whole retry.
              'maxOutputTokens': 32768,
              // Force a clean, schema-validated JSON array on the way back.
              'responseMimeType': 'application/json',
              'responseSchema': _responseSchema,
            },
          });

    // A client made here is closed here, so a scan doesn't leave a
    // connection pool open behind it.
    final httpClient = client ?? http.Client();
    final http.Response response;
    try {
      response = await http.Response.fromStream(await httpClient.send(request));
    } finally {
      if (client == null) httpClient.close();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestException.fromStatus(response.statusCode, response.body);
    }

    // Everything below is either "the model gave us nothing usable" (a
    // FormatException, worth another attempt) or a refusal (never worth one).
    // A TypeError from an unexpected shape is mapped to FormatException too,
    // so the retry rule never sees a raw cast failure.
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final blockReason = _blockReason(data);
      if (blockReason != null) {
        throw AiRequestException(
          'Gemini food scan was blocked: $blockReason',
          retryable: false,
        );
      }
      final candidates = data['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) {
        throw const FormatException('Gemini food scan returned no candidates');
      }
      final first = candidates.first as Map<String, dynamic>;
      if (first['finishReason'] == 'SAFETY') {
        throw const AiRequestException(
          'Gemini food scan was blocked: SAFETY',
          retryable: false,
        );
      }
      final content = first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? const [];
      if (parts.isEmpty) {
        throw const FormatException('Gemini food scan returned no content');
      }
      final text = (parts.first as Map<String, dynamic>)['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('Gemini food scan returned no text');
      }

      final decodedJson = jsonDecode(_stripJsonFence(text));
      final foodJson = decodedJson is List<dynamic>
          ? decodedJson
          : (decodedJson as Map<String, dynamic>)['foods'] as List<dynamic>? ??
                const [];

      final items = foodJson
          .whereType<Map<String, dynamic>>()
          .map(_foodItemFromJson)
          .where(
            (foodItem) =>
                foodItem.name.isNotEmpty && !_isPlaceholderName(foodItem.name),
          )
          .toList();
      return FoodScanReading(
        items: items,
        usage: FridgeScanUsage.fromJson(data['usageMetadata']),
      );
    } on TypeError catch (error) {
      throw FormatException('Gemini food scan returned an odd shape: $error');
    }
  }

  /// `promptFeedback.blockReason` means the photo or prompt was refused, so
  /// sending the very same bytes again would be refused the same way.
  static String? _blockReason(Map<String, dynamic> data) {
    final feedback = data['promptFeedback'];
    if (feedback is! Map<String, dynamic>) return null;
    final reason = feedback['blockReason'];
    return reason is String && reason.isNotEmpty ? reason : null;
  }

  /// The prompt forbids placeholder items, but guard in code too so an
  /// "Unknown" entry can never reach the fridge UI.
  static bool _isPlaceholderName(String name) {
    final normalized = name.toLowerCase().trim();
    const placeholders = {
      'unknown',
      'unknown item',
      'unknown food',
      'unidentified',
      'unidentified item',
      'unclear',
      'not sure',
      'n/a',
      'none',
    };
    return placeholders.contains(normalized) ||
        normalized.startsWith('unknown ') ||
        normalized.startsWith('unidentified ');
  }

  /// Structured-output schema so Gemini returns a strict JSON array of items,
  /// each with a valid [FoodType] label.
  static Map<String, dynamic> get _responseSchema => {
    'type': 'ARRAY',
    'items': {
      'type': 'OBJECT',
      'properties': {
        'name': {'type': 'STRING'},
        'amount': {'type': 'STRING'},
        'foodType': {
          'type': 'STRING',
          'enum': [for (final foodType in FoodType.values) foodType.label],
        },
        'description': {'type': 'STRING'},
        'expiryEstimateDays': {'type': 'INTEGER', 'nullable': true},
      },
      'required': ['name', 'amount', 'foodType'],
    },
  };

  static FoodItem _foodItemFromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    final amount = (json['amount'] ?? '').toString().trim();
    final type = (json['foodType'] ?? '').toString().trim();

    return FoodItem(
      name: name,
      amount: amount.isEmpty ? '1 $name' : amount,
      foodType: FoodType.fromLabel(type),
      description: (json['description'] ?? '').toString().trim().isEmpty
          ? null
          : (json['description'] ?? '').toString().trim(),
      expiryDate: _expiryFromEstimate(json['expiryEstimateDays']),
    );
  }

  /// Maps an estimated fridge shelf-life (in days from today) to a concrete
  /// expiry date. Tolerates ints, numeric strings, and missing/invalid values
  /// (which yield null, keeping older prompts backward compatible).
  static DateTime? _expiryFromEstimate(Object? value) {
    if (value == null) {
      return null;
    }
    final days = value is num ? value.toInt() : int.tryParse(value.toString());
    if (days == null || days < 0) {
      return null;
    }
    return DateTime.now().add(Duration(days: days));
  }

  static String _buildPrompt() {
    final foodTypes = FoodType.values
        .map((foodType) => foodType.label)
        .join(', ');

    return '''
You are a fridge inventory assistant. Inspect the entire image and identify every visible food and drink item.

Include only items you can identify with reasonable confidence. Do not include shelves, containers whose contents are unknown, or uncertain guesses. Combine repeated identical items into one entry.

Identification rules:
- Systematically examine every bag, jar, box, and container — including partially visible, opaque, or nested ones (a bag inside a bag) and items at the edges of the image.
- Consider the full range of foods, including dried herbs and herbal teas (e.g. linden/ihlamur, chamomile, mint), spices, and regional or international items. Do not default to a common lookalike food (e.g. never call dried flowers or herbs "bread").
- For packaged or labeled items, READ any visible text on the packaging and identify the product from its label rather than its shape or color.
- For unlabeled bags of dry staples, identify by texture and by what is common in a home pantry: fine matte white powder = flour; crystalline white = sugar or salt; small oblong translucent grains = rice; golden cracked grains = bulgur; round dried seeds = beans, chickpeas, or lentils; also consider pasta, semolina, and oats.
- If you cannot identify an item with reasonable confidence, OMIT it entirely. Never output "Unknown", "Unidentified", or any placeholder name.

Use count-based amounts as the primary measurement style. Examples:
- 3 bananas
- 2 apples
- 1 milk carton
- 1 bag of spinach
- 6 eggs

Use one of these foodType values:
$foodTypes

For each item, estimate "expiryEstimateDays": the typical number of days from
today until it spoils in a fridge (a whole number). Use null if you cannot
reasonably estimate it.

Return only valid JSON as an array, with no Markdown or explanation. Each object must use this exact shape:
[
  {
    "name": "Bananas",
    "amount": "3 bananas",
    "foodType": "Produce",
    "description": "optional short detail, or empty string",
    "expiryEstimateDays": 5
  }
]
''';
  }

  static String _stripJsonFence(String text) {
    return text
        .trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'^```\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }
}

/// Scan v2. Unlike [FridgePhotoFoodAgent], which silently omits anything it is
/// unsure of, v2 lists every food it sees with a confidence, the zone it sits
/// in and a box, so later steps can zoom in on the doubtful ones.
///
/// Shares the model, endpoint and the v1 parsing helpers (same library, so the
/// private ones are reachable) with [FridgePhotoFoodAgent].
class FridgeScanService {
  /// Candidate finish reasons that mean Gemini refused; retrying the same
  /// photo gets the same refusal.
  static const _refusalReasons = {
    'SAFETY',
    'BLOCKLIST',
    'PROHIBITED_CONTENT',
    'SPII',
    'IMAGE_SAFETY',
  };

  static const _ultraHigh = 'MEDIA_RESOLUTION_ULTRA_HIGH';

  /// [overviewJpeg] is the downscaled photo from `preparePhoto`, never the full
  /// original. [abortTrigger] stops the request when the retry loop gives up on
  /// this attempt.
  ///
  /// [perPartUltraHigh] sets the resolution on the image part alone (ULTRA_HIGH
  /// is only accepted per part) and leaves the global [mediaResolution] out.
  static Future<ScanResponse> scanV2(
    Uint8List overviewJpeg, {
    http.Client? client,
    String? apiKey,
    Future<void>? abortTrigger,
    String mediaResolution = 'MEDIA_RESOLUTION_HIGH',
    bool perPartUltraHigh = false,
    String thinkingLevel = 'low',
    ScanStyle style = ScanStyle.full,
  }) async {
    final token = apiKey ?? FridgePhotoFoodAgent._apiKey;
    if (token.isEmpty) {
      throw const AiRequestException(
        'Missing GEMINI_API_KEY',
        retryable: false,
      );
    }

    final request =
        http.AbortableRequest(
            'POST',
            Uri.parse(FridgePhotoFoodAgent.endpoint),
            abortTrigger: abortTrigger,
          )
          ..headers.addAll({
            'Content-Type': 'application/json',
            'x-goog-api-key': token,
          })
          ..body = jsonEncode(
            buildRequestBody(
              overviewJpeg,
              mediaResolution: mediaResolution,
              perPartUltraHigh: perPartUltraHigh,
              thinkingLevel: thinkingLevel,
              style: style,
            ),
          );

    final httpClient = client ?? http.Client();
    final http.Response response;
    try {
      response = await http.Response.fromStream(await httpClient.send(request));
    } finally {
      if (client == null) httpClient.close();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestException.fromStatus(response.statusCode, response.body);
    }

    // Same contract as v1: nothing usable is a FormatException (worth a retry),
    // a refusal is never retried.
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final blockReason = FridgePhotoFoodAgent._blockReason(data);
      if (blockReason != null) {
        throw AiRequestException(
          'Gemini food scan was blocked: $blockReason',
          retryable: false,
        );
      }
      final candidates = data['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) {
        throw const FormatException('Gemini food scan returned no candidates');
      }
      final first = candidates.first as Map<String, dynamic>;
      final finishReason = first['finishReason'];
      if (_refusalReasons.contains(finishReason)) {
        throw AiRequestException(
          'Gemini food scan was blocked: $finishReason',
          retryable: false,
        );
      }
      final content = first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? const [];
      if (parts.isEmpty) {
        throw const FormatException('Gemini food scan returned no content');
      }
      final text = (parts.first as Map<String, dynamic>)['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('Gemini food scan returned no text');
      }

      return parseScanResponse(
        jsonDecode(FridgePhotoFoodAgent._stripJsonFence(text)),
        usage: FridgeScanUsage.fromJson(data['usageMetadata']),
        style: style,
      );
    } on TypeError catch (error) {
      throw FormatException('Gemini food scan returned an odd shape: $error');
    }
  }

  /// The request JSON. Public so tests can check its shape.
  static Map<String, dynamic> buildRequestBody(
    Uint8List overviewJpeg, {
    String mediaResolution = 'MEDIA_RESOLUTION_HIGH',
    bool perPartUltraHigh = false,
    String thinkingLevel = 'low',
    ScanStyle style = ScanStyle.full,
  }) {
    return {
      'contents': [
        {
          'parts': [
            {
              'inlineData': {
                'mimeType': 'image/jpeg',
                'data': base64Encode(overviewJpeg),
              },
              if (perPartUltraHigh) 'mediaResolution': {'level': _ultraHigh},
            },
            {'text': buildPrompt(style: style)},
          ],
        },
      ],
      // No temperature: Argon ignores sampling parameters.
      'generationConfig': {
        if (!perPartUltraHigh) 'mediaResolution': mediaResolution,
        'thinkingConfig': {'thinkingLevel': thinkingLevel},
        // A ceiling, not a target. v2 lists every item with a box, so the
        // JSON is longer than v1's, and a cut-off reply costs a whole retry.
        'maxOutputTokens': 32768,
        'responseMimeType': 'application/json',
        'responseSchema': style == ScanStyle.lean
            ? leanScanResponseSchema()
            : scanResponseSchema(),
      },
    };
  }

  /// Turns the decoded model JSON into a [ScanResponse]. Accepts a bare list
  /// as the items. Missing optional fields get defaults; non-food entries are
  /// dropped and counted; placeholder and empty names are dropped.
  static ScanResponse parseScanResponse(
    Object? decoded, {
    FridgeScanUsage usage = const FridgeScanUsage(),
    ScanStyle style = ScanStyle.full,
  }) {
    final lean = style == ScanStyle.lean;
    final Map<String, dynamic> root = decoded is Map<String, dynamic>
        ? decoded
        : {'items': decoded};

    final zones = [
      for (final zone in (root['zones'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>())
        ScanZone(
          name: (zone['name'] ?? '').toString().trim(),
          count: _toInt(zone['count']) ?? 0,
        ),
    ];

    var droppedNonFood = 0;
    final items = <ScannedItem>[];
    for (final json in (root['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()) {
      if (json[lean ? 'food' : 'isFood'] == false) {
        droppedNonFood++;
        continue;
      }
      final name = (json['name'] ?? '').toString().trim();
      if (name.isEmpty || FridgePhotoFoodAgent._isPlaceholderName(name)) {
        continue;
      }
      final description = lean
          ? ''
          : (json['description'] ?? '').toString().trim();
      items.add(
        ScannedItem(
          name: name,
          amount: lean ? '' : (json['amount'] ?? '').toString().trim(),
          foodType: FoodType.fromLabel(
            (json[lean ? 'type' : 'foodType'] ?? '').toString().trim(),
          ),
          confidence: ScanConfidence.fromLabel(
            json[lean ? 'conf' : 'confidence'],
          ),
          alternatives: _alternatives(
            json[lean ? 'alts' : 'alternatives'],
            name,
          ),
          location: (json[lean ? 'zone' : 'location'] ?? '').toString().trim(),
          box2d: _box(lean ? json['box'] : json['box_2d'] ?? json['box2d']),
          photoIndex: lean ? 0 : _toInt(json['photoIndex']) ?? 0,
          description: description.isEmpty ? null : description,
          expiryEstimateDays: _toInt(
            json[lean ? 'days' : 'expiryEstimateDays'],
          ),
        ),
      );
    }

    final tilt = root[lean ? 'tilt' : 'tiltDegrees'];
    return ScanResponse(
      zones: zones,
      items: items,
      tiltDegrees: tilt is num && tilt.isFinite ? tilt.toDouble() : 0,
      droppedNonFood: droppedNonFood,
      usage: usage,
    );
  }

  static int? _toInt(Object? value) {
    if (value is num) return value.isFinite ? value.round() : null;
    return int.tryParse(value?.toString() ?? '');
  }

  /// At most two non-empty names that differ from the item's own name.
  static List<String> _alternatives(Object? value, String name) {
    if (value is! List<dynamic>) return const [];
    final result = <String>[];
    for (final entry in value) {
      final alternative = entry.toString().trim();
      if (alternative.isEmpty ||
          alternative.toLowerCase() == name.toLowerCase() ||
          FridgePhotoFoodAgent._isPlaceholderName(alternative) ||
          result.contains(alternative)) {
        continue;
      }
      result.add(alternative);
      if (result.length == 2) break;
    }
    return result;
  }

  /// `[ymin, xmin, ymax, xmax]` clamped to 0–1000 and put in min/max order, or
  /// null if it isn't four numbers.
  static List<int>? _box(Object? value) {
    if (value is! List<dynamic> || value.length != 4) return null;
    final numbers = [for (final entry in value) _toInt(entry)];
    if (numbers.contains(null)) return null;
    final v = [for (final n in numbers) n!.clamp(0, 1000).toInt()];
    return [
      math.min(v[0], v[2]),
      math.min(v[1], v[3]),
      math.max(v[0], v[2]),
      math.max(v[1], v[3]),
    ];
  }

  /// The v2 prompt. Public so tests can check what it asks for.
  static String buildPrompt({ScanStyle style = ScanStyle.full}) {
    final foodTypes = FoodType.values
        .map((foodType) => foodType.label)
        .join(', ');

    if (style == ScanStyle.lean) return _leanPrompt(foodTypes);

    return '''
You are a fridge inventory assistant. Inspect the entire image and list every visible food and drink item. Do not leave anything out: a missing item is worse than a doubtful one.

Work zone by zone: each shelf from top to bottom, then the drawers, then the door bins from top to bottom. For each zone, first state how many items you count in it, then list those items. Combine repeated identical items into one entry.

Identification rules:
- Systematically examine every bag, jar, box, and container, including partially visible, opaque, or nested ones (a bag inside a bag) and items at the edges of the image.
- Name the contents, not the container: "tomato stew", not "glass dish"; "leftover rice", not "plastic box". If the contents cannot be seen, give your best guess of what is inside.
- Consider the full range of foods, including dried herbs and herbal teas (e.g. linden/ihlamur, chamomile, mint), spices, and regional or international items. Do not default to a common lookalike food (e.g. never call dried flowers or herbs "bread").
- For packaged or labeled items, READ any visible text on the packaging and identify the product from its label rather than its shape or color.
- For unlabeled bags of dry staples, identify by texture and by what is common in a home pantry: fine matte white powder = flour; crystalline white = sugar or salt; small oblong translucent grains = rice; golden cracked grains = bulgur; round dried seeds = beans, chickpeas, or lentils; also consider pasta, semolina, and oats.
- If you are not sure what an item is, still list it: give your best guess as the name, set "confidence" to "guess", and put up to two other possibilities in "alternatives". Never output "Unknown", "Unidentified", or any placeholder name.

For each item give:
- "name": what it is.
- "amount": a count-based amount such as "3 bananas", "1 milk carton", "1 bag of spinach", "6 eggs".
- "foodType": one of these values: $foodTypes
- "confidence": "sure" if you can read the label or it is unmistakable, "likely" if it is probably right, "guess" if you are unsure.
- "alternatives": up to two other names it could be (an empty array if "sure").
- "location": the name of the zone it is in, e.g. "shelf 2", "crisper drawer", "door bin 1".
- "box_2d": [ymin, xmin, ymax, xmax], its bounding box on a 0 to 1000 grid over the whole image.
- "photoIndex": 0 (there is one photo).
- "isFood": true for food and drink; false for medicine, supplements, vitamins, skincare, household items, and plants.
- "description": an optional short detail, or an empty string.
- "expiryEstimateDays": the typical number of days from today until it spoils in a fridge (a whole number), or null if you cannot reasonably estimate it.

Also give "tiltDegrees": the clockwise rotation in degrees the photo needs to be level (0 if it is already level, negative for counter-clockwise).

Return only valid JSON, with no Markdown or explanation, in this shape:
{
  "zones": [{"name": "shelf 1", "count": 2}],
  "items": [
    {
      "name": "Bananas",
      "amount": "3 bananas",
      "foodType": "Produce",
      "confidence": "sure",
      "alternatives": [],
      "location": "shelf 1",
      "box_2d": [120, 80, 260, 310],
      "photoIndex": 0,
      "isFood": true,
      "description": "",
      "expiryEstimateDays": 5
    }
  ],
  "tiltDegrees": 0
}
''';
  }

  static String _leanPrompt(String foodTypes) {
    return '''
You are a fridge inventory assistant. Inspect the whole image and list every visible food and drink item. A missing item is worse than a doubtful one, but only list what you can point to.

Work zone by zone: each shelf from top to bottom, then the drawers, then the door bins from top to bottom. For each zone, first state how many items you count in it, then list those items. Combine identical items into one entry.

Rules:
- Check every bag, jar, box and container, including partly visible, opaque or nested ones and items at the image edges.
- Name the contents, not the container: "tomato stew", not "glass dish". If the contents are hidden, give your best guess.
- READ any visible label and identify the product from it, not from shape or colour.
- Consider dried herbs, herbal teas (linden/ihlamur, chamomile, mint), spices and regional foods. Never call dried herbs "bread".
- Unlabeled dry staples: fine matte white powder = flour; crystalline white = sugar or salt; small oblong translucent grains = rice; golden cracked grains = bulgur; round dried seeds = beans, chickpeas or lentils; also pasta, semolina, oats.
- "sure" only when you can read the label or the item is unmistakable from its shape. Anything inferred from colour, a container or a partial view is "likely" or "guess".
- The name is ONE item. Never write "X or Y" in a name; put other possibilities in "alts".
- Do not list an item unless you can point to it: no items inferred from context (e.g. "canned fish" or "blueberries" because something dark is visible). If you see an object but cannot tell what it is, list your best guess as "guess".
- Never output "Unknown", "Unidentified" or any placeholder name.
- Keep every string short: names at most 4 words, zone names like "shelf 2", "door bin 1".

Keys for each item:
- "name": what it is.
- "type": one of: $foodTypes
- "conf": "sure", "likely" or "guess".
- "alts": up to two other names it could be (empty array if "sure").
- "zone": the zone it is in.
- "box": [ymin, xmin, ymax, xmax] on a 0 to 1000 grid over the whole image.
- "food": true for food and drink; false for medicine, supplements, vitamins, protein powders, skincare, household items and plants.
- "days": typical whole days from today until it spoils in a fridge, or null if unknown.

Also give "tilt": the clockwise rotation in degrees the photo needs to be level (0 if level, negative for counter-clockwise).

Return only valid JSON, no Markdown, in this shape:
{"zones": [{"name": "shelf 1", "count": 1}], "items": [{"name": "Bananas", "type": "Produce", "conf": "sure", "alts": [], "zone": "shelf 1", "box": [120, 80, 260, 310], "food": true, "days": 5}], "tilt": 0}
''';
  }
}
