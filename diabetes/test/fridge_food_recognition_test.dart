import 'dart:convert';
import 'dart:typed_data';

import 'package:diabetes/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Wraps a food list in Gemini's `generateContent` response envelope.
http.Response _geminiResponse(List<Map<String, dynamic>> foods) {
  return http.Response(
    jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(foods)},
            ],
          },
        },
      ],
    }),
    200,
  );
}

void main() {
  test('Gemini fridge recognition adapts structured food output', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return _geminiResponse([
        {
          'name': 'Apples',
          'amount': '3 apples',
          'foodType': 'Produce',
          'description': 'red apples',
        },
        {
          'name': 'Milk',
          'amount': '1 carton',
          'foodType': 'Dairy',
          'description': '',
        },
      ]);
    });

    final foods = await FridgePhotoFoodAgent.detectFoods(
      Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
      client: client,
      apiKey: 'test-token',
    );

    expect(capturedRequest.url.toString(), FridgePhotoFoodAgent.endpoint);
    expect(capturedRequest.headers['x-goog-api-key'], 'test-token');
    expect(capturedRequest.body, contains('inline_data'));
    expect(foods, hasLength(2));
    expect(foods.first.name, 'Apples');
    expect(foods.first.amount, '3 apples');
    expect(foods.first.foodType, FoodType.produce);
    expect(foods.last.name, 'Milk');
    expect(foods.last.foodType, FoodType.dairy);
    // No expiry estimate in the payload -> no expiry date (backward compat).
    expect(foods.first.expiryDate, isNull);
  });

  test('Gemini fridge recognition maps expiry estimate to a date', () async {
    final client = MockClient((request) async {
      return _geminiResponse([
        {
          'name': 'Spinach',
          'amount': '1 bag',
          'foodType': 'Produce',
          'description': '',
          'expiryEstimateDays': 4,
        },
      ]);
    });

    final foods = await FridgePhotoFoodAgent.detectFoods(
      Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
      client: client,
      apiKey: 'test-token',
    );

    expect(foods, hasLength(1));
    final expiry = foods.first.expiryDate;
    expect(expiry, isNotNull);
    final daysAway = expiry!.difference(DateTime.now()).inDays;
    // Allow for the sub-day remainder in the difference calculation.
    expect(daysAway, inInclusiveRange(3, 4));
  });

  test('Gemini fridge recognition drops placeholder "Unknown" items', () async {
    final client = MockClient((request) async {
      return _geminiResponse([
        {
          'name': 'Unknown',
          'amount': '1 item',
          'foodType': 'Other',
          'description': '',
        },
        {
          'name': 'Unknown item',
          'amount': '1 bag',
          'foodType': 'Other',
          'description': '',
        },
        {
          'name': 'Rice',
          'amount': '1 bag of rice',
          'foodType': 'Grain',
          'description': '',
        },
      ]);
    });

    final foods = await FridgePhotoFoodAgent.detectFoods(
      Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
      client: client,
      apiKey: 'test-token',
    );

    expect(foods, hasLength(1));
    expect(foods.single.name, 'Rice');
  });

  test('Gemini fridge recognition requires an API key', () async {
    expect(
      () => FridgePhotoFoodAgent.detectFoods(
        Uint8List.fromList(const [1]),
        apiKey: '',
      ),
      throwsA(isA<Exception>()),
    );
  });
}
