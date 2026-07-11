import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/keybinding_resolver.dart';
import 'package:teampilot/services/commands/terminal_passthrough_shortcuts.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.enter => PhysicalKeyboardKey.enter,
    LogicalKeyboardKey.tab => PhysicalKeyboardKey.tab,
    LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft => PhysicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.keyW => PhysicalKeyboardKey.keyW,
    _ => throw UnsupportedError('Add mapping for $logicalKey'),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  KeyDownEvent keyDown(LogicalKeyboardKey logicalKey) => KeyDownEvent(
    physicalKey: _physicalFor(logicalKey),
    logicalKey: logicalKey,
    timeStamp: Duration.zero,
  );

  KeyUpEvent keyUp(LogicalKeyboardKey logicalKey) => KeyUpEvent(
    physicalKey: _physicalFor(logicalKey),
    logicalKey: logicalKey,
    timeStamp: Duration.zero,
  );

  void pressModifier(LogicalKeyboardKey key) {
    HardwareKeyboard.instance.handleKeyEvent(keyDown(key));
  }

  void releaseModifier(LogicalKeyboardKey key) {
    HardwareKeyboard.instance.handleKeyEvent(keyUp(key));
  }

  tearDown(() {
    for (final key in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(key)) {
        releaseModifier(key);
      }
    }
  });

  /// [ShortcutActivator] has no value `==`, so overlay membership can only
  /// be asserted the same way `TerminalView._onKeyFallback` itself checks
  /// it: does any entry's activator `accept` this synthesized event.
  bool anyEntryAccepts(
    Map<ShortcutActivator, Intent> overlay,
    KeyEvent event,
  ) {
    return overlay.keys.any(
      (activator) => activator.accepts(event, HardwareKeyboard.instance),
    );
  }

  group('terminalPassthroughShortcutOverlay', () {
    test('claims a terminalPassthrough command chord (Ctrl+Tab)', () {
      final effective = KeybindingResolver.effectiveBindings(
        catalog: CommandCatalog.v1,
        overrides: {},
      );
      final overlay = terminalPassthroughShortcutOverlay(
        effectiveByCommand: effective,
        isMacOS: false,
      );

      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      expect(
        anyEntryAccepts(overlay, keyDown(LogicalKeyboardKey.tab)),
        isTrue,
        reason: 'sessionNextTab (Ctrl+Tab, terminalPassthrough: true)',
      );
    });

    test('does not claim a non-passthrough command chord (bare Enter)', () {
      final effective = KeybindingResolver.effectiveBindings(
        catalog: CommandCatalog.v1,
        overrides: {},
      );
      final overlay = terminalPassthroughShortcutOverlay(
        effectiveByCommand: effective,
        isMacOS: false,
      );

      expect(
        anyEntryAccepts(overlay, keyDown(LogicalKeyboardKey.enter)),
        isFalse,
        reason: 'composeSubmit (bare Enter) has terminalPassthrough: false',
      );
    });

    test('resolves `mod` chords per isMacOS (Mod+W)', () {
      final catalog = [
        CommandDefinition(
          id: CommandIds.sessionCloseTab,
          category: CommandCategory.tabs,
          defaultChords: [KeyChord(key: 'w', mods: [KeyChordMod.mod])],
          when: ShortcutWhen.hasSessionTab,
          terminalPassthrough: true,
          titleL10nKey: 'x',
        ),
      ];
      final effective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {},
      );

      final macOverlay = terminalPassthroughShortcutOverlay(
        effectiveByCommand: effective,
        isMacOS: true,
        catalog: catalog,
      );
      pressModifier(LogicalKeyboardKey.metaLeft);
      expect(
        anyEntryAccepts(macOverlay, keyDown(LogicalKeyboardKey.keyW)),
        isTrue,
        reason: 'mod resolves to Meta on macOS',
      );
      releaseModifier(LogicalKeyboardKey.metaLeft);

      final otherOverlay = terminalPassthroughShortcutOverlay(
        effectiveByCommand: effective,
        isMacOS: false,
        catalog: catalog,
      );
      pressModifier(LogicalKeyboardKey.controlLeft);
      expect(
        anyEntryAccepts(otherOverlay, keyDown(LogicalKeyboardKey.keyW)),
        isTrue,
        reason: 'mod resolves to Control off macOS',
      );
      releaseModifier(LogicalKeyboardKey.controlLeft);
    });

    test('an unbound (empty override) command contributes no activator', () {
      final catalog = [
        CommandDefinition(
          id: 'test.unbound',
          category: CommandCategory.meta,
          defaultChords: [KeyChord(key: 'w', mods: [KeyChordMod.mod])],
          when: ShortcutWhen.always,
          terminalPassthrough: true,
          titleL10nKey: 'x',
        ),
      ];
      final effective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {'test.unbound': []},
      );

      final overlay = terminalPassthroughShortcutOverlay(
        effectiveByCommand: effective,
        isMacOS: false,
        catalog: catalog,
      );

      expect(overlay, isEmpty);
    });
  });
}
