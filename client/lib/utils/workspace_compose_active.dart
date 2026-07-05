import '../cubits/chat_cubit.dart';

/// Whether [tabScopeId] is showing workspace compose landing (not a session tab).
bool workspaceComposeActive(ChatCubit cubit, String tabScopeId) {
  final store = cubit.tabStore;
  if (store.activeWorkspaceId == tabScopeId) {
    return cubit.state.composeActive;
  }
  return store.isComposeActive(tabScopeId);
}
