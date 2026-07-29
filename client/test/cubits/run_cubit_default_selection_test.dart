import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/run_cubit.dart';
import 'package:teampilot/models/run/launch_config_document.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/run/run_ui_prefs_store.dart';
import 'package:teampilot/services/run/shell_script_launch_schema.dart';

import '../support/in_memory_filesystem.dart';
import 'run_cubit_test.dart' show FakeRunPlatform;

const _workspaceId = 'ws-test';
const _folder = WorkspaceFolder(path: '/proj');
const _prefsPath = '/ui/run-ui-prefs.json';

OwnedLaunchConfiguration _shellScriptConfig({
  String id = 'api',
  String name = 'api',
}) {
  return OwnedLaunchConfiguration(
    owner: _folder,
    configuration: LaunchConfiguration.fromJson(
      ShellScriptLaunchSchema.withDefaults({
        'id': id,
        'name': name,
        'type': ShellScriptLaunchSchema.typeName,
        'execute': 'scriptText',
        'scriptText': 'true',
        'executeInTerminal': false,
      }),
    ),
  );
}

OwnedLaunchCompound _compound(String id) => OwnedLaunchCompound(
  owner: _folder,
  compound: LaunchCompound(
    id: id,
    name: id,
    configurationIds: const [],
  ),
);

RunUiPrefsStore _prefsStore(InMemoryFilesystem fs) =>
    RunUiPrefsStore(fs: fs, pathOverride: _prefsPath);

RunCubit _cubit({
  required FakeRunPlatform platform,
  required RunUiPrefsStore prefsStore,
}) {
  return RunCubit(
    platform: platform,
    folders: const [_folder],
    workspaceId: _workspaceId,
    prefsStore: prefsStore,
  );
}

/// [FakeRunPlatform] that mutates [configurations] on delete (reload path).
class _MutableFakeRunPlatform extends FakeRunPlatform {
  _MutableFakeRunPlatform({required super.configurations});

  @override
  Future<void> deleteConfiguration({
    required WorkspaceFolder folder,
    required String id,
  }) async {
    configurations = [
      for (final config in configurations)
        if (!(config.owner == folder && config.configId == id)) config,
    ];
  }
}

void main() {
  test('load with no prefs selects first configuration and writes prefs', () async {
    final fs = InMemoryFilesystem();
    final prefs = _prefsStore(fs);
    final a = _shellScriptConfig(id: 'a');
    final b = _shellScriptConfig(id: 'b');
    final platform = FakeRunPlatform(configurations: [a, b]);
    final cubit = _cubit(platform: platform, prefsStore: prefs);

    await cubit.load();

    expect(cubit.state.selectedKey, a.selectionKey);
    expect(await prefs.selectedKeyFor(_workspaceId), a.selectionKey);
    await cubit.close();
  });

  test('load restores persisted selection key', () async {
    final fs = InMemoryFilesystem();
    final prefs = _prefsStore(fs);
    final a = _shellScriptConfig(id: 'a');
    final b = _shellScriptConfig(id: 'b');
    await prefs.saveSelectedKey(_workspaceId, b.selectionKey);
    final platform = FakeRunPlatform(configurations: [a, b]);
    final cubit = _cubit(platform: platform, prefsStore: prefs);

    await cubit.load();

    expect(cubit.state.selectedKey, b.selectionKey);
    await cubit.close();
  });

  test('load with stale prefs selects first config and rewrites prefs', () async {
    final fs = InMemoryFilesystem();
    final prefs = _prefsStore(fs);
    final a = _shellScriptConfig(id: 'a');
    await prefs.saveSelectedKey(_workspaceId, 'stale-key');
    final platform = FakeRunPlatform(configurations: [a]);
    final cubit = _cubit(platform: platform, prefsStore: prefs);

    await cubit.load();

    expect(cubit.state.selectedKey, a.selectionKey);
    expect(await prefs.selectedKeyFor(_workspaceId), a.selectionKey);
    await cubit.close();
  });

  test('load with only compounds selects first compound', () async {
    final fs = InMemoryFilesystem();
    final prefs = _prefsStore(fs);
    final compound = _compound('all');
    final platform = FakeRunPlatform(
      configurations: const [],
      compounds: [compound],
    );
    final cubit = _cubit(platform: platform, prefsStore: prefs);

    await cubit.load();

    expect(cubit.state.selectedKey, compound.selectionKey);
    expect(await prefs.selectedKeyFor(_workspaceId), compound.selectionKey);
    await cubit.close();
  });

  test('load with empty configs and compounds clears selection and prefs', () async {
    final fs = InMemoryFilesystem();
    final prefs = _prefsStore(fs);
    await prefs.saveSelectedKey(_workspaceId, 'orphan');
    final platform = FakeRunPlatform(configurations: const [], compounds: const []);
    final cubit = _cubit(platform: platform, prefsStore: prefs);

    await cubit.load();

    expect(cubit.state.selectedKey, isNull);
    expect(await prefs.selectedKeyFor(_workspaceId), isNull);
    await cubit.close();
  });

  test('select writes prefs for configuration', () async {
    final fs = InMemoryFilesystem();
    final prefs = _prefsStore(fs);
    final a = _shellScriptConfig(id: 'a');
    final b = _shellScriptConfig(id: 'b');
    final platform = FakeRunPlatform(configurations: [a, b]);
    final cubit = _cubit(platform: platform, prefsStore: prefs);
    await cubit.load();

    await cubit.select(b.selectionKey);

    expect(cubit.state.selectedKey, b.selectionKey);
    expect(await prefs.selectedKeyFor(_workspaceId), b.selectionKey);
    await cubit.close();
  });

  test(
    'delete selected config when another remains falls back to remaining',
    () async {
      final fs = InMemoryFilesystem();
      final prefs = _prefsStore(fs);
      final platform = _MutableFakeRunPlatform(
        configurations: [
          _shellScriptConfig(id: 'a'),
          _shellScriptConfig(id: 'b'),
        ],
      );
      final cubit = RunCubit(
        platform: platform,
        folders: const [_folder],
        workspaceId: _workspaceId,
        prefsStore: prefs,
      );
      await cubit.load();
      final first = cubit.state.configurations.firstWhere((c) => c.configId == 'a');
      final second = cubit.state.configurations.firstWhere((c) => c.configId == 'b');
      await cubit.select(first.selectionKey);
      expect(await prefs.selectedKeyFor(_workspaceId), first.selectionKey);

      await cubit.deleteConfiguration(first);

      expect(cubit.state.configurations.map((c) => c.configId), ['b']);
      expect(cubit.state.selectedKey, second.selectionKey);
      expect(await prefs.selectedKeyFor(_workspaceId), second.selectionKey);
      await cubit.close();
    },
  );
}
