import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/keybinding_repository.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  String keybindingsPath() =>
      p.join(AppStorage.appDataRoot, 'keybindings.json');

  test('load returns empty overrides when the file is missing', () async {
    final repo = KeybindingRepository();

    final overrides = await repo.load();

    expect(overrides, isEmpty);
  });

  test('save then load round-trips overrides', () async {
    final repo = KeybindingRepository();
    final saved = {
      CommandIds.workspaceCloseTab: [
        KeyChord(key: 'w', mods: [KeyChordMod.mod, KeyChordMod.shift]),
      ],
      CommandIds.zoomIn: const <KeyChord>[],
    };

    await repo.save(saved);
    final loaded = await repo.load();

    expect(loaded, saved);
  });

  test('load drops unknown command ids', () async {
    final repo = KeybindingRepository();
    final path = keybindingsPath();
    await Directory(p.dirname(path)).create(recursive: true);
    await File(path).writeAsString(
      jsonEncode({
        'version': 1,
        'bindings': {
          'not.a.real.command': [
            {'key': 'w', 'mods': ['mod']},
          ],
          CommandIds.workspaceCloseTab: [
            {'key': 'w', 'mods': ['mod', 'shift']},
          ],
        },
      }),
    );

    final loaded = await repo.load();

    expect(loaded.keys, [CommandIds.workspaceCloseTab]);
  });

  test('save writes to {appDataRoot}/keybindings.json', () async {
    final repo = KeybindingRepository();

    await repo.save({
      CommandIds.zoomReset: [
        KeyChord(key: 'digit0', mods: [KeyChordMod.mod]),
      ],
    });

    expect(await File(keybindingsPath()).exists(), isTrue);
  });

  test('on-disk JSON matches the documented shape', () async {
    final repo = KeybindingRepository();

    await repo.save({
      CommandIds.workspaceCloseTab: [
        KeyChord(key: 'w', mods: [KeyChordMod.mod]),
      ],
    });

    final raw = await File(keybindingsPath()).readAsString();
    final decoded = jsonDecode(raw);

    expect(decoded, {
      'version': 1,
      'bindings': {
        CommandIds.workspaceCloseTab: [
          {'key': 'w', 'mods': ['mod']},
        ],
      },
    });
  });

  test('save with an empty chord list persists intentional unbind', () async {
    final repo = KeybindingRepository();

    await repo.save({CommandIds.zoomIn: const []});
    final raw = await File(keybindingsPath()).readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    expect(decoded['bindings'][CommandIds.zoomIn], isEmpty);

    final loaded = await repo.load();
    expect(loaded[CommandIds.zoomIn], isEmpty);
  });
}
