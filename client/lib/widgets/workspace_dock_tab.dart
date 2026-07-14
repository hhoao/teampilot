import 'package:flutter/foundation.dart';

/// One open instance in the workspace bottom dock (shell PTY or Run session).
@immutable
sealed class WorkspaceDockTab {
  const WorkspaceDockTab();

  String get id;
}

/// Interactive workspace shell tab (`WorkspaceTerminalEntry`).
@immutable
final class WorkspaceDockShellTab extends WorkspaceDockTab {
  const WorkspaceDockShellTab(this.entryId);

  final String entryId;

  @override
  String get id => 'shell:$entryId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceDockShellTab && other.entryId == entryId;

  @override
  int get hashCode => entryId.hashCode;
}

/// Run tool-window session shown as a dock tab (same chrome as shell).
@immutable
final class WorkspaceDockRunTab extends WorkspaceDockTab {
  const WorkspaceDockRunTab(this.sessionId);

  final String sessionId;

  @override
  String get id => 'run:$sessionId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceDockRunTab && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}
