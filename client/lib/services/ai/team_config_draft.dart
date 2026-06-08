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

/// A validated team draft produced from AI output.
///
/// Generation produces only the team shape and prose — names, roles,
/// responsibilities, working methods, and the team description. Model, effort,
/// skills, and per-member CLI are NOT generated; the user configures those
/// after the team is created.
class TeamConfigDraft {
  const TeamConfigDraft({
    required this.members,
    this.teamName,
    this.description,
  });

  final List<TeamMemberConfig> members;
  final String? teamName;
  final String? description;
}

/// Parses [rawJson] into a [TeamConfigDraft]. Nameless members are skipped; the
/// result always contains exactly one `team-lead`. Model, effort, skills, and
/// CLI are left unset for the user to configure after creation.
TeamConfigDraft parseTeamConfigDraft(
  String rawJson, {
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

      parsed.add(
        TeamMemberConfig(
          id: TeamMemberNaming.slugMemberName(name),
          name: name,
          agentType: role,
          prompt: responsibilities,
          playbook: workingMethod,
          joinedAt: joinedAt,
        ),
      );
    }
  }

  final members = _enforceSingleLead(parsed, joinedAt: joinedAt);

  final teamName = (decoded['teamName'] as String? ?? '').trim();
  final description = (decoded['description'] as String? ?? '').trim();

  return TeamConfigDraft(
    members: members,
    teamName: teamName.isEmpty ? null : teamName,
    description: description.isEmpty ? null : description,
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
