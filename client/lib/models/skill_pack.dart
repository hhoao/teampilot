import 'package:flutter/foundation.dart';

import 'skill_acquire_spec.dart';

/// One skill published inside a [SkillPack].
@immutable
class SkillPackEntry {
  const SkillPackEntry({
    required this.id,
    required this.directory,
    required this.name,
  });

  final String id;
  final String directory;
  final String name;

  factory SkillPackEntry.fromJson(Map<String, Object?> json) => SkillPackEntry(
    id: (json['id'] as String?)?.trim() ?? '',
    directory: (json['directory'] as String?)?.trim() ?? '',
    name: (json['name'] as String?)?.trim() ?? '',
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'directory': directory,
    'name': name,
  };
}

/// Install-once unit that registers many skills from one git repo (or script).
@immutable
class SkillPack {
  const SkillPack({
    required this.id,
    required this.name,
    required this.repoOwner,
    required this.repoName,
    required this.repoBranch,
    required this.acquire,
    required this.skills,
  });

  final String id;
  final String name;
  final String repoOwner;
  final String repoName;
  final String repoBranch;
  final SkillAcquireSpec acquire;
  final List<SkillPackEntry> skills;

  factory SkillPack.fromJson(Map<String, Object?> json) {
    final acquireRaw = json['acquire'];
    final skillsRaw = json['skills'];
    return SkillPack(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      repoOwner: (json['repoOwner'] as String?)?.trim() ?? '',
      repoName: (json['repoName'] as String?)?.trim() ?? '',
      repoBranch: (json['repoBranch'] as String?)?.trim() ?? 'main',
      acquire: acquireRaw is Map
          ? SkillAcquireSpec.fromJson(acquireRaw.cast<String, Object?>())
          : const SkillAcquireSpec(kind: 'git-pack'),
      skills: skillsRaw is List
          ? skillsRaw
                .whereType<Map>()
                .map((e) => SkillPackEntry.fromJson(e.cast<String, Object?>()))
                .where((e) => e.id.isNotEmpty && e.directory.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'repoOwner': repoOwner,
    'repoName': repoName,
    'repoBranch': repoBranch,
    'acquire': acquire.toJson(),
    'skills': [for (final s in skills) s.toJson()],
  };

  SkillPackEntry? entryById(String skillId) {
    for (final s in skills) {
      if (s.id == skillId) return s;
    }
    return null;
  }
}
