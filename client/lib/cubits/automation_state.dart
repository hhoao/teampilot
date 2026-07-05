import 'package:equatable/equatable.dart';

import '../models/automation.dart';
import '../models/automation_list_scope.dart';

enum AutomationLoadStatus { idle, loading, ready, error }

class AutomationState extends Equatable {
  const AutomationState({
    this.automations = const [],
    this.runsByAutomationId = const {},
    this.status = AutomationLoadStatus.idle,
    this.errorMessage,
    this.listScope,
  });

  final List<Automation> automations;
  final Map<String, List<AutomationRun>> runsByAutomationId;
  final AutomationLoadStatus status;
  final String? errorMessage;
  final AutomationListScope? listScope;

  List<Automation> get visibleAutomations =>
      filterAutomationsForScope(automations, listScope);

  AutomationState copyWith({
    List<Automation>? automations,
    Map<String, List<AutomationRun>>? runsByAutomationId,
    AutomationLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    AutomationListScope? listScope,
    bool clearListScope = false,
  }) {
    return AutomationState(
      automations: automations ?? this.automations,
      runsByAutomationId: runsByAutomationId ?? this.runsByAutomationId,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      listScope: clearListScope ? null : (listScope ?? this.listScope),
    );
  }

  @override
  List<Object?> get props => [
    automations,
    runsByAutomationId,
    status,
    errorMessage,
    listScope,
  ];
}

List<Automation> filterAutomationsForScope(
  List<Automation> automations,
  AutomationListScope? scope,
) {
  if (scope == null || scope.isAll) return automations;
  if (scope.isWorkspace) {
    final workspaceId = scope.workspaceId!;
    return automations
        .where((a) => a.workspaceId == workspaceId)
        .toList(growable: false);
  }
  final tab = scope.tabScope!;
  var items = automations.where(
    (a) =>
        a.workspaceId == tab.workspaceId &&
        a.launchProfileId == tab.launchProfileId,
  );
  final sessionId = scope.sessionId?.trim();
  if (sessionId != null && sessionId.isNotEmpty) {
    items = items.where((a) => a.sessionId == sessionId);
  }
  return items.toList(growable: false);
}
