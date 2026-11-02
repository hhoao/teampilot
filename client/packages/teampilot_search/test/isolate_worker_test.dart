import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('tp_isolate_');
    File(
      '${fixture.path}/a.dart',
    ).writeAsStringSync('hello world\nfoo hello\n');
    File('${fixture.path}/b.txt').writeAsStringSync('nothing here\n');
    Directory('${fixture.path}/nested').createSync();
    File(
      '${fixture.path}/nested/deep_router.dart',
    ).writeAsStringSync('hello nested\n');
    Directory('${fixture.path}/.git').createSync();
    File('${fixture.path}/.git/hello').writeAsStringSync('hello ignored\n');
  });

  tearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });

  group('IsolatedContentSearch', () {
    test('streams matches computed on the worker isolate', () async {
      final engine = IsolatedContentSearch();
      final matches = await engine
          .run(fixture.path, const TpSearchOptions(pattern: 'hello'))
          .toList();

      expect(matches.map((m) => m.relativePath).toSet(), {
        'a.dart',
        'nested/deep_router.dart',
      });
      expect(matches, hasLength(3));
      // Offsets still refer to the original line text.
      final first = matches.firstWhere((m) => m.relativePath == 'a.dart');
      expect(
        first.lineText.substring(first.matchStart, first.matchEnd),
        'hello',
      );
    });

    test('surfaces engine failures as stream errors', () async {
      final missing = '${fixture.path}/missing-root';
      final engine = IsolatedContentSearch();
      Object? error;
      try {
        await engine
            .run(missing, const TpSearchOptions(pattern: 'hello'))
            .drain<void>();
      } on Object catch (e) {
        error = e;
      }
      expect(error, isA<StateError>());
      // A fresh engine on the same path fails the same way.
      final second = IsolatedContentSearch();
      await expectLater(
        second.run(missing, const TpSearchOptions(pattern: 'hello')),
        emitsError(isA<StateError>()),
      );
    });

    test('cancel closes the stream without waiting for the walk', () async {
      final engine = IsolatedContentSearch();
      final done = Completer<void>();
      final received = <TpSearchMatch>[];
      final subscription = engine
          .run(fixture.path, const TpSearchOptions(pattern: 'hello'))
          .listen(received.add, onDone: done.complete);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      engine.cancel();
      await done.future.timeout(const Duration(seconds: 10));
      await subscription.cancel();

      expect(received.length, lessThanOrEqualTo(3));
    });

    test('a cancelled run does not poison the next one', () async {
      final engine = IsolatedContentSearch();
      final subscription = engine
          .run(fixture.path, const TpSearchOptions(pattern: 'hello'))
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();

      final matches = await engine
          .run(fixture.path, const TpSearchOptions(pattern: 'hello'))
          .toList();
      expect(matches, hasLength(3));
    });
  });

  group('IsolatedFileIndex', () {
    test('builds and queries on the worker isolate', () async {
      final index = IsolatedFileIndex();
      addTearDown(index.dispose);

      await index.build(fixture.path);
      expect(index.isBuilt, isTrue);

      final fuzzy = await index.query('router');
      expect(
        fuzzy.map((hit) => hit.relativePath),
        contains('nested/deep_router.dart'),
      );

      final byName = await index.query('deep', mode: TpFileMatchMode.contains);
      expect(byName.map((hit) => hit.name), ['deep_router.dart']);

      expect(await index.queryDirectories('nested'), contains('nested'));
    });

    test('rebuilds in place and frees the handle on dispose', () async {
      final index = IsolatedFileIndex();
      await index.build(fixture.path);
      await index.build(fixture.path);
      expect(await index.query('a'), isNotEmpty);

      index.dispose();
      expect(index.isBuilt, isFalse);
      expect(index.query('a'), throwsStateError);
    });

    test('queries before the first build are rejected', () {
      final index = IsolatedFileIndex();
      addTearDown(index.dispose);
      expect(index.query('a'), throwsStateError);
    });
  });
}
