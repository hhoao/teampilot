import 'package:teampilot/services/commands/command_definition.dart';
import 'package:teampilot/services/commands/key_chord.dart';

/// Snapshot of app focus/state used to decide whether a shortcut fires.
///
/// Derived cheaply per key event from focus + relevant cubits; see
/// docs/superpowers/specs/2026-07-11-keyboard-shortcuts-platform-design.md.
class ShortcutContext {
  const ShortcutContext({
    this.inTerminal = false,
    this.inCompose = false,
    this.inTextInput = false,
    this.hasWorkspace = false,
    this.hasOpenWorkspaceTabs = false,
    this.hasSessionTab = false,
    this.floatingPanelOpen = false,
    this.claimedChords = const {},
  });

  /// Primary focus is an agent PTY or workspace shell terminal view.
  final bool inTerminal;

  /// Focus is a compose / multiline prompt field.
  final bool inCompose;

  /// Focus is any editable text (compose, find, settings fields, editor).
  final bool inTextInput;

  /// Current route is an open workspace tab.
  final bool hasWorkspace;

  /// Home shell has at least one open workspace tab.
  final bool hasOpenWorkspaceTabs;

  /// Active workspace has a selected session tab (not compose-only landing).
  final bool hasSessionTab;

  /// Floating workspace panel visibility is [FloatingPanelVisibility.open].
  final bool floatingPanelOpen;

  /// Chords owned by the focused surface (union over every `ShortcutFocus`
  /// ancestor). A global command whose chord is claimed must not fire; the
  /// surface's own `Shortcuts` handles it instead.
  final Set<KeyChord> claimedChords;
}

extension ShortcutWhenEvaluation on ShortcutWhen {
  /// Whether this `when` clause is satisfied by [context].
  bool isSatisfiedBy(ShortcutContext context) {
    switch (this) {
      case ShortcutWhen.always:
        return true;
      case ShortcutWhen.hasWorkspace:
        return context.hasWorkspace;
      case ShortcutWhen.hasOpenWorkspaceTabs:
        return context.hasOpenWorkspaceTabs;
      case ShortcutWhen.hasSessionTab:
        return context.hasSessionTab;
      case ShortcutWhen.inCompose:
        return context.inCompose;
      case ShortcutWhen.floatingPanelOpen:
        return context.floatingPanelOpen;
    }
  }
}
