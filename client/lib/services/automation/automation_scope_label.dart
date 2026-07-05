import 'package:collection/collection.dart';

import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/automation.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/personal_profile.dart';
import '../../models/team_config.dart';

/// Short subtitle for workspace sidebar rows and list grouping.
String automationScopeSubtitle(
  AppLocalizations l10n, {
  required Automation automation,
  required LaunchProfileState profiles,
  required CliPresetsState presets,
}) {
  if (automation.isScheduledMessage) {
    final sessionId = automation.sessionId?.trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      return l10n.automationsScopeScheduledMessage(sessionId);
    }
    return l10n.automationsFilterScheduledMessage;
  }

  final profile = profiles.byId(automation.launchProfileId);
  if (profile?.kind == LaunchProfileKind.personal) {
    final presetLabel = _personalPresetLabel(automation, presets);
    return l10n.automationsScopePersonal(presetLabel);
  }

  final teamName = profile?.display.trim();
  final memberName = _teamMemberName(
    profiles,
    automation.launchProfileId,
    automation.targetMemberId,
  );
  if (teamName != null && teamName.isNotEmpty) {
    return l10n.automationsScopeTeam(teamName, memberName);
  }
  return l10n.automationsScopeTeamMember(memberName);
}

/// Group header when automations are split by launch profile.
String automationLaunchProfileGroupLabel(
  AppLocalizations l10n, {
  required String launchProfileId,
  required LaunchProfileState profiles,
}) {
  final profile = profiles.byId(launchProfileId);
  if (profile == null) return launchProfileId;
  return switch (profile.kind) {
    LaunchProfileKind.personal => l10n.automationsScopeModePersonal(profile.display),
    LaunchProfileKind.team => l10n.automationsScopeModeTeam(profile.display),
  };
}

String _personalPresetLabel(Automation automation, CliPresetsState presets) {
  final presetId = automation.cliPresetId?.trim();
  if (presetId != null && presetId.isNotEmpty) {
    final preset = presets.presets.where((p) => p.id == presetId).firstOrNull;
    if (preset != null) return preset.name;
  }
  final cli = automation.cli;
  if (cli != null) return cli.value;
  return presets.presets.firstOrNull?.name ?? '';
}

String _teamMemberName(
  LaunchProfileState profiles,
  String launchProfileId,
  String memberId,
) {
  final profile = profiles.byId(launchProfileId);
  if (profile is! TeamProfile) return memberId;
  final member = profile.members
      .where((m) => m.id == memberId && m.isValid)
      .firstOrNull;
  return member?.name ?? memberId;
}
