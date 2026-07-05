import 'package:flutter/foundation.dart';

import 'discoverable_team.dart';
import 'team_config.dart';

enum ExpertMemberSource {
  builtin('builtin'),
  registry('registry'),
  teamExtract('teamExtract'),
  local('local');

  const ExpertMemberSource(this.value);

  final String value;

  static ExpertMemberSource decode(Object? raw) =>
      tryParse(raw?.toString()) ?? ExpertMemberSource.builtin;

  static ExpertMemberSource? tryParse(String? raw) {
    final normalized = raw?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final source in ExpertMemberSource.values) {
      if (source.value == normalized) return source;
    }
    return null;
  }
}

/// A public member persona as listed in an Expert Hub registry manifest.
@immutable
class DiscoverableMember {
  const DiscoverableMember({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.source,
    required this.member,
    this.author,
    this.updatedAt = 0,
    this.tags = const {},
    this.skillDeps = const [],
    this.originTeamKey,
  });

  /// Unique discovery key: `owner/name/slug`, `local/{uuid}`, or `{teamKey}#{slug}`.
  final String key;
  final String name;
  final String description;
  final String category;
  final String? author;
  final int updatedAt;
  final Set<String> tags;
  final DiscoverableTeamMember member;
  final List<SkillDependencyRef> skillDeps;
  final ExpertMemberSource source;
  final String? originTeamKey;

  factory DiscoverableMember.fromJson(Map<String, Object?> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, Object?>) f) =>
        raw is List
        ? raw
              .whereType<Map>()
              .map((m) => f(m.cast<String, Object?>()))
              .toList(growable: false)
        : const [];
    return DiscoverableMember(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      author: json['author'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      tags: {
        for (final t in (json['tags'] as List?) ?? const [])
          if (t is String && t.trim().isNotEmpty) t.trim(),
      },
      member: DiscoverableTeamMember.fromJson(
        (json['member'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      skillDeps: list(json['skillDeps'], SkillDependencyRef.fromJson),
      source: ExpertMemberSource.decode(json['source']),
      originTeamKey: json['originTeamKey'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'description': description,
    'category': category,
    if (author != null) 'author': author,
    if (updatedAt != 0) 'updatedAt': updatedAt,
    if (tags.isNotEmpty) 'tags': tags.toList(),
    'member': member.toJson(),
    if (skillDeps.isNotEmpty) 'skillDeps': skillDeps.map((d) => d.toJson()).toList(),
    'source': source.value,
    if (originTeamKey != null && originTeamKey!.isNotEmpty)
      'originTeamKey': originTeamKey,
  };

  TeamMemberConfig toMemberConfig({required int joinedAt, String? idOverride}) {
    final base = member.toMemberConfig(joinedAt: joinedAt);
    final displayName = name.trim().isNotEmpty ? name.trim() : base.name;
    if (idOverride == null && displayName == base.name) return base;
    return base.copyWith(
      id: idOverride ?? base.id,
      name: displayName,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoverableMember &&
      key == other.key &&
      name == other.name &&
      description == other.description &&
      category == other.category &&
      author == other.author &&
      updatedAt == other.updatedAt &&
      setEquals(tags, other.tags) &&
      member == other.member &&
      listEquals(skillDeps, other.skillDeps) &&
      source == other.source &&
      originTeamKey == other.originTeamKey;

  @override
  int get hashCode => Object.hash(
    key,
    name,
    description,
    category,
    author,
    updatedAt,
    Object.hashAllUnordered(tags),
    member,
    Object.hashAll(skillDeps),
    source,
    originTeamKey,
  );
}
