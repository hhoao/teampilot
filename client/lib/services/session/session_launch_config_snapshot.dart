import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_continue_overrides.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../cli/preset_resolver.dart';

/// Snapshots resolved launch config per session member binding at create time.
///
/// Team [TeamProfile.activePresetId] may change later; existing sessions keep
/// the create-time provider/model/preset via [AppSession.continueOverrides].
SessionContinueOverrides snapshotTeamSessionContinueOverrides({
  required SessionContinueOverrides base,
  required TeamProfile team,
  required List<SessionMemberBinding> bindings,
  required List<CliPreset> globalPresets,
}) {
  if (bindings.isEmpty) return base;

  final overrides = Map<String, SessionMemberContinueOverride>.from(
    base.memberOverrides,
  );
  for (final binding in bindings) {
    final rosterMemberId = binding.rosterMemberId.trim();
    if (rosterMemberId.isEmpty) continue;
    if (overrides.containsKey(rosterMemberId)) continue;

    final type = _memberTypeForBinding(team, binding);
    if (type == null || !type.isValid) continue;

    final resolved = resolveMemberLaunch(
      team: team,
      member: type,
      globalPresets: globalPresets,
    );
    if (!resolved.isConfigured && resolved.sourcePreset == null) continue;

    overrides[rosterMemberId] = SessionMemberContinueOverride(
      presetId: resolved.sourcePreset?.id,
      provider: resolved.provider.isNotEmpty ? resolved.provider : null,
      model: resolved.model.isNotEmpty ? resolved.model : null,
      effort: resolved.effort.isNotEmpty ? resolved.effort : null,
    );
  }

  return base.copyWith(memberOverrides: overrides);
}

/// Launch member for an existing team session reconnect.
///
/// Prefers [AppSession.continueOverrides], then the session-pinned CLI lock.
/// When the live team preset targets a different CLI, keeps the locked CLI
/// instead of applying the new team default.
TeamMemberConfig memberForSessionConnect({
  required AppSession session,
  required TeamProfile team,
  required TeamMemberConfig member,
  SessionMemberBinding? memberBinding,
  required List<CliPreset> globalPresets,
}) {
  final rosterMemberId = _rosterMemberId(member, memberBinding);
  final lockedCli = _lockedCli(session, rosterMemberId);
  final type = _memberTypeForConnect(team, member, memberBinding) ?? member;
  final resolved = resolveMemberLaunch(
    team: team,
    member: type,
    globalPresets: globalPresets,
  );

  if (lockedCli != null && resolved.cli != lockedCli) {
    return _withInstanceIdentity(
      instance: member,
      launched: type.copyWith(
        provider: type.provider.trim().isNotEmpty
            ? type.provider
            : team.providerForCli(lockedCli),
        model: type.model.trim().isNotEmpty ? type.model : team.modelForCli(lockedCli),
        effort: type.effort.trim().isNotEmpty
            ? type.effort
            : team.effortForCli(lockedCli),
        cli: team.teamMode == TeamMode.mixed ? lockedCli : null,
        updateCli: team.teamMode == TeamMode.mixed,
        activePresetId: null,
        updateActivePresetId: true,
      ),
    );
  }

  return _withInstanceIdentity(
    instance: member,
    launched: memberForLaunch(team: team, member: type, globalPresets: globalPresets),
  );
}

/// Effective preset for team session connect (never [TeamProfile.inheritPresetId]).
CliPreset? presetForSessionConnect({
  required AppSession session,
  required TeamProfile team,
  required TeamMemberConfig member,
  SessionMemberBinding? memberBinding,
  required List<CliPreset> globalPresets,
}) {
  final rosterMemberId = _rosterMemberId(member, memberBinding);
  final override = session.continueOverrides.memberOverrides[rosterMemberId];
  final overridePresetId = override?.presetId?.trim() ?? '';
  if (overridePresetId.isNotEmpty) {
    return presetById(overridePresetId, globalPresets);
  }

  final lockedCli = _lockedCli(session, rosterMemberId);
  final type = _memberTypeForConnect(team, member, memberBinding) ?? member;
  final resolved = resolveMemberLaunch(
    team: team,
    member: type,
    globalPresets: globalPresets,
  );
  if (lockedCli != null && resolved.cli != lockedCli) {
    return null;
  }
  return resolved.sourcePreset;
}

TeamMemberConfig? _memberTypeForBinding(
  TeamProfile team,
  SessionMemberBinding binding,
) {
  final typeId = binding.typeId.trim();
  if (typeId.isNotEmpty) {
    for (final type in team.members) {
      if (type.id == typeId) return type;
    }
  }
  final rosterMemberId = binding.rosterMemberId.trim();
  if (rosterMemberId.isNotEmpty) {
    for (final type in team.members) {
      if (type.id == rosterMemberId) return type;
    }
  }
  return null;
}

TeamMemberConfig? _memberTypeForConnect(
  TeamProfile team,
  TeamMemberConfig member,
  SessionMemberBinding? memberBinding,
) {
  final typeId = memberBinding?.typeId.trim() ?? '';
  if (typeId.isNotEmpty) {
    for (final type in team.members) {
      if (type.id == typeId) return type;
    }
  }
  for (final type in team.members) {
    if (type.id == member.id) return type;
  }
  final instanceId = member.id.trim();
  final dash = instanceId.lastIndexOf('-');
  if (dash > 0) {
    final suffix = instanceId.substring(dash + 1);
    if (int.tryParse(suffix) != null) {
      final inferredTypeId = instanceId.substring(0, dash);
      for (final type in team.members) {
        if (type.id == inferredTypeId) return type;
      }
    }
  }
  return null;
}

/// Keeps the runtime pod id ([instance]) while applying launch fields from
/// the resolved member-type config ([launched]).
TeamMemberConfig _withInstanceIdentity({
  required TeamMemberConfig instance,
  required TeamMemberConfig launched,
}) {
  final instanceId = instance.id.trim();
  if (instanceId.isEmpty || instanceId == launched.id) return launched;
  return launched.copyWith(
    id: instanceId,
    name: instance.name.trim().isNotEmpty ? instance.name.trim() : launched.name,
    agentType: instance.agentType ?? launched.agentType,
    capabilities: instance.capabilities.isNotEmpty
        ? instance.capabilities
        : launched.capabilities,
    replicas: 1,
  );
}

String _rosterMemberId(
  TeamMemberConfig member,
  SessionMemberBinding? memberBinding,
) {
  final fromBinding = memberBinding?.rosterMemberId.trim() ?? '';
  if (fromBinding.isNotEmpty) return fromBinding;
  return member.id.trim();
}

CliTool? _lockedCli(AppSession session, String rosterMemberId) {
  if (rosterMemberId.isEmpty) return null;
  return session.bindingFor(rosterMemberId)?.cli;
}
