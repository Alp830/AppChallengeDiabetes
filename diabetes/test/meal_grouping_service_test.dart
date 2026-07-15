import 'dart:convert';

import 'package:diabetes/meals/models/meal_models.dart';
import 'package:diabetes/meals/services/meal_grouping_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Gemini grouping sends food context but no glucose or identity', () async {
    late String requestBody;
    final client = MockClient((request) async {
      requestBody = request.body;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'groupId': 'group-1',
                      'canonicalName': 'Turkey sandwich',
                      'confidence': .92,
                      'explanation': 'Same main ingredients',
                      'differences': ['larger portion'],
                    }),
                  },
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final service = GeminiMealGroupingService(apiKey: 'test', client: client);
    final proposal = await service.propose(
      _meal(),
      const [MealGroup(id: 'group-1', name: 'Turkey sandwich')],
    );

    expect(proposal.groupId, 'group-1');
    expect(proposal.confidence, .92);
    expect(requestBody, contains('Turkey sandwich'));
    expect(requestBody.toLowerCase(), isNot(contains('glucose')));
    expect(requestBody, isNot(contains('userId')));
    expect(requestBody, isNot(contains('timestamp')));
  });

  test('invalid Gemini JSON fails without inventing a group', () async {
    final client = MockClient((_) async => http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'not-json'},
              ],
            },
          },
        ],
      }),
      200,
    ));
    expect(
      () => GeminiMealGroupingService(apiKey: 'test', client: client)
          .propose(_meal(), const []),
      throwsA(isA<FormatException>()),
    );
  });
}

MealEvent _meal() => MealEvent(
  id: 'meal-1',
  name: 'Turkey sandwich',
  timestamp: DateTime(2026, 7, 13, 12),
  mealType: 'Lunch',
  portion: MealPortion.larger,
  carbBand: CarbBand.medium,
  mealOrder: MealOrder.together,
  preparation: MealPreparation.fresh,
  components: const ['turkey', 'bread', 'lettuce'],
);
