import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no field overrides the themed input border', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('border: OutlineInputBorder()'))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
