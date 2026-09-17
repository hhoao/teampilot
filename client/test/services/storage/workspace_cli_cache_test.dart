import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/storage/workspace_cli_cache.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  final cache = WorkspaceCliCache(
    layout: RuntimeLayout(teampilotRoot: '/tp', fs: InMemoryFilesystem()),
  );

  test('empty provider id is _shared', () {
    expect(WorkspaceCliCache.providerKey(null), '_shared');
    expect(WorkspaceCliCache.providerKey('  '), '_shared');
    expect(WorkspaceCliCache.providerKey('acct-1'), 'acct-1');
  });

  test('global cursor plugins cache is under workspace/cache', () {
    expect(
      cache.globalEntryPath(
        tool: CliTool.cursor.value,
        providerId: 'acct-1',
        cacheRel: WorkspaceCliCache.cursorPluginsCacheRel,
      ),
      '/tp/workspace/cache/cli/cursor/acct-1/plugins/cache',
    );
  });

  test('workspace tool rel for cursor plugins is fake-home path', () {
    final binding = WorkspaceCliCache.bindingFor(
      CliTool.cursor,
    ).singleWhere((b) => b.cacheRel == WorkspaceCliCache.cursorPluginsCacheRel);
    expect(binding.toolRel, 'home/.cursor/plugins/cache');
  });
}
