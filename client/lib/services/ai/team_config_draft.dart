import 'dart:convert';

import '../../models/default_team_roster.dart';
import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';

class TeamDraftFormatException implements Exception {
  TeamDraftFormatException(this.message);
  final String message;
  @override
  String toString() => 'TeamDraftFormatException: $message';
}

/// Legal model/effort values for one CLI, used to clamp parsed members.
class CliModelOptions {
  const CliModelOptions({
    required this.cli,
    required this.models,
    required this.efforts,
    required this.defaultModel,
  });

  final CliTool cli;
  final List<String> models;
  final List<String> efforts;
  final String defaultModel;
}

/// Legal values the AI must choose from; used to clamp parsed output.
///
/// native: [clis] holds one entry (the team CLI).
/// mixed: one entry per launch-supported CLI.
class TeamDraftAllowedOptions {
  const TeamDraftAllowedOptions({required this.clis, required this.skillIds});

  final List<CliModelOptions> clis;
  final List<String> skillIds;

  /// The fallback CLI options. [clis] must be non-empty (native: the team CLI;
  /// mixed: at least one launch-supported CLI).
  CliModelOptions get primary {
    assert(clis.isNotEmpty, 'TeamDraftAllowedOptions.clis must not be empty');
    return clis.first;
  }

  CliModelOptions optionsFor(CliTool cli) =>
      clis.firstWhere((o) => o.cli == cli, orElse: () => primary);
}

/// A validated, legal team draft produced from AI output.
class TeamConfigDraft {
  const TeamConfigDraft({
    required this.members,
    this.teamName,
    this.description,
    this.skillIds = const [],
  });

  final List<TeamMemberConfig> members;
  final String? teamName;
  final String? description;
  final List<String> skillIds;
}

/// Parses [rawJson] into a clamped [TeamConfigDraft]. Illegal models fall back
/// to the member CLI's default; illegal efforts are cleared; unknown skill ids
/// and (in mixed) unknown clis are dropped to the primary CLI; nameless members
/// are skipped. The result always contains exactly one `team-lead`.
TeamConfigDraft parseTeamConfigDraft(
  String rawJson, {
  required TeamDraftAllowedOptions allowed,
  required TeamMode mode,
  required int joinedAt,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_stripFences(rawJson));
  } on FormatException catch (e) {
    throw TeamDraftFormatException('Output was not valid JSON: ${e.message}');
  }
  if (decoded is! Map) {
    throw TeamDraftFormatException('Output JSON was not an object.');
  }

  final mixed = mode == TeamMode.mixed;
  final rawMembers = decoded['members'];
  final parsed = <TeamMemberConfig>[];
  if (rawMembers is List) {
    for (final raw in rawMembers) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final role = (raw['role'] as String? ?? '').trim();
      final responsibilities = (raw['responsibilities'] as String? ?? '').trim();
      final workingMethod = (raw['workingMethod'] as String? ?? '').trim();

      CliTool? memberCli;
      if (mixed) {
        final parsedCli = CliTool.tryParse(raw['cli'] as String?);
        memberCli = (parsedCli != null &&
                allowed.clis.any((o) => o.cli == parsedCli))
            ? parsedCli
            : allowed.primary.cli;
      }
      final opts = allowed.optionsFor(memberCli ?? allowed.primary.cli);
      final rawModel = (raw['model'] as String? ?? '').trim();
      final model =
          opts.models.contains(rawModel) ? rawModel : opts.defaultModel;
      final rawEffort = (raw['effort'] as String? ?? '').trim();
      final effort = opts.efforts.contains(rawEffort) ? rawEffort : '';

      parsed.add(
        TeamMemberConfig(
          id: TeamMemberNaming.slugMemberName(name),
          name: name,
          agentType: role,
          prompt: responsibilities,
          playbook: workingMethod,
          model: model,
          effort: effort,
          cli: memberCli,
          joinedAt: joinedAt,
        ),
      );
    }
  }

  final members = _enforceSingleLead(parsed, joinedAt: joinedAt);

  final teamName = (decoded['teamName'] as String? ?? '').trim();
  final description = (decoded['description'] as String? ?? '').trim();
  final rawSkills = decoded['skillIds'];
  final skillIds = <String>[];
  if (rawSkills is List) {
    for (final s in rawSkills) {
      final id = s.toString().trim();
      if (allowed.skillIds.contains(id)) skillIds.add(id);
    }
  }

  return TeamConfigDraft(
    members: members,
    teamName: teamName.isEmpty ? null : teamName,
    description: description.isEmpty ? null : description,
    skillIds: skillIds,
  );
}

/// Guarantees exactly one `team-lead`: keeps the first lead the model emitted,
/// re-slugs duplicate leads to unique worker ids, and injects the default lead
/// when none was produced.
List<TeamMemberConfig> _enforceSingleLead(
  List<TeamMemberConfig> members, {
  required int joinedAt,
}) {
  final result = <TeamMemberConfig>[];
  final usedIds = <String>{};
  var leadSeen = false;
  for (final m in members) {
    if (TeamMemberNaming.isTeamLead(m)) {
      if (!leadSeen) {
        leadSeen = true;
        usedIds.add(m.id);
        result.add(m);
        continue;
      }
      // A duplicate lead is demoted to a worker. If its name still slugs to the
      // reserved lead id, fall back to the generic worker id so it can't re-claim
      // the lead slot.
      final base = TeamMemberNaming.slugMemberName(m.name);
      final demoted = base == TeamMemberNaming.teamLeadName
          ? TeamMemberNaming.defaultWorkerName
          : base;
      final id = _uniqueMemberId(demoted, usedIds);
      usedIds.add(id);
      result.add(m.copyWith(id: id));
    } else {
      final id = _uniqueMemberId(m.id, usedIds);
      usedIds.add(id);
      result.add(id == m.id ? m : m.copyWith(id: id));
    }
  }
  if (!leadSeen) {
    final lead = DefaultTeamRoster.bootstrap(joinedAt: joinedAt).first;
    result.insert(0, lead);
  }
  return result;
}

String _uniqueMemberId(String base, Set<String> used) {
  final b = base.isEmpty ? TeamMemberNaming.defaultWorkerName : base;
  if (!used.contains(b)) return b;
  var n = 2;
  while (used.contains('$b-$n')) {
    n++;
  }
  return '$b-$n';
}

/// Removes a surrounding ```json ... ``` fence if present.
String _stripFences(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final nl = text.indexOf('\n');
    // A fence with no newline (e.g. ```json{...}```) isn't a clean block; leave
    // it for jsonDecode + the generator's retry rather than corrupt it.
    if (nl == -1) return text;
    text = text.substring(nl + 1);
    final end = text.lastIndexOf('```');
    if (end != -1) text = text.substring(0, end);
  }
  return text.trim();
}
