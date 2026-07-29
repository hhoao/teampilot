import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/run/run_ui_prefs_store.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('missing file returns null selectedKey', () async {
    final fs = InMemoryFilesystem();
    final store = RunUiPrefsStore(fs: fs, pathOverride: '/ui/run-ui-prefs.json');
    expect(await store.selectedKeyFor('ws-1'), isNull);
  });

  test('round-trips selectedKey per workspaceId', () async {
    final fs = InMemoryFilesystem();
    final store = RunUiPrefsStore(fs: fs, pathOverride: '/ui/run-ui-prefs.json');
    await store.saveSelectedKey('ws-1', 'key-a');
    await store.saveSelectedKey('ws-2', 'key-b');
    expect(await store.selectedKeyFor('ws-1'), 'key-a');
    expect(await store.selectedKeyFor('ws-2'), 'key-b');
  });

  test('clearSelectedKey removes workspace entry', () async {
    final fs = InMemoryFilesystem();
    final store = RunUiPrefsStore(fs: fs, pathOverride: '/ui/run-ui-prefs.json');
    await store.saveSelectedKey('ws-1', 'key-a');
    await store.clearSelectedKey('ws-1');
    expect(await store.selectedKeyFor('ws-1'), isNull);
  });

  test('corrupt JSON is treated as empty', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/ui/run-ui-prefs.json', '{not-json');
    final store = RunUiPrefsStore(fs: fs, pathOverride: '/ui/run-ui-prefs.json');
    expect(await store.selectedKeyFor('ws-1'), isNull);
  });
}
