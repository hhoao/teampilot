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
      CommandIds.sessionNextTab,
      CommandIds.sessionCloseTab,
      CommandIds.zoomIn,
      CommandIds.composeSubmit,
      CommandIds.showCheatsheet,
      CommandIds.toggleSidebar,
    ]));
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

  test('session next tab defaults to explicit ctrl+tab', () {
    final def = CommandCatalog.v1.singleWhere(
      (c) => c.id == CommandIds.sessionNextTab,
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

  test('Alt+1…9 / Alt+0 focus session tabs by ordinal', () {
    for (var n = 1; n <= 10; n++) {
      final def = CommandCatalog.v1.singleWhere(
        (c) => c.id == CommandIds.sessionFocusTab(n),
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
