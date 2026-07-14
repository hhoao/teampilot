import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Describes which automations a list view or cubit load should cover.
@immutable
class AutomationListScope extends Equatable {
  const AutomationListScope._({
    this.workspaceId,
    this.sessionId,
  });

  /// Global management — every workspace.
  const AutomationListScope.all() : this._();

  /// All automations under one workspace.
  factory AutomationListScope.workspace(String workspaceId) {
    return AutomationListScope._(workspaceId: workspaceId.trim());
  }

  /// Automations for one session within a workspace.
  factory AutomationListScope.session(
    String workspaceId, {
    required String sessionId,
  }) {
    return AutomationListScope._(
      workspaceId: workspaceId.trim(),
      sessionId: sessionId.trim(),
    );
  }

  final String? workspaceId;
  final String? sessionId;

  bool get isAll => workspaceId == null;
  bool get isWorkspace => workspaceId != null && sessionId == null;
  bool get isSession => workspaceId != null && sessionId != null;

  @override
  List<Object?> get props => [workspaceId, sessionId];
}
