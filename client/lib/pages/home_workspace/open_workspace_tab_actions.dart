import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/launch_profile.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/launch_profile_ref.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../models/workspace_tab_ref.dart';
import '../../utils/launch_profile_display_name.dart';
import '../../utils/launch_profile_resolver.dart';
import '../../utils/workspace_display_name.dart';
import '../../services/home_workspace/workspace_launch_prefs_store.dart';
import 'home_launch_workspace_dialog.dart';
import 'home_workspace_tab_scope.dart';
import 'launch_workspace_team_order.dart';

List<LaunchWorkspaceIdentityOption> buildLaunchIdentityOptions({
  required AppLocalizations l10n,
  required List<LaunchProfile> identities,
  required Workspace workspace,
  required List<AppSession> sessions,
}) {
  final personals = identities.whereType<PersonalProfile>().toList();
  final teams = identities.whereType<TeamProfile>().toList();
  final orderedTeamIds = orderTeamIdsByRecentUse(
    workspaceId: workspace.workspaceId,
    teamIds: teams.map((t) => t.id).toList(),
    sessions: sessions,
  );
  final teamById = {for (final t in teams) t.id: t};
  final mixed = workspaceTopologyRequiresMemberAssignment(workspace.folders);
  final personalBlockedHint = mixed ? l10n.mixedWorkspacePersonalLaunchBlockedHint : null;
  return [
    for (final personal in personals)
      LaunchWorkspaceIdentityOption(
        id: personal.id,
        name: launchProfileDisplayName(l10n, personal),
        isTeam: false,
        enabled: !mixed,
        disabledReason: personalBlockedHint,
      ),
    for (final id in orderedTeamIds)
      if (teamById[id] != null)
        LaunchWorkspaceIdentityOption(
          id: id,
          name: launchProfileDisplayName(l10n, teamById[id]!),
          isTeam: true,
        ),
  ];
}

String workspaceTabDisplayLabel({
  required AppLocalizations l10n,
  required Workspace workspace,
  required LaunchProfileRef identity,
  required List<LaunchProfile> identities,
  bool alwaysShowIdentity = false,
}) {
  final workspaceName = workspace.localizedName(l10n);
  if (!alwaysShowIdentity) return workspaceName;
  final profileId = identity.profileId;
  final workspaceIdentity =
      identities.where((e) => e.id == profileId).firstOrNull;
  final isPersonal = workspaceIdentity?.kind == LaunchProfileKind.personal;
  final identityLabel = isPersonal
      ? l10n.homeWorkspaceWorkspaceTabKindPersonal
      : (launchProfileDisplayNameForId(l10n, identities, profileId) ??
          profileId);
  return '$identityLabel · $workspaceName';
}

LaunchProfileRef? resolveWorkspaceLaunchPreselection({
  required Workspace workspace,
  required WorkspaceLaunchPref? pref,
  required LaunchProfile? Function(String id) lookupById,
}) {
  final fromPref = pref != null ? LaunchProfileRef.decode(pref.lastIdentity) : null;
  if (fromPref != null) {
    final profile = lookupById(fromPref.profileId);
    final isPersonal = profile?.kind == LaunchProfileKind.personal;
    if (!personalIdentityBlockedForWorkspace(
      isPersonal: isPersonal,
      folders: workspace.folders,
    )) {
      return fromPref;
    }
  }
  final resolved = resolveWorkspaceLaunchProfileRef(workspace, lookupById);
  final resolvedProfile = lookupById(resolved.profileId);
  if (personalIdentityBlockedForWorkspace(
    isPersonal: resolvedProfile?.kind == LaunchProfileKind.personal,
    folders: workspace.folders,
  )) {
    return null;
  }
  return resolved;
}

/// Opens [workspace] in a new title-bar tab after picking a launch identity.
Future<void> openWorkspaceInNewTabWithIdentityPicker(
  BuildContext context, {
  required Workspace workspace,
  required List<AppSession> sessions,
  LaunchProfileRef? excludeIdentity,
}) async {
  if (!context.mounted) return;
  final l10n = context.l10n;
  final identityCubit = context.read<LaunchProfileCubit>();
  final options = buildLaunchIdentityOptions(
    l10n: l10n,
    identities: identityCubit.state.identities,
    workspace: workspace,
    sessions: sessions,
  );
  final filtered = excludeIdentity == null
      ? options
      : options
          .where((o) => LaunchProfileRef(o.id) != excludeIdentity)
          .toList();
  final pickFrom = filtered.isNotEmpty ? filtered : options;
  if (pickFrom.isEmpty) return;

  final choice = await showHomeLaunchWorkspaceDialog(
    context,
    workspaceName: workspace.effectiveDisplay,
    identities: pickFrom,
    preselected: resolveWorkspaceLaunchProfileRef(
      workspace,
      identityCubit.byId,
    ),
  );
  if (choice == null || !context.mounted) return;

  final tab = WorkspaceTabRef(
    workspaceId: workspace.workspaceId,
    identity: choice.identity,
  );
  HomeTabScope.openInTab(
    context,
    workspace.workspaceId,
    activate: true,
    identity: choice.identity,
  );
  if (!context.mounted) return;
  context.go(tab.route);
}
