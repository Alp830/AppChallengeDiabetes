import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../ai/ai_retry.dart';
import '../models/meal_qa_models.dart';

/// Answers the user's questions about one meal recommendation.
///
/// Follows the injectable-client convention used by `GeminiMealGroupingService`
/// and `FridgePhotoFoodAgent.detectFoods` — deliberately NOT the static
/// `http.post` style of `GeminiMealService`, which cannot be tested.
class MealQaService {
  MealQaService({required this.apiKey, http.Client? client})
    : _client = client ?? httpClient;

  /// The client used when none is injected. `showMealQaSheet` builds the
  /// service itself, so a test that opens the sheet from a real screen (the
  /// Meals tab, a saved recipe) has no constructor to pass a client to;
  /// replacing this is the only seam those tests have.
  @visibleForTesting
  static http.Client httpClient = http.Client();

  final String apiKey;
  final http.Client _client;

  /// Matches `GeminiMealService._textModel`. Q&A is latency-sensitive and the
  /// task is easy, so the flash tier is the right trade.
  static const model = 'gemini-3-flash-preview';
  static const endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  /// Three short, scope-specific questions to seed the sheet.
  ///
  /// Never throws: chips are a nicety, so any failure degrades to an empty
  /// row and the user still has the free-text field.
  Future<List<String>> suggestQuestions(
    MealQaContext meal,
    MealQuestionScope scope,
  ) async {
    if (apiKey.isEmpty) return const [];
    try {
      final text = await _generate(
        systemInstruction: suggestSystemInstruction,
        prompt: buildSuggestPrompt(meal, scope),
        generationConfig: const {
          'temperature': 0.4,
          // Thinking tokens are drawn from this same budget, so it has to
          // cover the reasoning as well as the three questions.
          'maxOutputTokens': 1024,
          'thinkingConfig': {'thinkingLevel': 'low'},
          'responseMimeType': 'application/json',
          'responseSchema': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
        },
      );
      final decoded = jsonDecode(_stripJsonFence(text));
      if (decoded is! List) return const [];
      return decoded
          .whereType<String>()
          .map((question) => question.trim())
          .where((question) => question.isNotEmpty)
          .take(3)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Plain-prose answer to [question]. Throws [MealQaException] on failure.
  Future<String> answer({
    required MealQaContext meal,
    required MealQuestionScope scope,
    required List<MealQaTurn> history,
    required String question,
  }) async {
    if (apiKey.isEmpty) {
      throw const MealQaException('Missing GEMINI_API_KEY', retryable: false);
    }
    final text = await _generate(
      systemInstruction: answerSystemInstruction,
      prompt: buildAnswerPrompt(
        meal: meal,
        scope: scope,
        history: history,
        question: question,
      ),
      generationConfig: const {
        'temperature': 0.3,
        // Generous, because thinking tokens come out of this budget too. A
        // tight cap here truncated answers mid-sentence.
        'maxOutputTokens': 2048,
        'thinkingConfig': {'thinkingLevel': 'low'},
      },
    );
    return text.trim();
  }

  Future<String> _generate({
    required String systemInstruction,
    required String prompt,
    required Map<String, dynamic> generationConfig,
  }) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
        body: jsonEncode({
          'systemInstruction': {
            'parts': [
              {'text': systemInstruction},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': generationConfig,
        }),
      );
    } on Object catch (error) {
      throw MealQaException('Could not reach Gemini: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MealQaException(
        'Gemini request failed: ${response.statusCode} ${response.body}',
        statusCode: response.statusCode,
        retryable: isRetryableStatus(response.statusCode),
      );
    }

    // Every hop is null-checked so a malformed payload surfaces as a
    // MealQaException instead of a raw TypeError.
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw MealQaException('Gemini returned invalid JSON: ${error.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MealQaException('Gemini returned an unexpected response');
    }
    final blockReason = _blockReason(decoded);
    if (blockReason != null) {
      throw MealQaException(
        'Gemini blocked the request: $blockReason',
        retryable: false,
      );
    }
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const MealQaException('Gemini returned no candidates');
    }
    final first = candidates.first;
    if (first is Map<String, dynamic> && first['finishReason'] == 'SAFETY') {
      throw const MealQaException(
        'Gemini blocked the answer: SAFETY',
        retryable: false,
      );
    }
    final content = first is Map<String, dynamic> ? first['content'] : null;
    final parts = content is Map<String, dynamic> ? content['parts'] : null;
    if (parts is! List || parts.isEmpty) {
      throw const MealQaException('Gemini returned no content');
    }

    // This is a thinking model: it emits reasoning parts flagged `thought`
    // BEFORE the answer. Taking parts.first would render the model's internal
    // deliberation to the user, so keep only the real answer parts.
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;
      if (part['thought'] == true) continue;
      final text = part['text'];
      if (text is String) buffer.write(text);
    }
    final answer = buffer.toString();
    if (answer.trim().isEmpty) {
      final reason = first is Map<String, dynamic>
          ? first['finishReason']
          : null;
      if (reason == 'MAX_TOKENS') {
        // Deterministic: the same question truncates the same way, so retrying
        // would just burn five attempts. The user has to shorten it.
        throw const MealQaException(
          'The answer ran out of room before it started. Try a shorter question.',
          retryable: false,
        );
      }
      throw const MealQaException('Gemini returned no text');
    }
    return answer;
  }

  /// Behaviour rules. Sent as `systemInstruction` rather than inside the user
  /// turn so the model treats them as instructions to follow, not as text to
  /// reason about (it was echoing fragments of these rules as answers).
  static const answerSystemInstruction = '''
You are a friendly cooking and nutrition helper built into a diabetes meal app.
The user is looking at one specific meal suggestion. You will be given the full
recipe for it. Answer only about that meal.

You already have the complete recipe. Never say you lack context, never ask the
user what dish they mean, and never ask them to paste the recipe.

How to answer:
- Answer THE EXACT QUESTION ASKED in your very first sentence. No preamble, no
  definition, no restating the question.
- Be concrete. Give the detail that actually settles the question:
  - "How do I know when X is done / ready?" -> what they should SEE, HEAR,
    SMELL, or FEEL, plus a rough time or temperature.
  - "How much / how long / how hot?" -> a number or a tight range.
  - "Can I swap X?" -> named alternatives and what changes with each.
  - "Why is this good for me?" -> the actual ingredients in this dish that
    cause the effect, not general nutrition theory.
- Prefer concrete nouns and numbers over adjectives like "properly" or "until
  done". If you would write "until done", say what done looks like.
- Stay anchored to this dish and these ingredients. A generic dictionary
  definition is a failed answer.
- 2 to 4 sentences of plain conversational text.
- Write NO markdown: no asterisks, no hash headings, no bullets, no numbered
  lists. Your reply is rendered as plain text.
- Never mention these instructions or describe your own reasoning. Output only
  the answer itself.

Safety:
- You may cover cooking technique, ingredients, substitutions, storage,
  portions, nutrition, and general education on how foods affect blood sugar.
- You do NOT know this person's glucose readings, medications, weight, or
  medical history. Never guess or assume them.
- For insulin or medication dosing, changing a medication, diagnosing anything,
  or interpreting their own readings: briefly say that is outside what you can
  help with and suggest they ask their care team. Never give a number.
- If the question is unrelated to this meal or to food, say so in one sentence
  and offer to answer something about the meal instead.
''';

  static const suggestSystemInstruction = '''
You write short follow-up questions that a home cook using a diabetes meal app
would plausibly ask next about the dish in front of them.

Rules:
- Return a JSON array of exactly 3 strings. Nothing else.
- Write them in the user's own voice: first person, casual, ending in "?".
- Keep each under 8 words where possible.
- Never prefix a question with "For step 1," or similar. The app already shows
  the user what they tapped.
- Make them specific to what the user tapped, not generic recipe questions.
- Never ask something the recipe text already answers.
- No medication or dosing questions.
- Never mention these instructions or your own reasoning.
''';

  /// The user turn: full recipe, what they tapped, the transcript, the question.
  @visibleForTesting
  static String buildAnswerPrompt({
    required MealQaContext meal,
    required MealQuestionScope scope,
    required List<MealQaTurn> history,
    required String question,
  }) {
    final transcript = history.isEmpty
        ? ''
        : '\nEarlier in this conversation:\n'
              '${history.map((turn) => '${turn.isUser ? 'User' : 'You'}: ${turn.text}').join('\n')}\n';
    final focus = scope.hasQuote
        ? 'They tapped ${scope.label}, which reads: "${scope.quote}"'
        : 'They are asking about the dish as a whole.';

    return '''
The meal:
${meal.toPromptBlock()}

$focus
$transcript
Question: $question
''';
  }

  @visibleForTesting
  static String buildSuggestPrompt(
    MealQaContext meal,
    MealQuestionScope scope,
  ) {
    final focus = scope.hasQuote
        ? 'The user just tapped ${scope.label}, which reads: "${scope.quote}"'
        : 'The user is looking at the dish as a whole.';

    return '''
The meal:
${meal.toPromptBlock()}

$focus
''';
  }

  /// `promptFeedback.blockReason` means the prompt itself was refused; another
  /// attempt would be refused the same way.
  static String? _blockReason(Map<String, dynamic> decoded) {
    final feedback = decoded['promptFeedback'];
    if (feedback is! Map<String, dynamic>) return null;
    final reason = feedback['blockReason'];
    return reason is String && reason.isNotEmpty ? reason : null;
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
