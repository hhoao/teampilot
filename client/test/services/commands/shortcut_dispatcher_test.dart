import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/keybinding_resolver.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';
import 'package:teampilot/services/commands/shortcut_dispatcher.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.keyF => PhysicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyK => PhysicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyN => PhysicalKeyboardKey.keyN,
    LogicalKeyboardKey.keyZ => PhysicalKeyboardKey.keyZ,
    LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft => PhysicalKeyboardKey.metaLeft,
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
    if (HardwareKeyboard.instance.isLogicalKeyPressed(
      LogicalKeyboardKey.metaLeft,
    )) {
      releaseModifier(LogicalKeyboardKey.metaLeft);
    }
  });

  final testCommandId = 'test.command';
  final testCatalog = [
    CommandDefinition(
      id: testCommandId,
      category: CommandCategory.meta,
      defaultChords: [KeyChord(key: 'k', mods: [KeyChordMod.mod])],
      when: ShortcutWhen.always,
      terminalPassthrough: true,
      titleL10nKey: 'x',
    ),
  ];

  ShortcutDispatcher buildDispatcher(CommandBus bus) {
    return ShortcutDispatcher(
      bus: bus,
      effectiveChords: (commandId) => testCatalog
          .firstWhere((def) => def.id == commandId)
          .defaultChords,
      context: () => const ShortcutContext(),
      isMacOS: () => true,
      catalog: testCatalog,
    );
  }

  group('ShortcutDispatcher.handle', () {
    test('match invokes the registered handler and returns true', () {
      final bus = CommandBus();
      var called = false;
      bus.register(testCommandId, () => called = true);
      final dispatcher = buildDispatcher(bus);

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyK));

      expect(handled, isTrue);
      expect(called, isTrue);
    });

    test('match with no registered handler still returns true', () {
      final bus = CommandBus();
      final dispatcher = buildDispatcher(bus);

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyK));

      expect(handled, isTrue);
    });

    test('disabled dispatcher returns false without invoking the bus', () {
      final bus = CommandBus();
      var called = false;
      bus.register(testCommandId, () => called = true);
      final dispatcher = buildDispatcher(bus)..enabled = false;

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyK));

      expect(handled, isFalse);
      expect(called, isFalse);
    });

    test('no chord match returns false', () {
      final bus = CommandBus();
      final dispatcher = buildDispatcher(bus);

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyZ));

      expect(handled, isFalse);
    });

    test('non-KeyDownEvent returns false', () {
      final bus = CommandBus();
      final dispatcher = buildDispatcher(bus);

      pressModifier(LogicalKeyboardKey.metaLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.metaLeft));

      final handled = dispatcher.handle(keyUp(LogicalKeyboardKey.keyK));

      expect(handled, isFalse);
    });
  });

  group('ShortcutDispatcher with real v1 catalog', () {
    ShortcutDispatcher buildV1Dispatcher(CommandBus bus, ShortcutContext context) {
      return ShortcutDispatcher(
        bus: bus,
        effectiveChords: (commandId) => KeybindingResolver.effectiveBindings(
          catalog: CommandCatalog.v1,
          overrides: {},
        )[commandId]!,
        context: () => context,
        isMacOS: () => false,
        catalog: CommandCatalog.v1,
      );
    }

    test('Ctrl+N in a workspace invokes sessionNewChat', () {
      final bus = CommandBus();
      String? invoked;
      bus.register(CommandIds.sessionNewChat, () {
        invoked = CommandIds.sessionNewChat;
      });
      final dispatcher = buildV1Dispatcher(
        bus,
        const ShortcutContext(hasWorkspace: true),
      );

      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyN));

      expect(handled, isTrue);
      expect(invoked, CommandIds.sessionNewChat);
    });

    test('Ctrl+N is not matched without an open workspace', () {
      final bus = CommandBus();
      var called = false;
      bus.register(CommandIds.sessionNewChat, () => called = true);
      final dispatcher = buildV1Dispatcher(bus, const ShortcutContext());

      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyN));

      expect(handled, isFalse);
      expect(called, isFalse);
    });
  });

  group('ShortcutDispatcher double Shift', () {
    final searchId = 'workbench.workspace.search';
    final searchCatalog = [
      CommandDefinition(
        id: searchId,
        category: CommandCategory.navigation,
        defaultChords: [
          KeyChord.doubleTapShift(),
        ],
        when: ShortcutWhen.hasWorkspace,
        terminalPassthrough: true,
        titleL10nKey: 'x',
      ),
    ];

    test('double Shift invokes the bound command when hasWorkspace', () {
      final bus = CommandBus();
      var called = false;
      bus.register(searchId, () => called = true);
      final dispatcher = ShortcutDispatcher(
        bus: bus,
        effectiveChords: (id) => searchCatalog
            .firstWhere((def) => def.id == id)
            .defaultChords,
        context: () => const ShortcutContext(hasWorkspace: true),
        isMacOS: () => false,
        catalog: searchCatalog,
      );

      final first = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        logicalKey: LogicalKeyboardKey.shiftLeft,
        timeStamp: Duration.zero,
      );
      final second = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.shiftLeft,
        logicalKey: LogicalKeyboardKey.shiftLeft,
        timeStamp: const Duration(milliseconds: 150),
      );

      expect(dispatcher.handle(first), isFalse);
      expect(dispatcher.handle(second), isTrue);
      expect(called, isTrue);
    });

    test('double Shift is ignored without hasWorkspace', () {
      final bus = CommandBus();
      var called = false;
      bus.register(searchId, () => called = true);
      final dispatcher = ShortcutDispatcher(
        bus: bus,
        effectiveChords: (id) => searchCatalog
            .firstWhere((def) => def.id == id)
            .defaultChords,
        context: () => const ShortcutContext(),
        isMacOS: () => false,
        catalog: searchCatalog,
      );

      expect(
        dispatcher.handle(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.shiftLeft,
            logicalKey: LogicalKeyboardKey.shiftLeft,
            timeStamp: Duration.zero,
          ),
        ),
        isFalse,
      );
      expect(
        dispatcher.handle(
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.shiftLeft,
            logicalKey: LogicalKeyboardKey.shiftLeft,
            timeStamp: const Duration(milliseconds: 150),
          ),
        ),
        isFalse,
      );
      expect(called, isFalse);
    });

    test('Ctrl+F does not invoke workspace search (Mod+F is surface-owned)', () {
      final bus = CommandBus();
      var called = false;
      bus.register(searchId, () => called = true);
      final dispatcher = ShortcutDispatcher(
        bus: bus,
        effectiveChords: (id) => searchCatalog
            .firstWhere((def) => def.id == id)
            .defaultChords,
        context: () => const ShortcutContext(hasWorkspace: true),
        isMacOS: () => false,
        catalog: searchCatalog,
      );

      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.keyF));
      expect(handled, isFalse);
      expect(called, isFalse);
    });
  });
}
