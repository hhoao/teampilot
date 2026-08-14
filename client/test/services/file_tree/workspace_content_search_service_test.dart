import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

import 'package:teampilot/services/file_tree/workspace_content_search_service.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('tp_wss_test_');
    File('${fixture.path}/a.dart').writeAsStringSync('hello world\n');
    File('${fixture.path}/b.txt').writeAsStringSync('hello text\n');
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  test('uses rust engine for local paths', () async {
    final service = WorkspaceContentSearchService();
    final matches = await service
        .search(fixture.path, 'hello')
        .toList();
    expect(matches.map((m) => m.relativePath).toSet(), {'a.dart', 'b.txt'});
  });

  test('local path through service returns TpSearchMatch', () async {
    final service = WorkspaceContentSearchService();
    final first = await service.search(fixture.path, 'hello').first;
    expect(first, isA<TpSearchMatch>());
  });
}
