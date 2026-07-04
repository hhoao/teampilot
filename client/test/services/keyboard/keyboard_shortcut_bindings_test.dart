import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/keyboard_shortcut_action.dart';
import 'package:teampilot/services/keyboard/keyboard_shortcut_bindings.dart';

PhysicalKeyboardKey _physicalFor(LogicalKeyboardKey logicalKey) {
  return switch (logicalKey) {
    LogicalKeyboardKey.enter => PhysicalKeyboardKey.enter,
    LogicalKeyboardKey.controlLeft => PhysicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.meta => PhysicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.keyS => PhysicalKeyboardKey.keyS,
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
      LogicalKeyboardKey.meta,
    ]) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(key)) {
        releaseModifier(key);
      }
    }
  });

  group('KeyboardShortcutBindings.compose', () {
    test('plain Enter maps to composeSubmit', () {
      expect(
        KeyboardShortcutBindings.compose.match(keyDown(LogicalKeyboardKey.enter)),
        KeyboardShortcutAction.composeSubmit,
      );
    });

    test('Ctrl+Enter maps to composeNewLine', () {
      pressModifier(LogicalKeyboardKey.controlLeft);
      addTearDown(() => releaseModifier(LogicalKeyboardKey.controlLeft));

      expect(
        KeyboardShortcutBindings.compose.match(keyDown(LogicalKeyboardKey.enter)),
        KeyboardShortcutAction.composeNewLine,
      );
    });

    test('mergeWith replaces bindings per action', () {
      final overrides = KeyboardShortcutBindings.fromActivators(
        activatorsByAction: {
          KeyboardShortcutAction.composeSubmit: const [
            SingleActivator(LogicalKeyboardKey.keyS, control: true),
          ],
        },
        matchPriority: const [KeyboardShortcutAction.composeSubmit],
      );

      final merged = KeyboardShortcutBindings.compose.mergeWith(overrides);
      expect(merged.activatorsFor(KeyboardShortcutAction.composeSubmit), [
        const SingleActivator(LogicalKeyboardKey.keyS, control: true),
      ]);
      expect(
        merged.activatorsFor(KeyboardShortcutAction.composeNewLine),
        KeyboardShortcutBindings.compose.activatorsFor(
          KeyboardShortcutAction.composeNewLine,
        ),
      );
    });
  });
}
