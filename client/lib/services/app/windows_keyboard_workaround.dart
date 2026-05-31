import 'dart:io';

import 'package:flutter/services.dart';

/// Patches Win32 Alt key events that omit modifier flags before the framework
/// keyboard state is updated.
///
/// Without this, modifier sync strips Alt from pressed keys when `modifiers` is
/// 0 and debug builds assert (Flutter only special-cases Linux/Android Alt).
void installWindowsKeyboardWorkaround() {
  if (!Platform.isWindows) return;

  // ignore: deprecated_member_use
  final keyEventManager = ServicesBinding.instance.keyEventManager;
  // ignore: deprecated_member_use
  final originalHandler = keyEventManager.handleRawKeyMessage;

  SystemChannels.keyEvent.setMessageHandler((Object? message) async {
    return originalHandler(patchWindowsAltModifierMessage(message));
  });
}

/// Visible for testing.
Object? patchWindowsAltModifierMessage(Object? message) {
  if (message is! Map) return message;

  final map = Map<String, dynamic>.from(
    message.map((key, value) => MapEntry(key.toString(), value)),
  );
  if (map['keymap'] != 'windows') return message;
  if (map['type'] != 'keydown') return message;

  final keyCode = map['keyCode'] as int? ?? 0;
  final modifiers = map['modifiers'] as int? ?? 0;
  if (modifiers != 0) return message;

  final int? altMask = switch (keyCode) {
    _vkLeftMenu => _modifierLeftAlt | _modifierAlt,
    _vkRightMenu => _modifierRightAlt | _modifierAlt,
    _ => null,
  };
  if (altMask == null) return message;

  map['modifiers'] = altMask;
  return map;
}

/// Win32 `VK_LMENU` / `VK_RMENU`.
const int _vkLeftMenu = 164;
const int _vkRightMenu = 165;

/// Mirrors Flutter `RawKeyEventDataWindows` modifier bit masks.
const int _modifierLeftAlt = 1 << 7;
const int _modifierRightAlt = 1 << 8;
const int _modifierAlt = 1 << 6;
