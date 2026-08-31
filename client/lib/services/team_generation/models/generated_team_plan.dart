import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Canonical plan JSON for one generated team; the wire contract the builder
/// model must speak. Unknown keys are rejected at every level, replicas are
/// strict ints in 1..8, and payload size is capped before decoding.
///
/// The model never supplies cli/provider/model/effort, profile IDs, expert
/// keys, filesystem paths, commands, or MCP credentials — only `presetId`
/// references into the frozen pool.
final class GeneratedTeamPlan {
  static const int schemaVersion = 1;
  static const int maxPayloadBytes = 128 * 1024;

  const GeneratedTeamPlan({
    required this.teamName,
    required this.teamDescription,
    required this.mode,
    required this.members,
    required this.skillIds,
    required this.pluginIds,
    required this.mcpServerIds,
    required this.revision,
  });

  factory GeneratedTeamPlan.fromJson(Map<String, Object?> json) {
    _checkTopLevelKeys(json);
    final team = json['team'];
    if (team is! Map) {
      throw const FormatException('plan.team must be an object');
    }
    final teamMap = team.cast<String, Object?>();
    _checkExactKeys(teamMap, const ['name', 'description', 'mode']);
    final membersRaw = json['members'];
    if (membersRaw is! List || membersRaw.isEmpty) {
      throw const FormatException('plan.members must be a non-empty array');
    }
    final members = <GeneratedTeamMemberPlan>[];
    for (final raw in membersRaw) {
      if (raw is! Map) {
        throw const FormatException('plan.members[] must be objects');
      }
      members.add(GeneratedTeamMemberPlan.fromJson(raw.cast<String, Object?>()));
    }
    final resources = json['resources'];
    Map<String, Object?> resourcesMap = const {};
    if (resources != null) {
      if (resources is! Map) {
        throw const FormatException('plan.resources must be an object');
      }
      resourcesMap = resources.cast<String, Object?>();
    }
    _checkExactKeys(
      resourcesMap,
      const ['skillIds', 'pluginIds', 'mcpServerIds'],
      optional: true,
    );
    List<String> idList(String key) => [
      for (final value in (resourcesMap[key] as List? ?? const []))
        if (value is String && value.trim().isNotEmpty) value.trim(),
    ];
    final mode = (teamMap['mode'] as String? ?? '').trim();
    return GeneratedTeamPlan(
      teamName: (teamMap['name'] as String? ?? '').trim(),
      teamDescription: (teamMap['description'] as String? ?? '').trim(),
      mode: mode,
      members: members,
      skillIds: idList('skillIds'),
      pluginIds: idList('pluginIds'),
      mcpServerIds: idList('mcpServerIds'),
      revision: '',
    );
  }

  final String teamName;
  final String teamDescription;

  /// Requested team mode: must equal the frozen settings mode at validation.
  final String mode;
  final List<GeneratedTeamMemberPlan> members;
  final List<String> skillIds;
  final List<String> pluginIds;
  final List<String> mcpServerIds;

  /// SHA-256 over canonical JSON (map keys recursively sorted).
  final String revision;

  bool get hasLead =>
      members.where((member) => member.name == 'team-lead').length == 1;

  Map<String, Object?> toCanonicalJson() => _sortJson({
    'schemaVersion': schemaVersion,
    'team': {
      'name': teamName,
      'description': teamDescription,
      'mode': mode,
    },
    'members': [
      for (final member in members) member.toCanonicalJson(),
    ],
    'resources': {
      'skillIds': skillIds,
      'pluginIds': pluginIds,
      'mcpServerIds': mcpServerIds,
    },
  });

  String canonicalJson() => jsonEncode(toCanonicalJson());

  String computeRevision() =>
      sha256.convert(utf8.encode(canonicalJson())).toString();

  Map<String, Object?> toJson() => toCanonicalJson();

