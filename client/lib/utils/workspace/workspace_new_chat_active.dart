import '../../cubits/chat_cubit.dart';

/// Whether [tabScopeId] is showing new-chat landing (not a session tab).
bool workspaceNewChatActive(ChatCubit cubit, String tabScopeId) {
  final store = cubit.tabStore;
  if (store.activeWorkspaceId == tabScopeId) {
    return cubit.state.newChatActive;
  }
  return store.isNewChatActive(tabScopeId);
}
