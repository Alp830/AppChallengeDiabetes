import 'package:diabetes/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Meal images are handed to the widget layer as a URL and loaded by the
/// platform's own image loader, never fetched through Dart. On web that
/// distinction is the whole feature: a Dart `http.get` is a CORS request, so
/// Chrome attaches `Origin: http://localhost:<port>`, and Pollinations answers
/// every such request with an immediate 403. An `<img>` load carries no
/// Origin header and succeeds. These tests pin that: building a
/// recommendation's image must touch no HTTP client at all.
void main() {
  late http.Client originalClient;

  setUp(() {
    originalClient = GeminiMealService.httpClient;
  });

  tearDown(() {
    GeminiMealService.httpClient = originalClient;
  });

  test('attaching images issues no HTTP request of its own', () {
    var calls = 0;
    GeminiMealService.httpClient = MockClient((request) async {
      calls++;
      return http.Response('should never be called', 200);
    });

    final results = GeminiMealService.attachImagesForTesting([
      for (var i = 0; i < 5; i++) _recommendation('dish $i'),
    ]);

    expect(
      calls,
      0,
      reason: 'a Dart fetch is what triggers the localhost-origin 403',
    );
    expect(results, hasLength(5));
    expect(results.every((r) => r.imageUrl != null), isTrue);
  });

  test('the image URL points at Pollinations and carries the prompt', () {
    final result = GeminiMealService.attachImagesForTesting([
      _recommendation('grilled salmon on a white plate'),
    ]).single;

    final uri = Uri.parse(result.imageUrl!);

    expect(uri.scheme, 'https');
    expect(uri.host, 'image.pollinations.ai');
    expect(uri.pathSegments.first, 'prompt');
    expect(uri.pathSegments.last, contains('grilled salmon on a white plate'));
    expect(uri.queryParameters['nologo'], 'true');
    expect(uri.queryParameters['referrer'], 'diabetes-app');
  });

  test('the prompt is framed as a photo so the dish is recognisable', () {
    final result = GeminiMealService.attachImagesForTesting([
      _recommendation('lentil soup'),
    ]).single;

    expect(Uri.parse(result.imageUrl!).pathSegments.last, contains('photo'));
  });

  test('the requested image is a wide banner, not a square', () {
    final uri = Uri.parse(
      GeminiMealService.attachImagesForTesting([
        _recommendation('lentil soup'),
      ]).single.imageUrl!,
    );

    final width = int.parse(uri.queryParameters['width']!);
    final height = int.parse(uri.queryParameters['height']!);

    expect(width / height, closeTo(2.5, 0.01));
  });

  test('the prompt states the dimensions it is composing for', () {
    final uri = Uri.parse(
      GeminiMealService.attachImagesForTesting([
        _recommendation('lentil soup'),
      ]).single.imageUrl!,
    );
    final instruction = uri.pathSegments.last;

    // The host crops to the query-string size no matter what, so the prompt
    // has to name that same size or the model composes for the wrong shape.
    expect(instruction, contains(uri.queryParameters['width']!));
    expect(instruction, contains(uri.queryParameters['height']!));
  });

  test('the dish leads the prompt so the model stays on the subject', () {
    final instruction = Uri.parse(
      GeminiMealService.attachImagesForTesting([
        _recommendation('red lentil peanut curry'),
      ]).single.imageUrl!,
    ).pathSegments.last;

    // Buried behind the framing notes, the model drifted off the dish
    // entirely — it returned a cheese tart for this exact curry.
    expect(instruction, startsWith('red lentil peanut curry'));
  });

  test('the prompt allows cropping when it makes a better picture', () {
    final instruction = Uri.parse(
      GeminiMealService.attachImagesForTesting([
        _recommendation('lentil soup'),
      ]).single.imageUrl!,
    ).pathSegments.last;

    expect(instruction, contains('past the edges'));
  });

  test('two dishes get two distinct URLs', () {
    final results = GeminiMealService.attachImagesForTesting([
      _recommendation('omelette'),
      _recommendation('baked salmon'),
    ]);

    expect(results.first.imageUrl, isNot(results.last.imageUrl));
  });

  test('a meal without an image prompt gets no URL', () {
    final results = GeminiMealService.attachImagesForTesting([
      _recommendation(''),
    ]);

    expect(results.single.imageUrl, isNull);
  });

  test('attaching an image preserves the rest of the recommendation', () {
    final result = GeminiMealService.attachImagesForTesting([
      _recommendation('miso soup'),
    ]).single;

    expect(result.dishName, 'Dish');
    expect(result.reason, 'Because');
    expect(result.ingredients, const ['rice']);
    expect(result.instructions, const ['cook']);
  });
}

MealRecommendation _recommendation(String imagePrompt) => MealRecommendation(
  dishName: 'Dish',
  imagePrompt: imagePrompt,
  reason: 'Because',
  ingredients: const ['rice'],
  instructions: const ['cook'],
);
