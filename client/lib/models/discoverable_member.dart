import 'package:flutter/foundation.dart';

import 'discoverable_team.dart';
import 'team_config.dart';

enum ExpertMemberSource {
  builtin('builtin'),
  registry('registry'),
  teamExtract('teamExtract'),
  local('local'),
  clone('clone');

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

/// Optional per-locale overlay for hub display fields (default language stays
/// on the root [DiscoverableMember] fields).
@immutable
class DiscoverableMemberLocaleText {
  const DiscoverableMemberLocaleText({
    this.name,
    this.description,
    this.category,
    this.responsibilities,
    this.playbook,
  });

  final String? name;
  final String? description;
  final String? category;
  final String? responsibilities;
  final String? playbook;

  factory DiscoverableMemberLocaleText.fromJson(Map<String, Object?> json) {
    String? pick(String key) {
      final v = (json[key] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final memberRaw = json['member'];
    final member = memberRaw is Map
        ? memberRaw.cast<String, Object?>()
        : const <String, Object?>{};
    final nestedResponsibilities = (member['responsibilities'] as String?)
        ?.trim();
    final nestedPlaybook = (member['playbook'] as String?)?.trim();
    return DiscoverableMemberLocaleText(
      name: pick('name'),
      description: pick('description'),
      category: pick('category'),
      responsibilities: pick('responsibilities') ??
          (nestedResponsibilities == null || nestedResponsibilities.isEmpty
              ? null
              : nestedResponsibilities),
      playbook: pick('playbook') ??
          (nestedPlaybook == null || nestedPlaybook.isEmpty
              ? null
              : nestedPlaybook),
    );
  }

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (category != null) 'category': category,
    if (responsibilities != null || playbook != null)
      'member': {
        if (responsibilities != null) 'responsibilities': responsibilities,
        if (playbook != null) 'playbook': playbook,
      },
  };

  @override
  bool operator ==(Object other) =>
      other is DiscoverableMemberLocaleText &&
      name == other.name &&
      description == other.description &&
      category == other.category &&
      responsibilities == other.responsibilities &&
      playbook == other.playbook;

  @override
  int get hashCode =>
      Object.hash(name, description, category, responsibilities, playbook);
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
    this.pluginDeps = const [],
    this.mcpDeps = const [],
    this.originTeamKey,
    this.clonedAt,
    this.i18n = const {},
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
  final List<PluginDependencyRef> pluginDeps;
  final List<McpDependencyRef> mcpDeps;
  final ExpertMemberSource source;
  final String? originTeamKey;

  /// Epoch ms when this entry was cloned from the catalog (refresh seed).
  final int? clonedAt;

  /// Locale overlays keyed by language code (`zh`, `ja`, …). Root fields are
  /// the default / fallback language (typically English).
  final Map<String, DiscoverableMemberLocaleText> i18n;

  factory DiscoverableMember.fromJson(Map<String, Object?> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, Object?>) f) =>
        raw is List
        ? raw
              .whereType<Map>()
              .map((m) => f(m.cast<String, Object?>()))
              .toList(growable: false)
        : const [];
    final i18nRaw = json['i18n'];
    final i18n = <String, DiscoverableMemberLocaleText>{};
    if (i18nRaw is Map) {
      for (final entry in i18nRaw.entries) {
        final lang = entry.key.toString().trim().toLowerCase();
        final value = entry.value;
        if (lang.isEmpty || value is! Map) continue;
        i18n[lang] = DiscoverableMemberLocaleText.fromJson(
          value.cast<String, Object?>(),
        );
      }
    }
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
      pluginDeps: list(json['pluginDeps'], PluginDependencyRef.fromJson),
      mcpDeps: list(json['mcpDeps'], McpDependencyRef.fromJson),
      source: ExpertMemberSource.decode(json['source']),
      originTeamKey: json['originTeamKey'] as String?,
      clonedAt: (json['clonedAt'] as num?)?.toInt(),
      i18n: i18n,
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
    if (pluginDeps.isNotEmpty)
      'pluginDeps': pluginDeps.map((d) => d.toJson()).toList(),
    if (mcpDeps.isNotEmpty) 'mcpDeps': mcpDeps.map((d) => d.toJson()).toList(),
    'source': source.value,
    if (originTeamKey != null && originTeamKey!.isNotEmpty)
      'originTeamKey': originTeamKey,
    if (clonedAt != null && clonedAt! > 0) 'clonedAt': clonedAt,
    if (i18n.isNotEmpty)
      'i18n': {
        for (final e in i18n.entries) e.key: e.value.toJson(),
      },
  };

