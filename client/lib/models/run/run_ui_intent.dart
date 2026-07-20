import 'package:flutter/foundation.dart';

/// Which workbench tool surface a Shell Script / Run launch should target.
enum RunToolSurface { terminal, run }

/// Workbench tab activation / focus request emitted after a successful run start.
@immutable
class RunUiIntent {
  const RunUiIntent({
    required this.surface,
    required this.activateToolWindow,
    required this.focusToolWindow,
    this.terminalEntryId,
  });

  final RunToolSurface surface;
  final bool activateToolWindow;
  final bool focusToolWindow;

  /// Shell terminal entry to select when [surface] is [RunToolSurface.terminal].
  final String? terminalEntryId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunUiIntent &&
          runtimeType == other.runtimeType &&
          surface == other.surface &&
          activateToolWindow == other.activateToolWindow &&
          focusToolWindow == other.focusToolWindow &&
          terminalEntryId == other.terminalEntryId;

  @override
  int get hashCode => Object.hash(
    surface,
    activateToolWindow,
    focusToolWindow,
    terminalEntryId,
  );
}
