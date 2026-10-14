import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../../cubits/session_preferences_cubit.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_session.dart';
import '../../../models/cli_preset.dart';
import '../../../models/session_member_binding.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/chat/launch/session/session_member_cli_locks.dart';
import '../../../services/chat/launch/session/team_session_member_plan.dart';
import '../../../services/chat/session/chat_tab.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../widgets/compose/compose_chrome.dart';
import 'claude_acp_launch_switch.dart';

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

/// Gemini personal desktop always launches ACP; otherwise [resolveLaunchAcp].
bool willLaunchPersonalAcp({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (isPersonal && cli == CliTool.gemini && !_isAndroid(isAndroidOverride)) {
    return true;
  }
  return resolveLaunchAcp(
    isPersonal: isPersonal,
    cli: cli,
    requested: requested,
    isAndroidOverride: isAndroidOverride,
  );
}

/// Whether Landing should show the ACP Ask / Full access permission chip.
bool showLandingAcpPermissionChip({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  List<SessionMemberBinding> stampedMembers = const [],
  bool? isAndroidOverride,
}) {
  if (_isAndroid(isAndroidOverride)) return false;
  if (isPersonal) {
    return willLaunchPersonalAcp(
      isPersonal: true,
      cli: cli,
      requested: requested,
      isAndroidOverride: isAndroidOverride,
    );
  }
  return stampedMembers.any((member) => member.acp);
}

/// Compose chrome for ACP Ask vs Full access, or null when the pair is incomplete.
ComposePermissionControl? acpComposePermissionControl({
  required LaunchSecurityPolicy current,
  required Set<LaunchSecurityPolicy> supported,
  required AppLocalizations l10n,
  required ValueChanged<LaunchSecurityPolicy> onSelected,
}) {
  if (supported.length <= 1 ||
      !supported.contains(LaunchSecurityPolicy.ask) ||
      !supported.contains(LaunchSecurityPolicy.fullAccess)) {
    return null;
  }
  return ComposePermissionControl(
    launchSecurityPolicy: current,
    supportedPolicies: supported,
    defaultLabel: l10n.acpPermissionAskLabel,
    fullAccessLabel: l10n.acpPermissionFullAccessLabel,
    askLabel: l10n.acpPermissionAskLabel,
    onSelected: onSelected,
  );
}

/// Landing mixed members stamped the same way session create stamps ACP.
List<SessionMemberBinding> stampedLandingMembers({
  required TeamProfile team,
  required Workspace workspace,
  required bool seedClaudeMemberAcp,
  required bool seedCodexMemberAcp,
  required bool seedCursorMemberAcp,
  bool seedOpencodeMemberAcp = true,
  List<CliPreset> globalPresets = const [],
  LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess,
  bool? isAndroidOverride,
}) {
  try {
    final memberClis = resolveSessionMemberCliLocks(
      team: team,
      rosterMembers: team.members,
      globalPresets: globalPresets,
    );
    final plan = buildTeamSessionMemberPlan(
      workspace: workspace,
      teamId: team.id,
      rosterMembers: team.members,
      memberClis: memberClis,
    );
    return stampMemberAcp(
      members: plan.members,
      memberTargets: plan.memberTargets,
      teamMode: team.teamMode,
      seedClaudeMemberAcp: seedClaudeMemberAcp,
      seedCodexMemberAcp: seedCodexMemberAcp,
      seedCursorMemberAcp: seedCursorMemberAcp,
      seedOpencodeMemberAcp: seedOpencodeMemberAcp,
      acpPermission: acpPermission,
      isAndroidOverride: isAndroidOverride,
    );
  } on Object {
    return const [];
  }
}

/// Personal uses [launchCli]; mixed prefers an ACP member whose policies include ask.
CliTool? landingAcpPolicyCli({
  required bool isPersonal,
  required CliTool? launchCli,
  required List<SessionMemberBinding> stampedMembers,
  required Set<LaunchSecurityPolicy> Function(CliTool cli) policiesForAcp,
}) {
  if (isPersonal) return launchCli;
  CliTool? fallback;
  for (final member in stampedMembers) {
    final cli = member.cli;
    if (!member.acp || cli == null) continue;
    fallback ??= cli;
    final policies = policiesForAcp(cli);
    if (policies.contains(LaunchSecurityPolicy.ask) &&
        policies.contains(LaunchSecurityPolicy.fullAccess)) {
      return cli;
    }
  }
  return fallback;
}

ComposePermissionControl? buildLandingAcpComposePermissionControl({
  required bool isPersonal,
  required CliTool? launchCli,
  required bool requested,
  required List<SessionMemberBinding> stampedMembers,
  required LaunchSecurityPolicy current,
  required CliToolRegistry registry,
  required AppLocalizations l10n,
  required ValueChanged<LaunchSecurityPolicy> onSelected,
  bool? isAndroidOverride,
}) {
  if (!showLandingAcpPermissionChip(
    isPersonal: isPersonal,
    cli: launchCli,
    requested: requested,
    stampedMembers: stampedMembers,
    isAndroidOverride: isAndroidOverride,
  )) {
    return null;
  }
  final cli = landingAcpPolicyCli(
    isPersonal: isPersonal,
    launchCli: launchCli,
    stampedMembers: stampedMembers,
    policiesForAcp: (tool) =>
        registry.launchSecurityFor(tool).policiesFor(acp: true),
  );
  if (cli == null) return null;
  return acpComposePermissionControl(
    current: current,
    supported: registry.launchSecurityFor(cli).policiesFor(acp: true),
    l10n: l10n,
    onSelected: onSelected,
  );
}

ComposePermissionControl? landingAcpPermissionControl({
  required BuildContext context,
  required bool isPersonal,
  required CliTool? launchCli,
  required AppLocalizations l10n,
  TeamProfile? selectedTeam,
  Workspace? workspace,
  List<CliPreset> presets = const [],
}) {
  final current = watchAcpPermissionDefault(context);
  final stamped = !isPersonal && selectedTeam != null && workspace != null
      ? stampedLandingMembers(
          team: selectedTeam,
          workspace: workspace,
          seedClaudeMemberAcp: readPersonalAcpDefault(context, CliTool.claude),
          seedCodexMemberAcp: readPersonalAcpDefault(context, CliTool.codex),
          seedCursorMemberAcp: readPersonalAcpDefault(context, CliTool.cursor),
          seedOpencodeMemberAcp: readPersonalAcpDefault(
            context,
            CliTool.opencode,
          ),
          globalPresets: presets,
          acpPermission: current,
        )
      : const <SessionMemberBinding>[];
  final registry =
      CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
  return buildLandingAcpComposePermissionControl(
    isPersonal: isPersonal,
    launchCli: launchCli,
    requested: readPersonalAcpDefault(context, launchCli),
    stampedMembers: stamped,
    current: current,
    registry: registry,
    l10n: l10n,
    onSelected: (policy) {
      unawaited(
        context.read<SessionPreferencesCubit>().setAcpPermissionDefault(policy),
      );
    },
  );
}

ComposePermissionControl? buildSessionAcpComposePermissionControl({
  required AppSession session,
  required String selectedMemberId,
  required CliToolRegistry registry,
  required AppLocalizations l10n,
  required ValueChanged<LaunchSecurityPolicy> onSelected,
}) {
  final personalAcp = isAcpChatSession(session);
  if (!personalAcp && !isAcpChatSeat(session, selectedMemberId)) {
    return null;
  }
  final cli = personalAcp
      ? session.cli
      : session.bindingFor(selectedMemberId)?.cli;
  if (cli == null) return null;
  final current = personalAcp
      ? session.acpPermission
      : session.bindingFor(selectedMemberId)?.acpPermission ??
            LaunchSecurityPolicy.fullAccess;
  return acpComposePermissionControl(
    current: current,
    supported: registry.launchSecurityFor(cli).policiesFor(acp: true),
    l10n: l10n,
    onSelected: onSelected,
  );
}

ComposePermissionControl? sessionAcpPermissionControl({
  required BuildContext context,
  required AppSession session,
  required String selectedMemberId,
  required AppLocalizations l10n,
  AcpChatRuntimeCubit? runtime,
}) {
  final registry =
      CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
  return buildSessionAcpComposePermissionControl(
    session: session,
    selectedMemberId: selectedMemberId,
    registry: registry,
    l10n: l10n,
    onSelected: (policy) {
      unawaited(
        applyAcpComposePermission(
          preferences: context.read<SessionPreferencesCubit>(),
          chat: context.read<ChatCubit>(),
          repo: context.read<SessionRepository>(),
          sessionId: session.sessionId,
          memberId: isAcpChatSession(session) ? null : selectedMemberId,
          policy: policy,
          runtime: runtime,
        ),
      );
    },
  );
}

/// Preference + session/seat fact + runtime policy for a mid-session chip change.
Future<void> applyAcpComposePermission({
  required SessionPreferencesCubit preferences,
  required ChatCubit chat,
  required SessionRepository repo,
  required String sessionId,
  String? memberId,
  required LaunchSecurityPolicy policy,
  AcpChatRuntimeCubit? runtime,
}) async {
  runtime?.setPermissionPolicy(policy);
  await preferences.setAcpPermissionDefault(policy);
  await chat.setAcpPermission(
    repo,
    sessionId,
    memberId: memberId,
    policy: policy,
  );
}
