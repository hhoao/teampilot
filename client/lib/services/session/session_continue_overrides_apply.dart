import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';

LaunchSecurityPolicy resolveContinueSecurityPolicy({
  required LaunchSecurityPolicy launchDefault,
  LaunchSecurityPolicyOverride? sessionLevel,
  LaunchSecurityPolicyOverride? memberLevel,
}) {
  var resolved = launchDefault;
  if (sessionLevel != null) resolved = sessionLevel.applyTo(resolved);
  if (memberLevel != null) resolved = memberLevel.applyTo(resolved);
  return resolved;
}

/// Launch-member merge order: base → optional team preset → continue overrides last.
///
/// [withPreset] is team-only; Simple skips preset. Overrides always win over
/// template preset for policy / provider / model / effort / presetId.
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
  var merged = applySessionContinueOverrides(
    baseMember: afterPreset,
    session: session,
    memberId: memberId,
    isSimple: isSimple,
    livePreset: isSimple ? null : preset,
  );
  if (!isSimple) {
    final id = memberId.trim();
    if (id.isNotEmpty) {
      merged = merged.copyWith(id: id);
    }
  }
  return merged;
}

/// Simple: do NOT re-apply provider/model from memberOverrides; only security
/// policy from continueOverrides.
/// Team: apply memberOverrides[memberId] provider/model/effort/presetId + policy.
/// Never change [baseMember.cli].
///
/// When a member follows a matching live preset, do not reapply its stored
/// provider/model/effort snapshot. Detached or missing presets still stamp
/// concrete fields and clear [TeamMemberConfig.activePresetId] so a later
/// [memberForLaunch] cannot re-expand a template preset over those fields.
TeamMemberConfig applySessionContinueOverrides({
  required TeamMemberConfig baseMember,
  required AppSession session,
  required String memberId,
  required bool isSimple,
  CliPreset? livePreset,
}) {
  final overrides = session.continueOverrides;

  if (isSimple) {
    return baseMember.copyWith(
      // Seat key / X-Member for simple = session.sessionId (passed as memberId).
      id: memberId,
      launchSecurityPolicy: resolveContinueSecurityPolicy(
        launchDefault: baseMember.launchSecurityPolicy,
        sessionLevel: overrides.launchSecurityPolicy,
        memberLevel: null,
      ),
    );
  }

  final memberOverride = overrides.memberOverrides[memberId];
  final policy = resolveContinueSecurityPolicy(
    sessionLevel: overrides.launchSecurityPolicy,
    memberLevel: memberOverride?.launchSecurityPolicy,
    launchDefault: baseMember.launchSecurityPolicy,
  );

  if (memberOverride == null) {
    return baseMember.copyWith(launchSecurityPolicy: policy);
  }

  var merged = baseMember.copyWith(launchSecurityPolicy: policy);
  final followId = memberOverride.presetId?.trim() ?? '';
  final liveId = livePreset?.id.trim() ?? '';
  final following =
      followId.isNotEmpty &&
      livePreset != null &&
      liveId == followId &&
      livePreset.cli == baseMember.cli;

  if (following) {
    return merged.copyWith(
      activePresetId: followId,
      updateActivePresetId: true,
    );
  }

  final hasConcreteLaunchFields =
      memberOverride.provider != null ||
      memberOverride.model != null ||
      memberOverride.effort != null;

  if (memberOverride.provider != null) {
    merged = merged.copyWith(provider: memberOverride.provider);
  }
  if (memberOverride.model != null) {
    merged = merged.copyWith(model: memberOverride.model);
  }
  if (memberOverride.effort != null) {
    merged = merged.copyWith(effort: memberOverride.effort, updateEffort: true);
  }

  if (hasConcreteLaunchFields) {
    // Keep continue provider/model through stageTeamLaunch → memberForLaunch.
    merged = merged.copyWith(activePresetId: null, updateActivePresetId: true);
  } else if (memberOverride.presetId != null) {
    merged = merged.copyWith(
      activePresetId: memberOverride.presetId,
      updateActivePresetId: true,
    );
  }

  return merged;
}
