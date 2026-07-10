import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';
import 'package:teampilot/services/commands/shortcut_dispatcher.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.keyK => PhysicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyZ => PhysicalKeyboardKey.keyZ,
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
}
