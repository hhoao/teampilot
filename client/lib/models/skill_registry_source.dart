import 'package:flutter/foundation.dart';

enum SkillRegistryKind { gitRepo, api }

enum SkillRegistryProtocol { skillsSh, skillsMp }

@immutable
class SkillRegistrySourceConfig {
  const SkillRegistrySourceConfig({
    required this.id,
    required this.kind,
    required this.label,
    this.protocol,
    this.enabled = true,
    this.baseUrl,
    this.apiToken,
    this.browseQuery,
    this.gitOwner,
    this.gitName,
    this.gitBranch,
  });

  final String id;
  final SkillRegistryKind kind;
  final String label;
  final SkillRegistryProtocol? protocol;
  final bool enabled;
  final String? baseUrl;
  final String? apiToken;
  final String? browseQuery;
  final String? gitOwner;
  final String? gitName;
  final String? gitBranch;

  bool get hasApiToken => apiToken != null && apiToken!.trim().isNotEmpty;

  String get githubUrl =>
      'https://github.com/$gitOwner/$gitName';

  static String defaultBaseUrl(SkillRegistryProtocol protocol) =>
      switch (protocol) {
        SkillRegistryProtocol.skillsSh => 'https://skills.sh',
        SkillRegistryProtocol.skillsMp => 'https://skillsmp.com/api/v1',
      };

  String get baseUrlOrDefault {
    final url = baseUrl?.trim();
    if (url != null && url.isNotEmpty) return url;
    final p = protocol;
    return p == null ? '' : defaultBaseUrl(p);
  }

  SkillRegistrySourceConfig copyWith({
    String? label,
    bool? enabled,
    String? baseUrl,
    String? apiToken,
    bool clearApiToken = false,
    String? browseQuery,
    String? gitOwner,
    String? gitName,
    String? gitBranch,
  }) => SkillRegistrySourceConfig(
    id: id,
    kind: kind,
    label: label ?? this.label,
    protocol: protocol,
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl ?? this.baseUrl,
    apiToken: clearApiToken ? null : (apiToken ?? this.apiToken),
    browseQuery: browseQuery ?? this.browseQuery,
    gitOwner: gitOwner ?? this.gitOwner,
    gitName: gitName ?? this.gitName,
    gitBranch: gitBranch ?? this.gitBranch,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind == SkillRegistryKind.api ? 'api' : 'git',
    'label': label,
    if (kind == SkillRegistryKind.api) 'protocol': protocol == SkillRegistryProtocol.skillsMp ? 'skillsMp' : 'skillsSh',
    'enabled': enabled,
    if (kind == SkillRegistryKind.api) ...{
      if (baseUrl != null && baseUrl!.trim().isNotEmpty) 'baseUrl': baseUrl,
      if (hasApiToken) 'apiToken': apiToken!.trim(),
      if (browseQuery != null && browseQuery!.trim().isNotEmpty) 'browseQuery': browseQuery,
    } else ...{
      if (gitOwner != null && gitOwner!.isNotEmpty) 'gitOwner': gitOwner,
      if (gitName != null && gitName!.isNotEmpty) 'gitName': gitName,
      if (gitBranch != null && gitBranch!.isNotEmpty) 'gitBranch': gitBranch,
    },
  };

  factory SkillRegistrySourceConfig.fromJson(Map<String, Object?> json) {
    final kind = (json['kind'] as String?) == 'git'
        ? SkillRegistryKind.gitRepo
        : SkillRegistryKind.api;
    final protocolRaw = (json['protocol'] as String?)?.trim().toLowerCase();
    final protocol = protocolRaw == 'skillsmp'
        ? SkillRegistryProtocol.skillsMp
        : SkillRegistryProtocol.skillsSh;
    return SkillRegistrySourceConfig(
      id: json['id'] as String? ?? '',
      kind: kind,
      label: json['label'] as String? ?? '',
      protocol: kind == SkillRegistryKind.api ? protocol : null,
      enabled: json['enabled'] as bool? ?? true,
      baseUrl: json['baseUrl'] as String?,
      apiToken: json['apiToken'] as String?,
      browseQuery: json['browseQuery'] as String?,
      gitOwner: json['gitOwner'] as String?,
      gitName: json['gitName'] as String?,
      gitBranch: json['gitBranch'] as String? ?? 'main',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillRegistrySourceConfig &&
          id == other.id &&
          kind == other.kind &&
          label == other.label &&
          protocol == other.protocol &&
          enabled == other.enabled &&
          baseUrl == other.baseUrl &&
          apiToken == other.apiToken &&
          browseQuery == other.browseQuery &&
          gitOwner == other.gitOwner &&
          gitName == other.gitName &&
          gitBranch == other.gitBranch;

  @override
  int get hashCode => Object.hash(
    id, kind, label, protocol, enabled, baseUrl, apiToken,
    browseQuery, gitOwner, gitName, gitBranch,
  );
}

@immutable
class SkillRegistriesConfig {
  const SkillRegistriesConfig({required this.sources});

  final List<SkillRegistrySourceConfig> sources;

  static const _defaultGitRepos = [
    ('anthropics', 'skills', 'main'),
    ('ComposioHQ', 'awesome-claude-skills', 'master'),
    ('cexll', 'myclaude', 'master'),
    ('JimLiu', 'baoyu-skills', 'main'),
  ];

  static SkillRegistriesConfig defaults() => SkillRegistriesConfig(
    sources: [
      SkillRegistrySourceConfig(
        id: 'skillsSh',
        kind: SkillRegistryKind.api,
        label: 'skills.sh',
        protocol: SkillRegistryProtocol.skillsSh,
        baseUrl: SkillRegistrySourceConfig.defaultBaseUrl(SkillRegistryProtocol.skillsSh),
        browseQuery: 'ai',
      ),
      SkillRegistrySourceConfig(
        id: 'skillsMp',
        kind: SkillRegistryKind.api,
        label: 'SkillsMP',
        protocol: SkillRegistryProtocol.skillsMp,
        baseUrl: SkillRegistrySourceConfig.defaultBaseUrl(SkillRegistryProtocol.skillsMp),
      ),
      for (final (owner, name, branch) in _defaultGitRepos)
        SkillRegistrySourceConfig(
          id: 'git-$owner-$name',
          kind: SkillRegistryKind.gitRepo,
          label: '$owner/$name',
          gitOwner: owner,
          gitName: name,
          gitBranch: branch,
        ),
    ],
  );

  SkillRegistrySourceConfig? byId(String id) {
    for (final s in sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'sources': sources.map((s) => s.toJson()).toList(),
  };

  factory SkillRegistriesConfig.fromJson(Map<String, Object?> json) {
    final raw = json['sources'];
    if (raw is! List || raw.isEmpty) return defaults();
    final parsed = raw
        .whereType<Map>()
        .map((m) => SkillRegistrySourceConfig.fromJson(m.cast<String, Object?>()))
        .toList();
    final byId = <String, SkillRegistrySourceConfig>{
      for (final s in parsed) s.id: s,
    };
    final d = defaults();
    final merged = <SkillRegistrySourceConfig>[
      byId['skillsSh'] ?? d.byId('skillsSh')!,
      byId['skillsMp'] ?? d.byId('skillsMp')!,
      for (final s in parsed)
        if (s.id != 'skillsSh' && s.id != 'skillsMp') s,
    ];
    return SkillRegistriesConfig(sources: merged);
  }
}
