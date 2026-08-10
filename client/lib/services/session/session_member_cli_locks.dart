import '../../models/cli_preset.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../cli/preset_resolver.dart';

/// Resolves per-**type** CLI locks for session create.
///
/// Keys are roster **type** ids ([TeamMemberConfig.id]), not pod instance ids.
/// Replicas of one type share one locked CLI; this also avoids mismatch when
/// create-time placement healing renumbers instances (`builder` → `builder-0`).
Map<String, CliTool> resolveSessionMemberCliLocks({
  required TeamProfile team,
  required List<TeamMemberConfig> rosterMembers,
  List<CliPreset> globalPresets = const [],
}) {
  final out = <String, CliTool>{};
  for (final type in rosterMembers.where((m) => m.isValid)) {
    out[type.id] = memberLaunchCli(
      team: team,
      member: type,
      globalPresets: globalPresets,
    );
  }
  return out;
}

/// Copies a locked CLI from [sourceMembers] for a cloned binding.
///
/// Prefer an exact [rosterMemberId] match; otherwise any binding with the same
/// [typeId]. Returns null when there is no usable match (or source `cli` is
/// null / legacy).
CliTool? copyCliFromSourceBinding({
  required List<SessionMemberBinding> sourceMembers,
  required String rosterMemberId,
  required String typeId,
}) {
  for (final m in sourceMembers) {
    if (m.rosterMemberId == rosterMemberId) return m.cli;
  }
  for (final m in sourceMembers) {
    if (m.typeId == typeId) return m.cli;
  }
  return null;
}
