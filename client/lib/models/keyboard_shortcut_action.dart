/// Identifies a keyboard-driven action that can be rebound via prefs later.
enum KeyboardShortcutAction {
  /// Submit the compose field (e.g. landing prompt → launch session).
  composeSubmit,

  /// Insert a newline in the compose field without submitting.
  composeNewLine,
}
