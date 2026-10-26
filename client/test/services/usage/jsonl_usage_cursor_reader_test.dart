import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/usage/jsonl_usage_cursor_reader.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;

  setUp(() {
    fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  });

  // ASCII only: InMemoryFilesystem stores text as UTF-16 code units, which is
  // byte-identical to UTF-8 for these fixtures.
  Future<void> write(String text) => fs.writeString('/tp/a.jsonl', text);

  test('reads only complete lines and holds the partial tail', () async {
    await write('one\ntwo\npart');

    final first = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: null,
    );

    expect(first.lines, ['one', 'two']);
    expect(first.lineOffsets, [0, 4]);
    expect(first.partialTail, isTrue);
    expect(first.nextCursor.byteOffset, 8);
    expect(first.nextCursor.tailFingerprint, isNotNull);

    await fs.appendString('/tp/a.jsonl', 'ial\n');
    final second = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: first.nextCursor,
    );

    expect(second.lines, ['partial']);
    expect(second.lineOffsets, [8]);
    expect(second.partialTail, isFalse);
    expect(second.nextCursor.byteOffset, 16);
  });

  test('returns nothing when the file has not grown', () async {
    await write('one\n');
    final first = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: null,
    );
    final second = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: first.nextCursor,
    );

    expect(second.lines, isEmpty);
    expect(second.partialTail, isFalse);
    expect(second.nextCursor.byteOffset, first.nextCursor.byteOffset);
  });

  test('pins to EOF when a rewrite changes the tail fingerprint', () async {
    await write('aaaa\n');
    final first = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: null,
    );

    await write('bbbb\n');
    final second = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: first.nextCursor,
    );

    expect(second.pinnedToEof, isTrue);
    expect(second.lines, isEmpty);
    expect(second.nextCursor.byteOffset, 5);
  });

  test('pins to EOF when the file shrinks below the cursor', () async {
    await write('one\ntwo\n');
    final first = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: null,
    );

    await write('x');
    final second = await readJsonlUsageWindow(
      fs: fs,
      path: '/tp/a.jsonl',
      cursor: first.nextCursor,
    );

    expect(second.pinnedToEof, isTrue);
    expect(second.lines, isEmpty);
    expect(second.nextCursor.byteOffset, 1);
  });
}
