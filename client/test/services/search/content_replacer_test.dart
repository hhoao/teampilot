import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_replacer.dart';

void main() {
  late Directory dir;
  late LocalFilesystem fs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tp_replacer_');
    fs = LocalFilesystem();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  TpSearchMatch match(String path, int line, String text, int start, int end,
          {String rel = 'f.txt'}) =>
      TpSearchMatch(
        path: path,
        relativePath: rel,
        lineNumber: line,
        lineText: text,
        matchStart: start,
        matchEnd: end,
      );

  test('replaces multiple matches across lines', () async {
    final f = File('${dir.path}/f.txt')
      ..writeAsStringSync('aa bb aa\ncc aa\n');
    final replacer = ContentReplacer(fs: fs);
    final n = await replacer.replaceAllInFile(
      path: f.path,
      matches: [
        match(f.path, 1, 'aa bb aa\n', 0, 2),
        match(f.path, 1, 'aa bb aa\n', 6, 8),
        match(f.path, 2, 'cc aa\n', 3, 5),
      ],
      replacement: 'X',
    );
    expect(n, 3);
    expect(f.readAsStringSync(), 'X bb X\ncc X\n');
  });

  test('handles CRLF line endings', () async {
    final f = File('${dir.path}/crlf.txt')
      ..writeAsStringSync('aa bb\r\naa cc\r\n');
    final replacer = ContentReplacer(fs: fs);
    await replacer.replaceAllInFile(
      path: f.path,
      matches: [match(f.path, 1, 'aa bb\r\n', 0, 2)],
      replacement: 'X',
    );
    expect(f.readAsStringSync(), 'X bb\r\naa cc\r\n');
  });

  test('replacements apply bottom-up so offsets stay valid', () async {
    final f = File('${dir.path}/adj.txt')..writeAsStringSync('aaaa\n');
    final replacer = ContentReplacer(fs: fs);
    await replacer.replaceAllInFile(
      path: f.path,
      matches: [
        match(f.path, 1, 'aaaa\n', 0, 2),
        match(f.path, 1, 'aaaa\n', 2, 4),
      ],
      replacement: 'X',
    );
    expect(f.readAsStringSync(), 'XX\n');
  });

  test('line text with terminators aligns to file offsets', () async {
    // 第 2 行匹配：行首偏移 = 第一行长度(含 \n)。
    final f = File('${dir.path}/m.txt')..writeAsStringSync('first\nsecond\n');
    final replacer = ContentReplacer(fs: fs);
    await replacer.replaceAllInFile(
      path: f.path,
      matches: [match(f.path, 2, 'second\n', 0, 6)],
      replacement: 'S',
    );
    expect(f.readAsStringSync(), 'first\nS\n');
  });

  test('returns 0 and writes nothing when matches list is empty', () async {
    final f = File('${dir.path}/n.txt')..writeAsStringSync('keep me\n');
    final replacer = ContentReplacer(fs: fs);
    final n = await replacer.replaceAllInFile(
      path: f.path,
      matches: const [],
      replacement: 'X',
    );
    expect(n, 0);
    expect(f.readAsStringSync(), 'keep me\n');
  });
}
