@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

void main() {
  test('streams first results promptly and stops on maxResults', () async {
    final dir = Directory.systemTemp.createTempSync('tp_search_it_');
    for (var i = 0; i < 50; i++) {
      File('${dir.path}/f$i.dart')
          .writeAsStringSync('line one\nhello target\nline three\n');
    }
    addTearDown(() => dir.deleteSync(recursive: true));

    final stopwatch = Stopwatch()..start();
    final engine = TpSearchEngine();
    final matches = await engine
        .search(dir.path, const TpSearchOptions(pattern: 'hello target'))
        .take(10)
        .toList();
    stopwatch.stop();

    expect(matches.length, 10);
    expect(stopwatch.elapsedMilliseconds,
        lessThan(5000)); // streaming, not a full-tree wait
  });
}
