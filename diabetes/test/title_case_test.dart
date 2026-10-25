import 'package:diabetes/design/title_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capitalizes major words', () {
    expect(titleCase('Your fridge'), 'Your Fridge');
    expect(titleCase('hello, my name is'), 'Hello, My Name Is');
    expect(titleCase('what we eat if it rains'), 'What We Eat If It Rains');
  });

  test('lowercases articles, coordinating conjunctions and prepositions', () {
    expect(titleCase('salt and pepper'), 'Salt and Pepper');
    expect(titleCase('i like the pizza'), 'I Like the Pizza');
    expect(titleCase('cook with what you have'), 'Cook with What You Have');
    expect(titleCase('Fish AND Chips'), 'Fish and Chips');
  });

  test('always capitalizes the first and last word', () {
    expect(titleCase('the fridge of'), 'The Fridge Of');
    expect(titleCase('of mice'), 'Of Mice');
  });

  test('leaves other letters alone', () {
    expect(titleCase('mcDonald'), 'McDonald');
    expect(titleCase(''), '');
  });
}
