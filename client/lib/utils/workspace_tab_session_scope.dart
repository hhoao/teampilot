import '../cubits/chat_cubit.dart';
import '../models/launch_profile.dart';
import '../models/launch_profile_kind.dart';
import '../models/launch_profile_ref.dart';

/// Team id used by [ChatCubit.setTeamSessionScope] for a title-bar workspace tab.
/// Personal identities scope to '' (no team filter).
String workspaceTabSessionTeamScopeId(
  LaunchProfileRef identity,
  LaunchProfile? resolvedIdentity,
) {
  if (resolvedIdentity?.kind == LaunchProfileKind.personal) return '';
  return identity.profileId;
}

/// Session id highlighted in a kept-alive workspace sidebar for [tabScopeId].
///
/// Foreground tabs follow [ChatState.activeSessionId]; background tabs freeze
/// to the bucket's saved active chat tab.
String? scopedActiveSessionId(ChatCubit cubit, String tabScopeId) {
  final store = cubit.tabStore;
  if (store.activeWorkspaceId == tabScopeId) {
    return cubit.state.activeSessionId;
  }
  final bucket = store.tabsForWorkspace(tabScopeId);
  if (bucket.isEmpty) return null;
  final index = store.savedActiveIndexFor(tabScopeId);
  return bucket[index.clamp(0, bucket.length - 1)].info.id;
}
