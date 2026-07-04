import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('insertNewlineAtSelection inserts at caret', () {
    final controller = TextEditingController(text: 'ab')
      ..selection = const TextSelection.collapsed(offset: 1);
    controller.value = insertNewlineAtSelection(controller);
    expect(controller.text, 'a\nb');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  test('Enter submits when canSubmit is true', () {
    final controller = TextEditingController(text: 'hello');
    var submitted = false;
    final handler = ComposeKeyboardShortcutHandler(
      controller: controller,
      onSubmit: () => submitted = true,
      canSubmit: () => true,
    );
    final focusNode = FocusNode();

    final result = handler.handle(focusNode, keyDown(LogicalKeyboardKey.enter));

    expect(result, KeyEventResult.handled);
    expect(submitted, isTrue);
    focusNode.dispose();
  });

  test('Enter does not submit when canSubmit is false', () {
    final controller = TextEditingController(text: 'hello');
    var submitted = false;
    final handler = ComposeKeyboardShortcutHandler(
      controller: controller,
      onSubmit: () => submitted = true,
      canSubmit: () => false,
    );
    final focusNode = FocusNode();

    handler.handle(focusNode, keyDown(LogicalKeyboardKey.enter));

    expect(submitted, isFalse);
    focusNode.dispose();
  });

  test('Ctrl+Enter inserts newline instead of submitting', () {
    final controller = TextEditingController(text: 'hi');
    var submitted = false;
    final handler = ComposeKeyboardShortcutHandler(
      controller: controller,
      onSubmit: () => submitted = true,
      canSubmit: () => true,
    );
    final focusNode = FocusNode();

    HardwareKeyboard.instance.handleKeyEvent(
      keyDown(LogicalKeyboardKey.controlLeft),
    );
    addTearDown(() {
      HardwareKeyboard.instance.handleKeyEvent(
        KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );
    });

    handler.handle(focusNode, keyDown(LogicalKeyboardKey.enter));

    expect(submitted, isFalse);
    expect(controller.text, 'hi\n');
    focusNode.dispose();
  });
}