  /// Returns a copy with display fields overlaid for [languageCode]
  /// (`zh-CN` → `zh`). Missing locale falls back to root fields. The returned
  /// member keeps [i18n] so further locale switches still work.
  DiscoverableMember forLocale(String languageCode) {
    final overlay = _overlayFor(languageCode);
    if (overlay == null) return this;
    return DiscoverableMember(
      key: key,
      name: overlay.name ?? name,
      description: overlay.description ?? description,
      category: overlay.category ?? category,
      source: source,
      member: DiscoverableTeamMember(
        name: member.name,
        provider: member.provider,
        model: member.model,
        agent: member.agent,
        agentType: member.agentType,
        capabilities: member.capabilities,
        replicas: member.replicas,
        responsibilities: overlay.responsibilities ?? member.responsibilities,
        playbook: overlay.playbook ?? member.playbook,
        extraArgs: member.extraArgs,
      ),
      author: author,
      updatedAt: updatedAt,
      tags: tags,
      skillDeps: skillDeps,
      pluginDeps: pluginDeps,
      mcpDeps: mcpDeps,
      originTeamKey: originTeamKey,
      clonedAt: clonedAt,
      i18n: i18n,
    );
  }

  DiscoverableMember copyWith({
    String? key,
    String? name,
    String? description,
    String? category,
    String? author,
    int? updatedAt,
    Set<String>? tags,
    DiscoverableTeamMember? member,
    List<SkillDependencyRef>? skillDeps,
    List<PluginDependencyRef>? pluginDeps,
    List<McpDependencyRef>? mcpDeps,
    ExpertMemberSource? source,
    String? originTeamKey,
    int? clonedAt,
    Map<String, DiscoverableMemberLocaleText>? i18n,
  }) {
    return DiscoverableMember(
      key: key ?? this.key,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      author: author ?? this.author,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      member: member ?? this.member,
      skillDeps: skillDeps ?? this.skillDeps,
      pluginDeps: pluginDeps ?? this.pluginDeps,
      mcpDeps: mcpDeps ?? this.mcpDeps,
      source: source ?? this.source,
      originTeamKey: originTeamKey ?? this.originTeamKey,
      clonedAt: clonedAt ?? this.clonedAt,
      i18n: i18n ?? this.i18n,
    );
  }

  DiscoverableMemberLocaleText? _overlayFor(String languageCode) {
    final raw = languageCode.trim().toLowerCase();
    if (raw.isEmpty || i18n.isEmpty) return null;
    final exact = i18n[raw];
    if (exact != null) return exact;
    final primary = raw.split(RegExp(r'[_-]')).first;
    return i18n[primary];
  }

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
      listEquals(pluginDeps, other.pluginDeps) &&
      listEquals(mcpDeps, other.mcpDeps) &&
      source == other.source &&
      originTeamKey == other.originTeamKey &&
      clonedAt == other.clonedAt &&
      mapEquals(i18n, other.i18n);

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
    Object.hashAll(pluginDeps),
    Object.hashAll(mcpDeps),
    source,
    originTeamKey,
    clonedAt,
    Object.hashAll(i18n.entries.map((e) => Object.hash(e.key, e.value))),
  );
}
