import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_config_document.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/run/launch_config_store.dart';

void main() {
  late MemoryLaunchConfigIo memoryIo;
  late LaunchConfigStore store;
  late WorkspaceFolder folderA;
  late WorkspaceFolder folderB;

  setUp(() {
    memoryIo = MemoryLaunchConfigIo();
    store = LaunchConfigStore(io: memoryIo);
    folderA = const WorkspaceFolder(path: '/proj/a');
    folderB = const WorkspaceFolder(path: '/proj/b');
  });

  Future<void> writeLaunchJson(
    WorkspaceFolder folder,
    Map<String, Object?> json,
  ) {
    final path = LaunchConfigStore.launchConfigPath(folder);
    return memoryIo.writeString(
      path,
      jsonEncode(json),
      targetId: folder.targetId,
    );
  }

  test('merges configs from multiple folders with owner tags', () async {
    await writeLaunchJson(folderA, {
      'version': 1,
      'configurations': [
        {'id': 'main', 'name': 'Main A', 'type': 'shellScript', 'execute': 'scriptText', 'scriptText': 'a'},
      ],
    });
    await writeLaunchJson(folderB, {
      'version': 1,
      'configurations': [
        {'id': 'main', 'name': 'Main B', 'type': 'shellScript', 'execute': 'scriptText', 'scriptText': 'b'},
      ],
    });

    final list = await store.listConfigurations(folders: [folderA, folderB]);
    expect(list, hasLength(2));
    expect(list.map((e) => e.selectionKey).toSet(), hasLength(2));
    expect(list.map((e) => e.owner.path).toSet(), {'/proj/a', '/proj/b'});
  });

  test('compound refs resolve only within same file', () async {
    await writeLaunchJson(folderA, {
      'version': 1,
      'configurations': [
        {'id': 'a', 'name': 'A', 'type': 'shellScript', 'execute': 'scriptText', 'scriptText': 'a'},
        {'id': 'b', 'name': 'B', 'type': 'shellScript', 'execute': 'scriptText', 'scriptText': 'b'},
      ],
      'compounds': [
        {
          'id': 'both',
          'name': 'Both',
          'configurations': ['a', 'b'],
        },
      ],
    });

    final compounds = await store.listCompounds(folders: [folderA]);
    expect(compounds, hasLength(1));
    expect(compounds.single.compound.configurationIds, ['a', 'b']);
    expect(compounds.single.owner, folderA);
  });

  test('missing launch.json yields empty lists', () async {
    expect(
      await store.listConfigurations(folders: [folderA]),
      isEmpty,
    );
    expect(await store.listCompounds(folders: [folderA]), isEmpty);
  });

  test('upsertConfiguration writes and updates by id', () async {
    const config = LaunchConfiguration(
      id: 'api',
      name: 'API',
      type: 'shellScript',
      extras: {
        'execute': 'scriptText',
        'scriptText': 'npm run dev',
      },
    );

    await store.upsertConfiguration(folder: folderA, configuration: config);
    final listed = await store.listConfigurations(folders: [folderA]);
    expect(listed.single.configuration, config);

    final updated = config.copyWith(
      extras: {
        'execute': 'scriptText',
        'scriptText': 'pnpm run dev',
      },
    );
    await store.upsertConfiguration(folder: folderA, configuration: updated);
    final relisted = await store.listConfigurations(folders: [folderA]);
    expect(relisted, hasLength(1));
    expect(relisted.single.configuration.extras['scriptText'], 'pnpm run dev');
  });

  test('writeDocument round-trips full document', () async {
    const doc = LaunchConfigDocument(
      version: 1,
      configurations: [
        LaunchConfiguration(
          id: 'one',
          name: 'One',
          type: 'shellScript',
          extras: {
            'execute': 'scriptText',
            'scriptText': 'true',
          },
        ),
      ],
      compounds: [
        LaunchCompound(id: 'pair', name: 'Pair', configurationIds: ['one']),
      ],
    );

    await store.writeDocument(folder: folderA, document: doc);
    final path = LaunchConfigStore.launchConfigPath(folderA);
    final raw = await memoryIo.readString(path, targetId: folderA.targetId);
    expect(raw, isNotNull);

    final parsed = LaunchConfigDocument.fromJson(
      jsonDecode(raw!) as Map<String, Object?>,
    );
    expect(parsed.version, 1);
    expect(parsed.configurations.single.id, 'one');
    expect(parsed.configurations.single.type, 'shellScript');
    expect(parsed.compounds.single.configurationIds, ['one']);
  });

  test('deleteConfiguration removes id and writes document', () async {
    final io = MemoryLaunchConfigIo();
    final store = LaunchConfigStore(io: io);
    const folder = WorkspaceFolder(path: '/proj');
    await store.upsertConfiguration(
      folder: folder,
      configuration: const LaunchConfiguration(
        id: 'api',
        name: 'API',
        type: 'shellScript',
        extras: {
          'execute': 'scriptText',
          'scriptText': 'echo',
        },
      ),
    );
    await store.deleteConfiguration(folder: folder, id: 'api');
    final remaining = await store.listConfigurations(folders: [folder]);
    expect(remaining, isEmpty);
  });

  test('selectionKey includes path targetId and config id', () {
    const owned = OwnedLaunchConfiguration(
      owner: WorkspaceFolder(path: '/x', targetId: 'ssh:host'),
      configuration: LaunchConfiguration(
        id: 'run',
        name: 'Run',
        type: 'shellScript',
      ),
    );
    expect(
      owned.selectionKey,
      'ssh:host|/x|run',
    );
  });
}
