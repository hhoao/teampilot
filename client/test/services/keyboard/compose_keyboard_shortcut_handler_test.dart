import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/commands/command_catalog.dart';
import 'package:teampilot/services/commands/shortcut_context.dart';
import 'package:teampilot/services/commands/shortcut_dispatcher.dart';
import 'package:teampilot/services/keyboard/compose_keyboard_shortcut_handler.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.enter => PhysicalKeyboardKey.enter,
    LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
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

  void pressModifier(LogicalKeyboardKey key) {
    HardwareKeyboard.instance.handleKeyEvent(keyDown(key));
  }

  void releaseModifier(LogicalKeyboardKey key) {
    HardwareKeyboard.instance.handleKeyEvent(
      KeyUpEvent(
        physicalKey: _physicalFor(key),
        logicalKey: key,
        timeStamp: Duration.zero,
      ),
    );
  }

  tearDown(() {
    if (HardwareKeyboard.instance.isLogicalKeyPressed(
      LogicalKeyboardKey.controlLeft,
    )) {
      releaseModifier(LogicalKeyboardKey.controlLeft);
    }
  });

  test('insertNewlineAtSelection inserts at caret', () {
    final controller = TextEditingController(text: 'ab')
      ..selection = const TextSelection.collapsed(offset: 1);
    controller.value = insertNewlineAtSelection(controller);
    expect(controller.text, 'a\nb');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  ShortcutDispatcher buildComposeDispatcher(CommandBus bus) {
    return ShortcutDispatcher(
      bus: bus,
      effectiveChords: (commandId) => CommandCatalog.v1
          .firstWhere((def) => def.id == commandId)
          .defaultChords,
      context: () =>
          const ShortcutContext(inCompose: true, inTextInput: true),
      isMacOS: () => false,
    );
  }

  group('ComposeCommandBindings.register', () {
    test(
      'Enter submits when canSubmit is true and context is inCompose',
      () {
        final bus = CommandBus();
        final controller = TextEditingController(text: 'hello');
        var submitted = false;
        final unregister = ComposeCommandBindings.register(
          bus: bus,
          controller: controller,
          onSubmit: () => submitted = true,
          canSubmit: () => true,
        );
        final dispatcher = buildComposeDispatcher(bus);

        final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.enter));

        expect(handled, isTrue);
        expect(submitted, isTrue);
        unregister();
      },
    );

    test('Enter does not submit when canSubmit is false', () {
      final bus = CommandBus();
      final controller = TextEditingController(text: 'hello');
      var submitted = false;
      final unregister = ComposeCommandBindings.register(
        bus: bus,
        controller: controller,
        onSubmit: () => submitted = true,
        canSubmit: () => false,
      );
      final dispatcher = buildComposeDispatcher(bus);

      dispatcher.handle(keyDown(LogicalKeyboardKey.enter));

      expect(submitted, isFalse);
      unregister();
    });

    test('Ctrl+Enter inserts a newline instead of submitting', () {
      final bus = CommandBus();
      final controller = TextEditingController(text: 'hi');
      var submitted = false;
      final unregister = ComposeCommandBindings.register(
        bus: bus,
        controller: controller,
        onSubmit: () => submitted = true,
        canSubmit: () => true,
      );
      final dispatcher = buildComposeDispatcher(bus);

      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      dispatcher.handle(keyDown(LogicalKeyboardKey.enter));

      expect(submitted, isFalse);
      expect(controller.text, 'hi\n');
      unregister();
    });

    test('unregistering stops Enter from submitting', () {
      final bus = CommandBus();
      final controller = TextEditingController(text: 'hello');
      var submitted = false;
      final unregister = ComposeCommandBindings.register(
        bus: bus,
        controller: controller,
        onSubmit: () => submitted = true,
        canSubmit: () => true,
      );
      final dispatcher = buildComposeDispatcher(bus);
      unregister();

      final handled = dispatcher.handle(keyDown(LogicalKeyboardKey.enter));

      // Still "handled" (dispatcher matches the command regardless of a
      // registered handler) but nothing fires since the handler is gone.
      expect(handled, isTrue);
      expect(submitted, isFalse);
    });
  });
}
