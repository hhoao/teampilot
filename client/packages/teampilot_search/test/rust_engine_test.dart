import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

void main() {
  late Directory fixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('tp_search_test_');
    File('${fixture.path}/a.dart')
        .writeAsStringSync('hello world\nfoo hello\n');
    File('${fixture.path}/b.txt').writeAsStringSync('no match here\n');
    Directory('${fixture.path}/sub').createSync();
    File('${fixture.path}/sub/c.rs').writeAsStringSync('HELLO upper\n');
    File('${fixture.path}/.gitignore').writeAsStringSync('ignored.txt\n');
    File('${fixture.path}/ignored.txt').writeAsStringSync('hello ignored\n');
    Directory('${fixture.path}/.hidden_dir').createSync();
    File('${fixture.path}/.hidden_dir/x.dart').writeAsStringSync('hello hidden\n');
    File('${fixture.path}/bin.dat').writeAsBytesSync([0, 0, 104, 101, 108, 108, 111, 0]);
  });

  tearDown(() => fixture.deleteSync(recursive: true));

  TpSearchEngine engine() => TpSearchEngine();

  test('streams matches with char offsets, skipping hidden/gitignored/binary',
      () async {
    final matches = await engine()
        .search(fixture.path, const TpSearchOptions(pattern: 'hello'))
        .toList();
    // WalkParallel reports matches in nondeterministic order across cores:
    // assert on the set of paths, not the sequence.
    expect(matches.map((m) => m.relativePath).toSet(), {'a.dart', 'sub/c.rs'});
    expect(matches.length, 3);
    // Multi-match chunks pack several files' strings into one buffer: every
    // match's path must point at its own file, not the chunk's first path.
    expect(
      matches.every((m) => m.path.endsWith(m.relativePath)),
      isTrue,
      reason: 'each match path must reference its own file',
    );
    final first = matches.first;
    expect(first.lineNumber, 1);
    expect(first.lineText, 'hello world\n');
    expect(first.matchStart, 0);
    expect(first.matchEnd, 5);
  });

  test('regex + smart case', () async {
    final smart = await engine()
        .search(
          fixture.path,
          const TpSearchOptions(pattern: 'HELLO', smartCase: true),
        )
        .toList();
    expect(smart.map((m) => m.relativePath), ['sub/c.rs']);

    final re = await engine()
        .search(fixture.path, const TpSearchOptions(pattern: 'h[e]llo'))
        .toList();
    expect(re.length, 3);
  });

  test('non-ASCII byte offset converts to char offset', () async {
    File('${fixture.path}/zh.txt')
        .writeAsStringSync('你好 hello world\n');
    final m = await engine()
        .search(fixture.path, const TpSearchOptions(pattern: 'hello'))
        .firstWhere((m) => m.relativePath == 'zh.txt');
    expect(m.lineText, '你好 hello world\n');
    expect(m.matchStart, 3); // 2 CJK chars (6 bytes) + 1 space = char offset 3
    expect(m.matchEnd, 8);
  });

  test('invalid regex -> stream error, no crash', () async {
    await expectLater(
      engine()
          .search(fixture.path, const TpSearchOptions(pattern: '[unclosed'))
          .toList(),
      throwsA(isA<FormatException>()),
    );
  });

  test('maxResults truncates with done', () async {
    final matches = await engine()
        .search(
          fixture.path,
          const TpSearchOptions(pattern: 'hello', maxResults: 2),
        )
        .toList();
    expect(matches.length, 2);
  });

  test('cancel() stops the stream', () async {
    final e = engine();
    final collected = <TpSearchMatch>[];
    final sub = e
        .search(fixture.path, const TpSearchOptions(pattern: 'hello'))
        .listen(collected.add, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    e.cancel();
    sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('non-existent root -> stream error', () async {
    await expectLater(
      engine()
          .search('${fixture.path}/nope', const TpSearchOptions(pattern: 'x'))
          .toList(),
      throwsA(anything),
    );
  });

  test('matching line over 64KiB emits text-less placeholder and completes',
      () async {
    File('${fixture.path}/big_line.txt')
        .writeAsStringSync('${'x' * (70 * 1024)} target\n');
    final matches = await engine()
        .search(fixture.path, const TpSearchOptions(pattern: 'target'))
        .toList();
    final m = matches.singleWhere((m) => m.relativePath == 'big_line.txt');
    expect(m.lineNumber, 1);
    expect(m.lineText, '');
    expect(m.matchStart, 0);
    expect(m.matchEnd, 0);
  });

  test('matching line over 1MB emits text-less placeholder with line number',
      () async {
    File('${fixture.path}/huge_line.txt')
        .writeAsStringSync('start${'x' * (1024 * 1024 + 64)} target\n');
    final matches = await engine()
        .search(fixture.path, const TpSearchOptions(pattern: 'target'))
        .toList();
    final m = matches.singleWhere((m) => m.relativePath == 'huge_line.txt');
    expect(m.lineNumber, 1);
    expect(m.lineText, '');
    expect(m.matchStart, 0);
    expect(m.matchEnd, 0);
  });
}
