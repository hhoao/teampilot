import 'shortcut_dispatcher.dart';

/// Global handle to the single root [ShortcutDispatcher] installed by
/// `ShortcutDispatcherHost` in `main.dart`.
///
/// The rebind-capture dialog (`shortcut_rebind_dialog.dart`) needs to
/// suspend app-wide shortcut matching while it owns raw key input, but it is
/// opened from deep inside the settings UI with no direct reference to the
/// dispatcher instance. This static holder bridges that gap without
/// threading the dispatcher through every settings widget.
abstract final class ShortcutDispatcherHandle {
  /// The live dispatcher, or `null` when no `ShortcutDispatcherHost` is
  /// mounted (e.g. most widget tests).
  static ShortcutDispatcher? instance;
}
