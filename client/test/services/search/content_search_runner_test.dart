import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_search_runner.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('tp_runner_');
    File('${fixture.path}/a.dart').writeAsStringSync('hello world\nfoo hello\n');
    File('${fixture.path}/b.txt').writeAsStringSync('no match here\n');
    Directory('${fixture.path}/.hidden').createSync();
    File('${fixture.path}/.hidden/x.dart').writeAsStringSync('hello hidden\n');
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  test('local filesystem uses rust backend and streams matches', () async {
    final runner = ContentSearchRunner(
      fs: LocalFilesystem(),
      root: fixture.path,
    );
    expect(runner.backendLabel, 'rust');
    final matches = await runner
        .run(const TpSearchOptions(pattern: 'hello'))
        .toList();
    expect(matches.map((m) => m.relativePath).toSet(), {'a.dart'});
    expect(matches.where((m) => m.relativePath == 'a.dart').length, 2);
  });

  test('forceFallback routes to dart fallback backend label', () {
    final runner = ContentSearchRunner(
      fs: LocalFilesystem(),
      root: fixture.path,
      forceFallback: true,
    );
    expect(runner.backendLabel, 'dart-fallback');
  });

  test('non-local filesystem with forceFallback searches via fallback',
      () async {
    final runner = ContentSearchRunner(
      fs: _FakeRemoteFs(fixture.path),
      root: fixture.path,
      forceFallback: true,
    );
    expect(runner.backendLabel, 'dart-fallback');
    final matches = await runner
        .run(const TpSearchOptions(pattern: 'hello'))
        .toList();
    expect(matches.where((m) => m.relativePath == 'a.dart').length, 2);
  });
}

class _FakeRemoteFs extends LocalFilesystem {
  _FakeRemoteFs(this.root);
  final String root;
}
