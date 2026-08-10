import '../../cubits/workbench/workbench_cubit.dart';

/// Whether [tabScopeId] is showing new-chat landing (not a session tab).
bool workspaceNewChatActive(WorkbenchCubit workbench, String tabScopeId) =>
    workbench.state.bar(tabScopeId).center.landingActive;
