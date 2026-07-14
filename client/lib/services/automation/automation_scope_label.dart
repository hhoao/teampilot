import 'package:collection/collection.dart';

import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/automation.dart';
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

  if (automation.isPersonal) {
    final presetLabel = _personalPresetLabel(automation, presets);
    return l10n.automationsScopePersonal(presetLabel);
  }

  final teamId = automation.teamId?.trim() ?? '';
  final profile = profiles.byId(teamId);
  final teamName = profile?.display.trim();
  final memberName = _teamMemberName(
    profiles,
    teamId,
    automation.targetMemberId,
  );
  if (teamName != null && teamName.isNotEmpty) {
    return l10n.automationsScopeTeam(teamName, memberName);
  }
  return l10n.automationsScopeTeamMember(memberName);
}

/// Group header when automations are split by launch context (personal vs team).
String automationLaunchContextGroupLabel(
  AppLocalizations l10n, {
  required Automation automation,
  required LaunchProfileState profiles,
}) {
  if (automation.isPersonal) {
    return l10n.automationsScopeModePersonal('Simple');
  }
  final teamId = automation.teamId?.trim() ?? '';
  if (teamId.isEmpty) return l10n.automationsScopeModePersonal('Simple');
  final profile = profiles.byId(teamId);
  if (profile == null) return teamId;
  return l10n.automationsScopeModeTeam(profile.display);
}

String _personalPresetLabel(Automation automation, CliPresetsState presets) {
  final presetId = automation.presetId?.trim() ?? '';
  if (presetId.isEmpty) return '';
  final match = presets.presets.where((p) => p.id == presetId).firstOrNull;
  return match?.name.trim() ?? presetId;
}

String _teamMemberName(
  LaunchProfileState profiles,
  String teamId,
  String? targetMemberId,
) {
  final memberId = targetMemberId?.trim() ?? '';
  if (memberId.isEmpty) return '';
  final profile = profiles.byId(teamId);
  if (profile is! TeamProfile) return memberId;
  for (final member in profile.members) {
    if (member.id == memberId) {
      final name = member.name.trim();
      return name.isNotEmpty ? name : memberId;
    }
  }
  return memberId;
}
