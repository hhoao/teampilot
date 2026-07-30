import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';

void main() {
  test('v1 catalog contains required command ids', () {
    final ids = CommandCatalog.v1.map((c) => c.id).toSet();
    expect(ids, containsAll([
      CommandIds.workspaceNextTab,
      CommandIds.workspaceSearch,
      CommandIds.stripNextTab,
      CommandIds.sessionCloseTab,
      CommandIds.zoomIn,
      CommandIds.composeSubmit,
      CommandIds.showCheatsheet,
      CommandIds.toggleSidebar,
      CommandIds.floatingToggle,
      CommandIds.floatingMaximize,
      CommandIds.floatingMinimize,
      CommandIds.floatingNewTerminal,
      CommandIds.floatingOpenFile,
    ]));
  });

  test('floating toggle defaults to Mod+Alt+A', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.floatingToggle,
    );
    expect(def.defaultChords, [
      KeyChord(key: 'a', mods: [KeyChordMod.mod, KeyChordMod.alt]),
    ]);
    expect(def.when, ShortcutWhen.hasWorkspace);
    expect(def.terminalPassthrough, isTrue);
  });

  test('floating maximize default is macOS-only Mod+Alt+Shift+A', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.floatingMaximize,
    );
    if (defaultIsMacOS()) {
      expect(def.defaultChords, [
        KeyChord(
          key: 'a',
          mods: [KeyChordMod.mod, KeyChordMod.alt, KeyChordMod.shift],
        ),
      ]);
    } else {
      expect(def.defaultChords, isEmpty);
    }
  });

  test('floating minimize / newTerminal / openFile ship unbound', () {
    for (final id in [
      CommandIds.floatingMinimize,
      CommandIds.floatingNewTerminal,
      CommandIds.floatingOpenFile,
    ]) {
      final def = CommandCatalog.v1.singleWhere((c) => c.id == id);
      expect(def.defaultChords, isEmpty, reason: id);
    }
  });

  test('workspace search defaults to Mod+F and double Shift', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.workspaceSearch,
    );
    expect(def.defaultChords, [
      KeyChord(key: 'f', mods: [KeyChordMod.mod]),
      KeyChord.doubleTapShift(),
    ]);
    expect(def.when, ShortcutWhen.hasWorkspace);
    expect(def.terminalPassthrough, isTrue);
  });

  test('strip next tab defaults to explicit ctrl+tab', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.stripNextTab,
    );
    expect(def.defaultChords, [
      KeyChord(key: 'tab', mods: [KeyChordMod.ctrl]),
    ]);
    expect(def.terminalPassthrough, isTrue);
  });

  test('compose submit is unmodified enter, not passthrough', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.composeSubmit,
    );
    expect(def.defaultChords, [KeyChord(key: 'enter')]);
    expect(def.terminalPassthrough, isFalse);
    expect(def.when, ShortcutWhen.inCompose);
  });

  test('Alt+1…9 / Alt+0 focus strip tabs by ordinal', () {
    for (var n = 1; n <= 10; n++) {
      final def = CommandCatalog.v1.singleWhere(
        (c) => c.id == CommandIds.stripFocusTab(n),
      );
      expect(
        def.defaultChords,
        [
          KeyChord(
            key: n == 10 ? 'digit0' : 'digit$n',
            mods: [KeyChordMod.alt],
          ),
        ],
      );
      expect(def.when, ShortcutWhen.hasWorkspace);
      expect(def.terminalPassthrough, isTrue);
    }
  });
}
