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

  String get source =>
      repoOwner != null ? '$repoOwner/$repoName' : 'local';

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

  SkillRepo copyWith({String? owner, String? name, String? branch, bool? enabled}) =>
      SkillRepo(
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
          name == other.name;

  @override
  int get hashCode => Object.hash(owner, name);
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

  factory SkillUpdateInfo.fromJson(Map<String, Object?> json) => SkillUpdateInfo(
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
    skill: Skill.fromJson(
      (json['skill'] as Map).cast<String, Object?>(),
    ),
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
  });

  final String key;
  final String name;
  final String description;
  final String directory;
  final String? readmeUrl;
  final String repoOwner;
  final String repoName;
  final String repoBranch;

  String get source => '$repoOwner/$repoName';

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    'description': description,
    'directory': directory,
    'readmeUrl': readmeUrl,
    'repoOwner': repoOwner,
    'repoName': repoName,
    'repoBranch': repoBranch,
  };

  factory DiscoverableSkill.fromJson(Map<String, Object?> json) =>
      DiscoverableSkill(
        key: json['key'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        directory: json['directory'] as String,
        readmeUrl: json['readmeUrl'] as String?,
        repoOwner: json['repoOwner'] as String,
        repoName: json['repoName'] as String,
        repoBranch: json['repoBranch'] as String,
      );
}
