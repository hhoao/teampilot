import 'dart:convert';

import '../../models/team_config.dart';
import '../../utils/team_member_naming.dart';

enum TeamGenGranularity { rosterOnly, fullTeam }

class TeamDraftFormatException implements Exception {
  TeamDraftFormatException(this.message);
  final String message;
  @override
  String toString() => 'TeamDraftFormatException: $message';
}

/// Legal values the AI must choose from; used to clamp parsed output.
class TeamDraftAllowedOptions {
  const TeamDraftAllowedOptions({
    required this.models,
    required this.efforts,
    required this.skillIds,
    required this.defaultModel,
  });

  final List<String> models;
  final List<String> efforts;
  final List<String> skillIds;
  final String defaultModel;
}

/// A validated, legal team draft produced from AI output.
class TeamConfigDraft {
  const TeamConfigDraft({
    required this.members,
    this.teamName,
    this.mode,
    this.skillIds = const [],
  });

  final List<TeamMemberConfig> members;
  final String? teamName;
  final TeamMode? mode;
  final List<String> skillIds;
}

/// Parses [rawJson] into a clamped [TeamConfigDraft]. Illegal models fall back
/// to [TeamDraftAllowedOptions.defaultModel]; illegal efforts are cleared;
/// unknown skill ids are dropped; nameless members are skipped.
TeamConfigDraft parseTeamConfigDraft(
  String rawJson, {
  required TeamDraftAllowedOptions allowed,
  required TeamGenGranularity granularity,
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

  final full = granularity == TeamGenGranularity.fullTeam;

  final rawMembers = decoded['members'];
  final members = <TeamMemberConfig>[];
  if (rawMembers is List) {
    for (final raw in rawMembers) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final role = (raw['role'] as String? ?? '').trim();
      final rawModel = (raw['model'] as String? ?? '').trim();
      final model = allowed.models.contains(rawModel)
          ? rawModel
          : allowed.defaultModel;
      final rawEffort = (raw['effort'] as String? ?? '').trim();
      final effort = allowed.efforts.contains(rawEffort) ? rawEffort : '';
      members.add(
        TeamMemberConfig(
          id: TeamMemberNaming.slugMemberName(name),
          name: name,
          agentType: role,
          model: model,
          effort: effort,
          joinedAt: joinedAt,
        ),
      );
    }
  }

  if (!full) {
    return TeamConfigDraft(members: members);
  }

  final teamName = (decoded['teamName'] as String? ?? '').trim();
  final rawMode = (decoded['mode'] as String? ?? '').trim();
  final mode = switch (rawMode) {
    'mixed' => TeamMode.mixed,
    'native' => TeamMode.native,
    _ => null,
  };
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
    mode: mode,
    skillIds: skillIds,
  );
}

/// Removes a surrounding ```json ... ``` fence if present.
String _stripFences(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final nl = text.indexOf('\n');
    if (nl != -1) text = text.substring(nl + 1);
    final end = text.lastIndexOf('```');
    if (end != -1) text = text.substring(0, end);
  }
  return text.trim();
}
