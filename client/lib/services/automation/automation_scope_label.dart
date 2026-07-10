import 'package:collection/collection.dart';

import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/automation.dart';
import '../../models/automation_tab_scope.dart';
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

  if (automation.launchProfileId == AutomationTabScope.simpleLaunchProfileId) {
    final presetLabel = _personalPresetLabel(automation, presets);
    return l10n.automationsScopePersonal(presetLabel);
  }

  final profile = profiles.byId(automation.launchProfileId);
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
  if (launchProfileId == AutomationTabScope.simpleLaunchProfileId) {
    return l10n.automationsScopeModePersonal('Simple');
  }
  final profile = profiles.byId(launchProfileId);
  if (profile == null) return launchProfileId;
  return l10n.automationsScopeModeTeam(profile.display);
}

String _personalPresetLabel(Automation automation, CliPresetsState presets) {
  final presetId = automation.cliPresetId?.trim() ?? '';
  if (presetId.isEmpty) return '';
  final match = presets.presets.where((p) => p.id == presetId).firstOrNull;
  return match?.name.trim() ?? presetId;
}

String _teamMemberName(
  LaunchProfileState profiles,
  String launchProfileId,
  String? targetMemberId,
) {
  final memberId = targetMemberId?.trim() ?? '';
  if (memberId.isEmpty) return '';
  final profile = profiles.byId(launchProfileId);
  if (profile is! TeamProfile) return memberId;
  for (final member in profile.members) {
    if (member.id == memberId) {
      final name = member.name.trim();
      return name.isNotEmpty ? name : memberId;
    }
  }
  return memberId;
}
