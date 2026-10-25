/// Words kept lowercase mid-title: articles, coordinating conjunctions and
/// prepositions. Nouns, pronouns, verbs, adjectives, adverbs and subordinating
/// conjunctions ("if", "because", "as"…) are capitalized.
const _lowercaseWords = {
  // articles
  'a', 'an', 'the',
  // coordinating conjunctions
  'and', 'but', 'or', 'nor', 'for', 'yet', 'so',
  // prepositions
  'at', 'by', 'in', 'of', 'on', 'to', 'up', 'off', 'out', 'per', 'via', //
  'with', 'from', 'into', 'onto', 'over', 'upon', 'under', 'about', 'above',
  'below', 'between', 'through', 'during', 'within', 'without', 'across',
  'against', 'along', 'among', 'around', 'behind', 'beside', 'beyond',
  'despite', 'near', 'toward', 'towards',
};

/// Title case: the first and last word and every major word start with a
/// capital; articles, coordinating conjunctions and prepositions stay
/// lowercase in between. Other letters are left as typed, so names like
/// "McDonald" survive.
String titleCase(String text) {
  final words = text.split(' ');
  final last = words.length - 1;
  return [
    for (var i = 0; i < words.length; i++)
      if (words[i].isEmpty ||
          (i != 0 &&
              i != last &&
              _lowercaseWords.contains(words[i].toLowerCase())))
        words[i].toLowerCase()
      else
        words[i][0].toUpperCase() + words[i].substring(1),
  ].join(' ');
}
