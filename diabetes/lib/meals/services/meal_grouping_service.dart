import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/meal_models.dart';

class MealGroupingProposal {
  const MealGroupingProposal({
    required this.groupId,
    required this.canonicalName,
    required this.confidence,
    required this.explanation,
    required this.differences,
  });
  final String? groupId;
  final String canonicalName;
  final double confidence;
  final String explanation;
  final List<String> differences;
}

abstract interface class MealGroupingService {
  Future<MealGroupingProposal> propose(
    MealEvent meal,
    List<MealGroup> groups, {
    Uint8List? photo,
  });
}

class GeminiMealGroupingService implements MealGroupingService {
  const GeminiMealGroupingService({required this.apiKey, this.client});
  final String apiKey;
  final http.Client? client;
  static final Map<String, MealGroupingProposal> _cache = {};

  @override
  Future<MealGroupingProposal> propose(
    MealEvent meal,
    List<MealGroup> groups, {
    Uint8List? photo,
  }) async {
    if (apiKey.isEmpty) throw StateError('Gemini is not configured.');
    final safeMeal = {
      'name': meal.name,
      'restaurant': meal.restaurant,
      'components': meal.components,
      'portion': meal.portion.name,
      'mealOrder': meal.mealOrder.name,
      'preparation': meal.preparation.name,
    };
    final groupSummaries = groups
        .take(100)
        .map(
          (group) => {
            'id': group.id,
            'name': group.name,
            'summary': group.summary,
            'userConfirmedExamples': group.correctionExamples,
          },
        )
        .toList();
    final photoFingerprint = photo?.fold<int>(17, (hash, byte) => (hash * 31 + byte) & 0x7fffffff);
    final cacheKey = jsonEncode({
      'meal': safeMeal,
      'groups': groupSummaries,
      'photo': photoFingerprint,
    });
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final parts = <Map<String, dynamic>>[
      {
        'text': '''You group repeated meals for a personal meal journal. Compare only food identity and preparation. Do not make health claims. Return JSON only:
{"groupId":"existing id or new_group","canonicalName":"name","confidence":0.0,"explanation":"short","differences":["..."]}
Existing groups: ${jsonEncode(groupSummaries)}
New meal: ${jsonEncode(safeMeal)}''',
      },
      if (photo != null)
        {
          'inlineData': {'mimeType': 'image/jpeg', 'data': base64Encode(photo)},
        },
    ];
    final response = await (client ?? http.Client()).post(
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$apiKey',
      ),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {'role': 'user', 'parts': parts},
        ],
        'generationConfig': {'responseMimeType': 'application/json'},
      }),
    );
    if (response.statusCode != 200) throw StateError('Grouping request failed.');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = body['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (text == null) throw const FormatException('No grouping result.');
    final result = jsonDecode(text) as Map<String, dynamic>;
    final requestedId = result['groupId'] as String?;
    final validId = groups.any((group) => group.id == requestedId) ? requestedId : null;
    final proposal = MealGroupingProposal(
      groupId: requestedId == 'new_group' ? null : validId,
      canonicalName: result['canonicalName'] as String? ?? meal.name,
      confidence: ((result['confidence'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      explanation: result['explanation'] as String? ?? 'Similar meal details.',
      differences: (result['differences'] as List? ?? const []).whereType<String>().toList(),
    );
    _cache[cacheKey] = proposal;
    return proposal;
  }
}
