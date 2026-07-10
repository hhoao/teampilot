import '../../models/workspace.dart';
import '../../cubits/expert_hub_cubit.dart';
import '../../utils/landing_draft_resolver.dart';
import '../home_workspace/landing_prefs_store.dart';
import 'composite_expert_hub_source.dart';
import 'expert_capability_pack.dart';
import 'expert_capability_resolver.dart';
import 'expert_landing_preflight.dart';
import 'expert_member_resolver.dart';

enum ExpertDeepLinkOutcome { none, applied, ignoredTeamMode, notFound }

/// Result of applying `?expert=` — includes pack when preflight ran.
class ExpertDeepLinkResult {
  const ExpertDeepLinkResult(this.outcome, {this.pack});

  final ExpertDeepLinkOutcome outcome;
  final ExpertCapabilityPack? pack;
}

/// Applies `?expert=` to the workspace compose-landing draft when valid.
///
/// Forces Simple mode (unless [routeProfileIsTeam]), preselects the expert,
/// and runs the same [ExpertCapabilityResolver.preflight] as chip select.
Future<ExpertDeepLinkResult> applyExpertDeepLink({
  required String? expertKey,
  required String workspaceId,
  required Workspace workspace,
  required bool routeProfileIsTeam,
  ExpertHubState? hubState,
  CompositeExpertHubSource? source,
  LandingPrefsStore? store,
  ExpertCapabilityResolver? resolver,
}) async {
  final trimmed = expertKey?.trim() ?? '';
  if (trimmed.isEmpty) {
    return const ExpertDeepLinkResult(ExpertDeepLinkOutcome.none);
  }

  final draft = await resolveLandingDraft(
    workspaceId: workspaceId,
    workspace: workspace,
    store: store,
  );

  // Explicit team profile in the URL keeps team mode; otherwise force Simple.
  if (routeProfileIsTeam) {
    await persistLandingDraft(
      workspaceId,
      draft.copyWith(expertKey: null),
      store: store,
    );
    return const ExpertDeepLinkResult(ExpertDeepLinkOutcome.ignoredTeamMode);
  }

  final member = await ExpertMemberResolver.resolveMember(
    key: trimmed,
    hubState: hubState,
    source: source,
  );
  if (member == null) {
    await persistLandingDraft(
      workspaceId,
      draft.copyWith(isPersonal: true, expertKey: null),
      store: store,
    );
    return const ExpertDeepLinkResult(ExpertDeepLinkOutcome.notFound);
  }

  ExpertCapabilityPack? pack;
  if (resolver != null) {
    final preflight = await preflightLandingExpert(
      resolver: resolver,
      expertKey: trimmed,
    );
    if (preflight.notFound) {
      await persistLandingDraft(
        workspaceId,
        draft.copyWith(isPersonal: true, expertKey: null),
        store: store,
      );
      return const ExpertDeepLinkResult(ExpertDeepLinkOutcome.notFound);
    }
    pack = preflight.pack;
  }

  await persistLandingDraft(
    workspaceId,
    draft.copyWith(isPersonal: true, expertKey: trimmed),
    store: store,
  );
  return ExpertDeepLinkResult(ExpertDeepLinkOutcome.applied, pack: pack);
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
