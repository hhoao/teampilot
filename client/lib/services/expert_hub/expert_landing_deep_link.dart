import '../../models/workspace.dart';import '../../cubits/expert_hub_cubit.dart';
import '../../utils/landing_draft_resolver.dart';
import '../home_workspace/landing_prefs_store.dart';
import 'composite_expert_hub_source.dart';
import 'expert_member_resolver.dart';

enum ExpertDeepLinkOutcome { none, applied, ignoredTeamMode, notFound }

/// Applies `?expert=` to the workspace compose-landing draft when valid.
Future<ExpertDeepLinkOutcome> applyExpertDeepLink({
  required String? expertKey,
  required String workspaceId,
  required Workspace workspace,
  required bool routeProfileIsTeam,
  ExpertHubState? hubState,
  CompositeExpertHubSource? source,
  LandingPrefsStore? store,
}) async {
  final trimmed = expertKey?.trim() ?? '';
  if (trimmed.isEmpty) return ExpertDeepLinkOutcome.none;

  final draft = await resolveLandingDraft(
    workspaceId: workspaceId,
    workspace: workspace,
    store: store,
  );

  if (routeProfileIsTeam || !draft.isPersonal) {
    await persistLandingDraft(
      workspaceId,
      draft.copyWith(expertKey: null),
      store: store,
    );
    return ExpertDeepLinkOutcome.ignoredTeamMode;
  }

  final member = await ExpertMemberResolver.resolveMember(
    key: trimmed,
    hubState: hubState,
    source: source,
  );
  if (member == null) {
    await persistLandingDraft(
      workspaceId,
      draft.copyWith(expertKey: null),
      store: store,
    );
    return ExpertDeepLinkOutcome.notFound;
  }

  await persistLandingDraft(
    workspaceId,
    draft.copyWith(isPersonal: true, expertKey: trimmed),
    store: store,
  );
  return ExpertDeepLinkOutcome.applied;
}

/// Whether [profileId] from `?profile=` refers to a team (not personal).
bool routeProfileIsTeamKind({
  required String? profileId,
  required bool Function(String id) isPersonalProfile,
}) {
  final id = profileId?.trim() ?? '';
  if (id.isEmpty) return false;
  return !isPersonalProfile(id);
}
