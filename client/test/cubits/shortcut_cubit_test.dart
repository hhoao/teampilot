import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  ShortcutCubit cubit() => ShortcutCubit(repository: KeybindingRepository());

  test('starts with catalog defaults as effective after load', () async {
    final sut = cubit();
    addTearDown(sut.close);

    await sut.load();

    for (final def in CommandCatalog.v1) {
      expect(sut.effective[def.id], def.defaultChords);
    }
  });

  test('rebind persists and updates the effective chords', () async {
    final sut = cubit();
    addTearDown(sut.close);
    await sut.load();

    final chords = [KeyChord(key: 'k', mods: [KeyChordMod.mod])];
    await sut.rebind(CommandIds.workspaceCloseTab, chords);

    expect(sut.effective[CommandIds.workspaceCloseTab], chords);

    final reloaded = cubit();
    addTearDown(reloaded.close);
    await reloaded.load();
    expect(reloaded.effective[CommandIds.workspaceCloseTab], chords);
  });

  test('unbind stores an empty chord list', () async {
    final sut = cubit();
    addTearDown(sut.close);
    await sut.load();

    await sut.unbind(CommandIds.workspaceCloseTab);

    expect(sut.state.overrides[CommandIds.workspaceCloseTab], isEmpty);
    expect(sut.effective[CommandIds.workspaceCloseTab], isEmpty);
  });

  test('resetCommand removes the override key', () async {
    final sut = cubit();
    addTearDown(sut.close);
    await sut.load();

    await sut.rebind(CommandIds.workspaceCloseTab, [
      KeyChord(key: 'k', mods: [KeyChordMod.mod]),
    ]);
    expect(sut.state.overrides, contains(CommandIds.workspaceCloseTab));

    await sut.resetCommand(CommandIds.workspaceCloseTab);

    expect(sut.state.overrides, isNot(contains(CommandIds.workspaceCloseTab)));
    final defaultChords = CommandCatalog.v1
        .firstWhere((def) => def.id == CommandIds.workspaceCloseTab)
        .defaultChords;
    expect(sut.effective[CommandIds.workspaceCloseTab], defaultChords);
  });

  test('resetAll clears every override', () async {
    final sut = cubit();
    addTearDown(sut.close);
    await sut.load();

    await sut.rebind(CommandIds.workspaceCloseTab, [
      KeyChord(key: 'k', mods: [KeyChordMod.mod]),
    ]);
    await sut.unbind(CommandIds.zoomIn);

    await sut.resetAll();

    expect(sut.state.overrides, isEmpty);

    final reloaded = cubit();
    addTearDown(reloaded.close);
    await reloaded.load();
    expect(reloaded.state.overrides, isEmpty);
  });

  test('conflicts getter reflects the current effective map', () async {
    final sut = cubit();
    addTearDown(sut.close);
    await sut.load();

    expect(sut.conflicts, isEmpty);

    final defaultZoomInChord = CommandCatalog.v1
        .firstWhere((def) => def.id == CommandIds.zoomIn)
        .defaultChords
        .first;
    await sut.rebind(CommandIds.zoomOut, [defaultZoomInChord]);

    expect(sut.conflicts, isNotEmpty);
    expect(
      sut.conflicts.single.commandIds,
      unorderedEquals([CommandIds.zoomIn, CommandIds.zoomOut]),
    );
  });

  group('importOverrides', () {
    test('applies cleanly when there are no conflicts', () async {
      final sut = cubit();
      addTearDown(sut.close);
      await sut.load();

      final chords = [KeyChord(key: 'p', mods: [KeyChordMod.mod])];
      final result = await sut.importOverrides({
        CommandIds.showCheatsheet: chords,
      });

      expect(result.applied, isTrue);
      expect(result.conflicts, isEmpty);
      expect(sut.effective[CommandIds.showCheatsheet], chords);
    });

    test(
      'leaves state unchanged and reports conflicts when replaceConflicts is false',
      () async {
        final sut = cubit();
        addTearDown(sut.close);
        await sut.load();

        final zoomOutDefault = CommandCatalog.v1
            .firstWhere((def) => def.id == CommandIds.zoomOut)
            .defaultChords;
        final before = Map<String, List<KeyChord>>.from(sut.state.overrides);

        final result = await sut.importOverrides({
          CommandIds.zoomIn: zoomOutDefault,
        });

        expect(result.applied, isFalse);
        expect(result.conflicts, isNotEmpty);
        expect(sut.state.overrides, before);
        expect(
          sut.effective[CommandIds.zoomIn],
          CommandCatalog.v1
              .firstWhere((def) => def.id == CommandIds.zoomIn)
              .defaultChords,
        );
      },
    );

    test(
      'clears conflicting chords from other commands when replaceConflicts is true',
      () async {
        final sut = cubit();
        addTearDown(sut.close);
        await sut.load();

        final zoomOutDefault = CommandCatalog.v1
            .firstWhere((def) => def.id == CommandIds.zoomOut)
            .defaultChords;

        final result = await sut.importOverrides({
          CommandIds.zoomIn: zoomOutDefault,
        }, replaceConflicts: true);

        expect(result.applied, isTrue);
        expect(result.conflicts, isNotEmpty);
        expect(sut.effective[CommandIds.zoomIn], zoomOutDefault);
        for (final chord in zoomOutDefault) {
          expect(sut.effective[CommandIds.zoomOut], isNot(contains(chord)));
        }
        expect(sut.conflicts, isEmpty);
      },
    );
  });
}
