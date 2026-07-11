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
TeamMemberConfig applySessionContinueOverrides({
  required TeamMemberConfig baseMember,
  required AppSession session,
  required String memberId,
  required bool isSimple,
}) {
  final overrides = session.continueOverrides;

  if (isSimple) {
    return baseMember.copyWith(
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
  if (memberOverride.presetId != null) {
    merged = merged.copyWith(
      activePresetId: memberOverride.presetId,
      updateActivePresetId: true,
    );
  }

  return merged;
}
