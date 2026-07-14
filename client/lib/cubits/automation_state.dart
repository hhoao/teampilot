import 'package:equatable/equatable.dart';

import '../models/automation.dart';
import '../models/automation_list_scope.dart';
import '../models/automation_session_match.dart';
import '../models/app_session.dart';

enum AutomationLoadStatus { idle, loading, ready, error }

class AutomationState extends Equatable {
  const AutomationState({
    this.automations = const [],
    this.runsByAutomationId = const {},
    this.status = AutomationLoadStatus.idle,
    this.errorMessage,
    this.listScope,
    this.sessionFilter,
  });

  final List<Automation> automations;
  final Map<String, List<AutomationRun>> runsByAutomationId;
  final AutomationLoadStatus status;
  final String? errorMessage;
  final AutomationListScope? listScope;

  /// When loading session-scoped lists, the session used for visibility filtering.
  final AppSession? sessionFilter;

  List<Automation> get visibleAutomations =>
      filterAutomationsForScope(automations, listScope, sessionFilter);

  AutomationState copyWith({
    List<Automation>? automations,
    Map<String, List<AutomationRun>>? runsByAutomationId,
    AutomationLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    AutomationListScope? listScope,
    bool clearListScope = false,
    AppSession? sessionFilter,
    bool clearSessionFilter = false,
  }) {
    return AutomationState(
      automations: automations ?? this.automations,
      runsByAutomationId: runsByAutomationId ?? this.runsByAutomationId,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      listScope: clearListScope ? null : (listScope ?? this.listScope),
      sessionFilter: clearSessionFilter
          ? null
          : (sessionFilter ?? this.sessionFilter),
    );
  }

  @override
  List<Object?> get props => [
    automations,
    runsByAutomationId,
    status,
    errorMessage,
    listScope,
    sessionFilter,
  ];
}

List<Automation> filterAutomationsForScope(
  List<Automation> automations,
  AutomationListScope? scope,
  AppSession? sessionFilter,
) {
  if (scope == null || scope.isAll) return automations;
  if (scope.isWorkspace) {
    final workspaceId = scope.workspaceId!;
    return automations
        .where((a) => a.workspaceId == workspaceId)
        .toList(growable: false);
  }
  final workspaceId = scope.workspaceId!;
  final session = sessionFilter;
  if (session != null) {
    return automations
        .where((a) => automationMatchesSession(a, session))
        .toList(growable: false);
  }
  final sessionId = scope.sessionId?.trim();
  if (sessionId == null || sessionId.isEmpty) {
    return automations
        .where((a) => a.workspaceId == workspaceId)
        .toList(growable: false);
  }
  return automations
      .where(
        (a) =>
            a.workspaceId == workspaceId &&
            automationMatchesSessionId(a, sessionId),
      )
      .toList(growable: false);
}
