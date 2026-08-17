import 'catalog/catalog_types.dart';
import 'skill_pack_instruction.dart';

Map<String, Object?>? _catalogMetricsToJson(CatalogMetrics metrics) {
  final json = <String, Object?>{
    if (metrics.adoptionCount != null) 'adoptionCount': metrics.adoptionCount,
    if (metrics.rating != null) 'rating': metrics.rating,
    if (metrics.ratingCount != null) 'ratingCount': metrics.ratingCount,
    if (metrics.updatedAtMs != null) 'updatedAtMs': metrics.updatedAtMs,
    if (metrics.publishedAtMs != null) 'publishedAtMs': metrics.publishedAtMs,
  };
  return json.isEmpty ? null : json;
}

CatalogMetrics _catalogMetricsFromJson(Object? raw) {
  if (raw is! Map) return const CatalogMetrics();
  final json = raw.cast<String, Object?>();
  return CatalogMetrics(
    adoptionCount: (json['adoptionCount'] as num?)?.toInt(),
    rating: (json['rating'] as num?)?.toDouble(),
    ratingCount: (json['ratingCount'] as num?)?.toInt(),
    updatedAtMs: (json['updatedAtMs'] as num?)?.toInt(),
    publishedAtMs: (json['publishedAtMs'] as num?)?.toInt(),
  );
}

class Skill {
  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.directory,
    this.repoOwner,
    this.repoName,
    this.repoBranch,
    this.readmeUrl,
    this.enabled = true,
    required this.installedAt,
    this.contentHash,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String directory;
  final String? repoOwner;
  final String? repoName;
  final String? repoBranch;
  final String? readmeUrl;
  final bool enabled;
  final int installedAt;
  final String? contentHash;
  final int updatedAt;

  String get source => repoOwner != null ? '$repoOwner/$repoName' : 'local';

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    String? directory,
    String? repoOwner,
    String? repoName,
    String? repoBranch,
    String? readmeUrl,
    bool? enabled,
    int? installedAt,
    String? contentHash,
    int? updatedAt,
    bool clearRepo = false,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      directory: directory ?? this.directory,
      repoOwner: clearRepo ? null : (repoOwner ?? this.repoOwner),
      repoName: clearRepo ? null : (repoName ?? this.repoName),
      repoBranch: clearRepo ? null : (repoBranch ?? this.repoBranch),
      readmeUrl: clearRepo ? null : (readmeUrl ?? this.readmeUrl),
      enabled: enabled ?? this.enabled,
      installedAt: installedAt ?? this.installedAt,
      contentHash: contentHash ?? this.contentHash,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'directory': directory,
    'repoOwner': repoOwner,
    'repoName': repoName,
    'repoBranch': repoBranch,
    'readmeUrl': readmeUrl,
    'enabled': enabled,
    'installedAt': installedAt,
    'contentHash': contentHash,
    'updatedAt': updatedAt,
  };

  factory Skill.fromJson(Map<String, Object?> json) => Skill(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    directory: json['directory'] as String,
    repoOwner: json['repoOwner'] as String?,
    repoName: json['repoName'] as String?,
    repoBranch: json['repoBranch'] as String?,
    readmeUrl: json['readmeUrl'] as String?,
    enabled: json['enabled'] as bool? ?? true,
    installedAt: json['installedAt'] as int,
    contentHash: json['contentHash'] as String?,
    updatedAt: json['updatedAt'] as int,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Skill &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          directory == other.directory &&
          enabled == other.enabled &&
          contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(id, name, directory, enabled, contentHash);
}

class SkillRepo {
  const SkillRepo({
    required this.owner,
    required this.name,
    this.branch = 'main',
    this.enabled = true,
  });

  final String owner;
  final String name;
  final String branch;
  final bool enabled;

  String get fullName => '$owner/$name';

  String get githubUrl => 'https://github.com/$owner/$name';

  SkillRepo copyWith({
    String? owner,
    String? name,
    String? branch,
    bool? enabled,
  }) => SkillRepo(
    owner: owner ?? this.owner,
    name: name ?? this.name,
    branch: branch ?? this.branch,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'owner': owner,
    'name': name,
    'branch': branch,
    'enabled': enabled,
  };

