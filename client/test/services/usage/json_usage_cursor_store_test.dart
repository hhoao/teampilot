import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/session_usage_capability.dart';
import 'package:teampilot/services/usage/json_usage_cursor_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late JsonUsageCursorStore store;

  setUp(() {
    fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    store = JsonUsageCursorStore(fs: fs, filePath: '/tp/usage/cursors.json');
  });

  test('round-trips cursors', () async {
    await store.save(
      'src',
      const UsageCursor(
        byteOffset: 12,
        size: 20,
        tailFingerprint: 99,
        lineOffset: 3,
        storeToken: 'baseline',
      ),
    );

    final loaded = await store.read('src');
    expect(loaded?.byteOffset, 12);
    expect(loaded?.size, 20);
    expect(loaded?.tailFingerprint, 99);
    expect(loaded?.lineOffset, 3);
    expect(loaded?.storeToken, 'baseline');
    expect(await store.read('missing'), isNull);
  });

  test('removes one cursor and preserves others', () async {
    await store.save('a', const UsageCursor(byteOffset: 1));
    await store.save('b', const UsageCursor(byteOffset: 2));

    await store.remove('a');

    expect(await store.read('a'), isNull);
    expect((await store.read('b'))?.byteOffset, 2);
  });

  test('prunes cursors that are no longer active', () async {
    await store.save('a', const UsageCursor(byteOffset: 1));
    await store.save('b', const UsageCursor(byteOffset: 2));
    await store.save('c', const UsageCursor(byteOffset: 3));

    final removed = await store.prune({'a', 'c'});

    expect(removed, 1);
    expect(await store.read('a'), isNotNull);
    expect(await store.read('b'), isNull);
    expect(await store.read('c'), isNotNull);
  });
}