  static void _checkTopLevelKeys(Map<String, Object?> json) {
    if (json.containsKey('schemaVersion') &&
        (json['schemaVersion'] as num?)?.toInt() != schemaVersion) {
      throw const FormatException('unsupported plan schemaVersion');
    }
    _checkExactKeys(
      json,
      const ['schemaVersion', 'team', 'members', 'resources'],
      optional: true,
    );
  }

  static void _checkExactKeys(
    Map<String, Object?> json,
    List<String> allowed, {
    bool optional = false,
  }) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('unknown plan key: $key');
      }
    }
    if (!optional) {
      for (final key in allowed) {
        if (key == 'schemaVersion') continue;
        if (!json.containsKey(key)) {
          throw FormatException('missing plan key: $key');
        }
      }
    }
  }
}

final class GeneratedTeamMemberPlan {
  const GeneratedTeamMemberPlan({
    required this.name,
    required this.role,
    required this.responsibilities,
    required this.workingMethod,
    required this.presetId,
    required this.replicas,
    required this.placement,
  });

  factory GeneratedTeamMemberPlan.fromJson(Map<String, Object?> json) {
    GeneratedTeamPlan._checkExactKeys(
      json,
      const [
        'name',
        'role',
        'responsibilities',
        'workingMethod',
        'presetId',
        'replicas',
        'placement',
      ],
      optional: true,
    );
    final replicasRaw = json['replicas'];
    final replicas = replicasRaw is int ? replicasRaw : null;
    if (replicas == null || replicas < 1 || replicas > 8) {
      throw const FormatException('replicas must be an int in 1..8');
    }
    final placementRaw = json['placement'];
    final placement = <String, int>{};
    if (placementRaw != null) {
      if (placementRaw is! Map) {
        throw const FormatException('placement must be an object');
      }
      placementRaw.forEach((key, value) {
        if (value is! int || value < 0) {
          throw const FormatException('placement counts must be non-negative ints');
        }
        placement['$key'.trim()] = value;
      });
    }
    final presetIdRaw = json['presetId'];
    final name = (json['name'] as String? ?? '').trim();
    final role = (json['role'] as String? ?? '').trim();
    final responsibilities = (json['responsibilities'] as String? ?? '').trim();
    final workingMethod = (json['workingMethod'] as String? ?? '').trim();
    if (name.isEmpty || role.isEmpty || responsibilities.isEmpty ||
        workingMethod.isEmpty) {
      throw const FormatException(
        'member name/role/responsibilities/workingMethod must be non-blank',
      );
    }
    return GeneratedTeamMemberPlan(
      name: name,
      role: role,
      responsibilities: responsibilities,
      workingMethod: workingMethod,
      presetId: presetIdRaw is String ? presetIdRaw.trim() : '',
      replicas: replicas,
      placement: placement,
    );
  }

  final String name;
  final String role;
  final String responsibilities;
  final String workingMethod;

  /// Blank/absent means inherit the fixed team default.
  final String presetId;
  final int replicas;
  final Map<String, int> placement;

  Map<String, Object?> toCanonicalJson() => {
    'name': name,
    'role': role,
    'responsibilities': responsibilities,
    'workingMethod': workingMethod,
    'presetId': presetId,
    'replicas': replicas,
    'placement': placement,
  };
}

Map<String, Object?> _sortJson(Map<String, Object?> json) {
  final out = <String, Object?>{};
  for (final key in (json.keys.toList()..sort())) {
    final value = json[key];
    if (value is Map<String, Object?>) {
      out[key] = _sortJson(value);
    } else if (value is List) {
      out[key] = [
        for (final item in value)
          if (item is Map<String, Object?>) _sortJson(item) else item,
      ];
    } else {
      out[key] = value;
    }
  }
  return out;
}

/// Encodes bytes to hex without importing convert in every caller.
String planSha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Used by the validator when hashing expert keys.
String generatedExpertKeyJson(Map<String, Object?> canonical) =>
    jsonEncode(_sortJson(canonical));

String generatedExpertKeyFrom(String canonicalJson) =>
    sha256.convert(utf8.encode(canonicalJson)).toString().substring(0, 24);

String utf8Of(String value) => value;