  factory SkillRepo.fromJson(Map<String, Object?> json) => SkillRepo(
    owner: json['owner'] as String,
    name: json['name'] as String,
    branch: json['branch'] as String? ?? 'main',
    enabled: json['enabled'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillRepo &&
          runtimeType == other.runtimeType &&
          owner == other.owner &&
          name == other.name &&
          branch == other.branch &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(owner, name, branch, enabled);
}

class SkillUpdateInfo {
  const SkillUpdateInfo({
    required this.id,
    required this.name,
    required this.remoteHash,
    this.currentHash,
  });

  final String id;
  final String name;
  final String? currentHash;
  final String remoteHash;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'currentHash': currentHash,
    'remoteHash': remoteHash,
  };

  factory SkillUpdateInfo.fromJson(Map<String, Object?> json) =>
      SkillUpdateInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        currentHash: json['currentHash'] as String?,
        remoteHash: json['remoteHash'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillUpdateInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          remoteHash == other.remoteHash;

  @override
  int get hashCode => Object.hash(id, remoteHash);
}

class SkillBackup {
  const SkillBackup({
    required this.backupId,
    required this.backupPath,
    required this.createdAt,
    required this.skill,
  });

  final String backupId;
  final String backupPath;
  final int createdAt;
  final Skill skill;

  Map<String, Object?> toJson() => {
    'backupId': backupId,
    'backupPath': backupPath,
    'createdAt': createdAt,
    'skill': skill.toJson(),
  };

  factory SkillBackup.fromJson(Map<String, Object?> json) => SkillBackup(
    backupId: json['backupId'] as String,
    backupPath: json['backupPath'] as String,
    createdAt: json['createdAt'] as int,
    skill: Skill.fromJson((json['skill'] as Map).cast<String, Object?>()),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillBackup &&
          runtimeType == other.runtimeType &&
          backupId == other.backupId;

  @override
  int get hashCode => backupId.hashCode;
}

class UnmanagedSkill {
  const UnmanagedSkill({
    required this.directory,
    required this.name,
    required this.path,
    this.description,
  });

  final String directory;
  final String name;
  final String? description;
  final String path;
}

class SkillsShEntry {
  const SkillsShEntry({
    required this.key,
    required this.name,
    required this.directory,
    required this.repoOwner,
    required this.repoName,
    required this.repoBranch,
    required this.installs,
    this.metrics = const CatalogMetrics(),
    this.readmeUrl,
  });

  final String key;
  final String name;
  final String directory;
  final String repoOwner;
  final String repoName;
  final String repoBranch;
  final String? readmeUrl;
  final int installs;
  final CatalogMetrics metrics;
}

class DiscoverableSkill {
  const DiscoverableSkill({
    required this.key,
    required this.name,
    required this.description,
    required this.directory,
    this.readmeUrl,
    required this.repoOwner,
    required this.repoName,
    required this.repoBranch,
    this.id,
    this.packId,
    this.install,
    this.scriptUrl,
    this.metrics = const CatalogMetrics(),
  });

  final String key;
  final String name;
  final String description;
  final String directory;
  final String? readmeUrl;
  final String repoOwner;
  final String repoName;
  final String repoBranch;

  /// Optional explicit local skill id (preferred for script / pack acquire).
  final String? id;
  final String? packId;

  /// Inline Dockerfile-like install when not using [packId].
  final List<SkillPackInstruction>? install;

  /// HTTPS installer URL sugar (synthesizes a [ScriptInstruction]).
  final String? scriptUrl;

  final CatalogMetrics metrics;

  String get source => '$repoOwner/$repoName';

  /// Resolved install AST for non-pack skills. Pack skills return null
  /// (engine loads the pack's `install`).
  List<SkillPackInstruction>? get resolvedInstall {
    if (packId != null && packId!.trim().isNotEmpty) return null;
    if (install != null && install!.isNotEmpty) return install;
    if (repoOwner.isNotEmpty && repoName.isNotEmpty && directory.isNotEmpty) {
      final branch = repoBranch.isEmpty ? 'main' : repoBranch;
      return [
        FromInstruction.parseRef('$repoOwner/$repoName@$branch'),
        SkillsInstruction(includeAll: false, include: [directory]),
      ];
    }
    final script = scriptUrl?.trim();
    if (script != null && script.isNotEmpty) {
      return [
        ScriptInstruction(
          url: script,
          id: expectedLocalId,
          primaryDirectory: directory.isEmpty ? null : directory,
        ),
      ];
    }
    return null;
  }

  /// Primary local [Skill.id] for install via [SkillAcquisitionEngine].
  String get expectedLocalId {
    final explicit = id?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final k = key.trim();
    if (k.isNotEmpty) return k;
    final pack = packId?.trim();
    if (pack != null && pack.isNotEmpty) {
      final basename = directory.split('/').last;
      return '$pack:$basename';
    }
    final script = scriptUrl?.trim();
    if (script != null && script.isNotEmpty) {
      return skillScriptIdFromPackageUrl(script);
    }
    final basename = directory.split('/').last;
    if (repoOwner.isNotEmpty && repoName.isNotEmpty && basename.isNotEmpty) {
      return '$repoOwner/$repoName:$basename';
    }
    return basename.isEmpty ? 'local:unknown' : 'local:$basename';
  }

  Map<String, Object?> toJson() {
    final metricsJson = _catalogMetricsToJson(metrics);
    return {
      'key': key,
      'name': name,
      'description': description,
      'directory': directory,
      'readmeUrl': readmeUrl,
      'repoOwner': repoOwner,
      'repoName': repoName,
      'repoBranch': repoBranch,
      if (id != null && id!.isNotEmpty) 'id': id,
      if (packId != null && packId!.isNotEmpty) 'packId': packId,
      if (scriptUrl != null && scriptUrl!.isNotEmpty) 'scriptUrl': scriptUrl,
      if (install != null && install!.isNotEmpty)
        'install': [
          for (final step in install!) _discoverableInstallToJson(step),
        ],
      if (metricsJson != null) 'metrics': metricsJson,
    };
  }

  factory DiscoverableSkill.fromJson(Map<String, Object?> json) {
    if (json.containsKey('recipe')) {
      throw const FormatException(
        'DiscoverableSkill.recipe is no longer supported; use install/scriptUrl',
      );
    }
    final idRaw = (json['id'] as String?)?.trim();
    final packRaw = (json['packId'] as String?)?.trim();
    final scriptRaw = (json['scriptUrl'] as String?)?.trim();
    final installRaw = json['install'];
    return DiscoverableSkill(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      directory: json['directory'] as String? ?? '',
      readmeUrl: json['readmeUrl'] as String?,
      repoOwner: json['repoOwner'] as String? ?? '',
      repoName: json['repoName'] as String? ?? '',
      repoBranch: json['repoBranch'] as String? ?? '',
      id: idRaw == null || idRaw.isEmpty ? null : idRaw,
      packId: packRaw == null || packRaw.isEmpty ? null : packRaw,
      scriptUrl: scriptRaw == null || scriptRaw.isEmpty ? null : scriptRaw,
      install: installRaw is List ? parseSkillPackInstall(installRaw) : null,
      metrics: _catalogMetricsFromJson(json['metrics']),
    );
  }
}

Map<String, Object?> _discoverableInstallToJson(SkillPackInstruction step) {
  // Reuse pack serialization via a throwaway SkillPack field helper is heavy;
  // encode the common cases used in deps.
  return switch (step) {
    FromInstruction(:final owner, :final name, :final branch) => {
      'FROM': '$owner/$name@$branch',
    },
    ScriptInstruction(
      :final url,
      :final id,
      :final primaryDirectory,
      :final alternatives,
      :final optional,
    ) =>
      {
        'SCRIPT': {
          'url': url,
          if (id != null && id.isNotEmpty) 'id': id,
          if (primaryDirectory != null && primaryDirectory.isNotEmpty)
            'primaryDirectory': primaryDirectory,
          if (alternatives.isNotEmpty) 'alternatives': alternatives,
        },
        if (optional) 'optional': true,
      },
    SkillsInstruction(:final includeAll, :final include, :final exclude) => {
      'SKILLS': includeAll && exclude.isEmpty
          ? '*'
          : {
              if (includeAll) 'include': '*',
              if (!includeAll) 'include': include,
              if (exclude.isNotEmpty) 'exclude': exclude,
            },
    },
    PathInstruction(:final entries) => {
      'PATH': entries.length == 1 ? entries.single : entries,
    },
    EnvInstruction(:final entries) => {'ENV': entries},
    RunInstruction(:final shell, :final exec, :final optional) => {
      'RUN': shell ?? exec,
      if (optional) 'optional': true,
    },
    ShellInstruction(:final wrapper) => {'SHELL': wrapper},
    WorkdirInstruction(:final path) => {'WORKDIR': path},
    CopyInstruction(:final from, :final to) => {
      'COPY': [from, to],
    },
  };
}
