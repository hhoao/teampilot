import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/keybinding_resolver.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.enter => PhysicalKeyboardKey.enter,
    LogicalKeyboardKey.tab => PhysicalKeyboardKey.tab,
    LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.shiftLeft => PhysicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.metaLeft => PhysicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.keyW => PhysicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyK => PhysicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyN => PhysicalKeyboardKey.keyN,
    LogicalKeyboardKey.keyF => PhysicalKeyboardKey.keyF,
    LogicalKeyboardKey.escape => PhysicalKeyboardKey.escape,
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
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(key)) {
        releaseModifier(key);
      }
    }
  });

  group('KeybindingResolver.effectiveBindings', () {
    final catalog = [
      CommandDefinition(
        id: 'test.a',
        category: CommandCategory.meta,
        defaultChords: [KeyChord(key: 'a', mods: [KeyChordMod.mod])],
        when: ShortcutWhen.always,
        terminalPassthrough: true,
        titleL10nKey: 'x',
      ),
    ];

    test('missing override falls back to default chords', () {
      final effective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {},
      );

      expect(effective['test.a'], catalog.single.defaultChords);
    });

    test('explicit empty override means unbound', () {
      final effective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {'test.a': []},
      );

      expect(effective['test.a'], isEmpty);
    });

    test('non-empty override replaces the default', () {
      final overrideChord = KeyChord(key: 'b', mods: [KeyChordMod.mod]);
      final effective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {
          'test.a': [overrideChord],
        },
      );

      expect(effective['test.a'], [overrideChord]);
    });
  });

  group('KeybindingResolver.match', () {
    late Map<String, List<KeyChord>> effective;

    setUp(() {
      effective = KeybindingResolver.effectiveBindings(
        catalog: CommandCatalog.v1,
        overrides: {},
      );
    });

    test('Ctrl+Tab matches stripNextTab when hasWorkspace', () {
      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.tab),
        effectiveByCommand: effective,
        context: const ShortcutContext(hasWorkspace: true),
        isMacOS: false,
      );

      expect(result, CommandIds.stripNextTab);
    });

    test('ignored when `when` is unsatisfied', () {
      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.tab),
        effectiveByCommand: effective,
        context: const ShortcutContext(),
        isMacOS: false,
      );

      expect(result, isNull);
    });

    test(
      'ignored when inTerminal and terminalPassthrough is false',
      () {
        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.enter),
          effectiveByCommand: effective,
          context: const ShortcutContext(inTerminal: true, inCompose: true),
          isMacOS: false,
        );

        expect(result, isNull);
      },
    );

    test('allowed when inTerminal and terminalPassthrough is true', () {
      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.tab),
        effectiveByCommand: effective,
        context: const ShortcutContext(hasWorkspace: true, inTerminal: true),
        isMacOS: false,
      );

      expect(result, CommandIds.stripNextTab);
    });

    test('bare Enter is ignored when not inCompose', () {
      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.enter),
        effectiveByCommand: effective,
        context: const ShortcutContext(),
        isMacOS: false,
      );

      expect(result, isNull);
    });

    test('bare Enter matches composeSubmit when inCompose', () {
      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.enter),
        effectiveByCommand: effective,
        context: const ShortcutContext(inCompose: true),
        isMacOS: false,
      );

      expect(result, CommandIds.composeSubmit);
    });

    group('inTextInput', () {
      test('modifier chord still matches (Mod+W closes session tab)', () {
        pressModifier(LogicalKeyboardKey.metaLeft);
        addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.keyW),
          effectiveByCommand: effective,
          context: const ShortcutContext(
            inTextInput: true,
            hasSessionTab: true,
          ),
          isMacOS: true,
        );

        expect(result, CommandIds.sessionCloseTab);
      });

      test('unmodified key never matches, even with when: always', () {
        final catalog = [
          CommandDefinition(
            id: 'test.bareAlways',
            category: CommandCategory.meta,
            defaultChords: [KeyChord(key: 'k')],
            when: ShortcutWhen.always,
            terminalPassthrough: true,
            titleL10nKey: 'x',
          ),
        ];
        final bareEffective = KeybindingResolver.effectiveBindings(
          catalog: catalog,
          overrides: {},
        );

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.keyK),
          effectiveByCommand: bareEffective,
          context: const ShortcutContext(inTextInput: true),
          isMacOS: false,
          catalog: catalog,
        );

        expect(result, isNull);
      });

      test('compose Enter still matches when inTextInput and inCompose', () {
        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.enter),
          effectiveByCommand: effective,
          context: const ShortcutContext(inTextInput: true, inCompose: true),
          isMacOS: false,
        );

        expect(result, CommandIds.composeSubmit);
      });

      test('bare Escape matches floatingMinimize even in text input', () {
        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.escape),
          effectiveByCommand: effective,
          context: const ShortcutContext(
            floatingPanelOpen: true,
            inTextInput: true,
          ),
          isMacOS: false,
        );

        expect(result, CommandIds.floatingMinimize);
      });
    });

    test('Escape matches floatingMinimize when floatingPanelOpen', () {
      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.escape),
        effectiveByCommand: effective,
        context: const ShortcutContext(floatingPanelOpen: true),
        isMacOS: false,
      );

      expect(result, CommandIds.floatingMinimize);
    });

    test('Escape ignored when floating panel is not open', () {
      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.escape),
        effectiveByCommand: effective,
        context: const ShortcutContext(hasWorkspace: true),
        isMacOS: false,
      );

      expect(result, isNull);
    });

    test('Escape matches floatingMinimize while inTerminal', () {
      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.escape),
        effectiveByCommand: effective,
        context: const ShortcutContext(
          floatingPanelOpen: true,
          inTerminal: true,
        ),
        isMacOS: false,
      );

      expect(result, CommandIds.floatingMinimize);
    });

    test('duplicate chord across commands: first catalog order wins', () {
      final sharedChord = KeyChord(key: 'k', mods: [KeyChordMod.mod]);
      final catalog = [
        CommandDefinition(
          id: 'test.first',
          category: CommandCategory.meta,
          defaultChords: [sharedChord],
          when: ShortcutWhen.always,
          terminalPassthrough: true,
          titleL10nKey: 'x',
        ),
        CommandDefinition(
          id: 'test.second',
          category: CommandCategory.meta,
          defaultChords: [sharedChord],
          when: ShortcutWhen.always,
          terminalPassthrough: true,
          titleL10nKey: 'y',
        ),
      ];
      final dupEffective = KeybindingResolver.effectiveBindings(
        catalog: catalog,
        overrides: {},
      );

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final result = KeybindingResolver.match(
        event: keyDown(LogicalKeyboardKey.keyK),
        effectiveByCommand: dupEffective,
        context: const ShortcutContext(),
        isMacOS: true,
        catalog: catalog,
      );

      expect(result, 'test.first');
    });

    group('claimed chords suppress the global command', () {
      test('a claimed Mod+N does not fire sessionNewChat', () {
        pressModifier(LogicalKeyboardKey.controlLeft);
        addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.keyN),
          effectiveByCommand: effective,
          // Not const: KeyChord's factory is not const, so a claimed-chords
          // set cannot live in a const expression.
          context: ShortcutContext(
            hasWorkspace: true,
            claimedChords: {KeyChord(key: 'n', mods: [KeyChordMod.mod])},
          ),
          isMacOS: false,
        );

        expect(result, isNull);
      });

      test('an unclaimed Mod+N still fires sessionNewChat', () {
        pressModifier(LogicalKeyboardKey.controlLeft);
        addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

        final result = KeybindingResolver.match(
          event: keyDown(LogicalKeyboardKey.keyN),
          effectiveByCommand: effective,
          context: const ShortcutContext(hasWorkspace: true),
          isMacOS: false,
        );

        expect(result, CommandIds.sessionNewChat);
      });
    });
  });

  group('KeybindingResolver.findConflicts', () {
    test('returns pairs sharing a chord', () {
      final sharedChord = KeyChord(key: 'k', mods: [KeyChordMod.mod]);
      final conflicts = KeybindingResolver.findConflicts({
        'a': [sharedChord],
        'b': [sharedChord],
        'c': [KeyChord(key: 'l')],
      });

      expect(conflicts, hasLength(1));
      expect(conflicts.single.chord, sharedChord);
      expect(conflicts.single.commandIds, unorderedEquals(['a', 'b']));
    });

    test('returns empty list when no chords are shared', () {
      final conflicts = KeybindingResolver.findConflicts({
        'a': [KeyChord(key: 'k', mods: [KeyChordMod.mod])],
        'b': [KeyChord(key: 'l')],
      });

      expect(conflicts, isEmpty);
    });
  });
}
