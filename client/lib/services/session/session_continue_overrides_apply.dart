import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_continue_overrides.dart';
import '../../models/team_config.dart';

bool resolveContinueSkipPermissions({
  required bool? sessionLevel,
  required bool? memberLevel,
  required bool launchDefault,
}) =>
    memberLevel ?? sessionLevel ?? launchDefault;

/// Launch-member merge order: base → optional team preset → continue overrides last.
///
/// [withPreset] is team-only; Simple skips preset. Overrides always win over
/// template preset for permission / provider / model / effort / presetId.
TeamMemberConfig finalizeSessionLaunchMember({
  required AppSession session,
  required TeamMemberConfig baseMember,
  required String memberId,
  required bool isSimple,
  CliPreset? preset,
  TeamMemberConfig Function(TeamMemberConfig, CliPreset?)? withPreset,
}) {
  final afterPreset = (!isSimple && preset != null && withPreset != null)
      ? withPreset(baseMember, preset)
      : baseMember;
  return applySessionContinueOverrides(
    baseMember: afterPreset,
    session: session,
    memberId: memberId,
    isSimple: isSimple,
  );
}

/// [isSimple]: launchDefault for permission is `false`.
/// Team: launchDefault is [baseMember.dangerouslySkipPermissions] before override.
/// Simple: do NOT re-apply provider/model from memberOverrides; only permission from continueOverrides.
/// Team: apply memberOverrides[memberId] provider/model/effort/presetId + permission.
/// Never change [baseMember.cli].
///
/// When concrete provider/model/effort are applied, clear [TeamMemberConfig.activePresetId]
/// on the launch member so a later [memberForLaunch] cannot re-expand a template
/// preset over those fields. [SessionMemberContinueOverride.presetId] remains for
/// UI/persist; it is only copied onto the launch member when no concrete fields
/// were overridden.
TeamMemberConfig applySessionContinueOverrides({
  required TeamMemberConfig baseMember,
  required AppSession session,
  required String memberId,
  required bool isSimple,
}) {
  final overrides = session.continueOverrides;

  if (isSimple) {
    return baseMember.copyWith(
      // Seat key / X-Member for simple = session.sessionId (passed as memberId).
      id: memberId,
      dangerouslySkipPermissions: resolveContinueSkipPermissions(
        sessionLevel: overrides.dangerouslySkipPermissions,
        memberLevel: null,
        launchDefault: false,
      ),
    );
  }

  final memberOverride = overrides.memberOverrides[memberId];
  final permission = resolveContinueSkipPermissions(
    sessionLevel: overrides.dangerouslySkipPermissions,
    memberLevel: memberOverride?.dangerouslySkipPermissions,
    launchDefault: baseMember.dangerouslySkipPermissions,
  );

  if (memberOverride == null) {
    return baseMember.copyWith(
      dangerouslySkipPermissions: permission,
    );
  }

  var merged = baseMember.copyWith(
    dangerouslySkipPermissions: permission,
  );

  final hasConcreteLaunchFields = memberOverride.provider != null ||
      memberOverride.model != null ||
      memberOverride.effort != null;

  if (memberOverride.provider != null) {
    merged = merged.copyWith(provider: memberOverride.provider);
  }
  if (memberOverride.model != null) {
    merged = merged.copyWith(model: memberOverride.model);
  }
  if (memberOverride.effort != null) {
    merged = merged.copyWith(
      effort: memberOverride.effort,
      updateEffort: true,
    );
  }

  if (hasConcreteLaunchFields) {
    // Keep continue provider/model through stageTeamLaunch → memberForLaunch.
    merged = merged.copyWith(
      activePresetId: null,
      updateActivePresetId: true,
    );
  } else if (memberOverride.presetId != null) {
    merged = merged.copyWith(
      activePresetId: memberOverride.presetId,
      updateActivePresetId: true,
    );
  }

  return merged;
}
