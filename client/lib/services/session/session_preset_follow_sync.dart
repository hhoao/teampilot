import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/session_continue_overrides.dart';
import '../../models/team_config.dart';
import '../../utils/workspace/landing_draft_resolver.dart';
import '../cli/preset_resolver.dart';

AppSession? staleFollowingSimpleSession({
  required AppSession session,
  required List<CliPreset> presets,
}) {
  if (!session.isSimple) return null;
  final identity = enrichSimpleLaunchIdentityFromPreset(
    identity: session.simpleIdentity,
    presets: presets,
  );
  if (identity.provider == session.provider &&
      identity.model == session.model &&
      identity.effort == session.effort) {
    return null;
  }
  return session.copyWith(
    provider: identity.provider,
    model: identity.model,
    effort: identity.effort,
  );
}

AppSession? staleFollowingTeamSession({
  required AppSession session,
  required String memberId,
  required List<CliPreset> presets,
  CliTool? lockedCli,
}) {
  if (session.isSimple) return null;
  final id = memberId.trim();
  if (id.isEmpty) return null;
  final existing = session.continueOverrides.memberOverrides[id];
  final presetId = existing?.presetId?.trim() ?? '';
  if (existing == null || presetId.isEmpty) return null;
  final preset = presetById(presetId, presets);
  if (preset == null) return null;
  if (lockedCli != null && preset.cli != lockedCli) return null;

  final provider = preset.provider.trim();
  final model = preset.model.trim();
  final effort = preset.effort.trim();
  if ((existing.provider ?? '') == provider &&
      (existing.model ?? '') == model &&
      (existing.effort ?? '') == effort) {
    return null;
  }

  final members = Map<String, SessionMemberContinueOverride>.from(
    session.continueOverrides.memberOverrides,
  );
  members[id] = existing.copyWith(
    provider: provider,
    model: model,
    effort: effort.isEmpty ? null : effort,
  );
  return session.copyWith(
    continueOverrides: session.continueOverrides.copyWith(
      memberOverrides: members,
    ),
  );
}
