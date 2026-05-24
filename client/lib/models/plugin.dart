class Plugin {
  const Plugin({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.directory,
    this.marketplaceOwner,
    this.marketplaceName,
    this.marketplaceBranch,
    this.homepageUrl,
    this.readmeUrl,
    this.capabilities = const PluginCapabilities(),
    this.contentHash,
    required this.installedAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final String directory;
  final String? marketplaceOwner;
  final String? marketplaceName;
  final String? marketplaceBranch;
  final String? homepageUrl;
  final String? readmeUrl;
  final PluginCapabilities capabilities;
  final String? contentHash;
  final int installedAt;
  final int updatedAt;

  String get source =>
      marketplaceOwner != null ? '$marketplaceOwner/$marketplaceName' : 'local';

  Plugin copyWith({
    String? id, String? name, String? description, String? version,
    String? directory, String? marketplaceOwner, String? marketplaceName,
    String? marketplaceBranch, String? homepageUrl, String? readmeUrl,
    PluginCapabilities? capabilities, String? contentHash,
    int? installedAt, int? updatedAt, bool clearMarketplace = false,
  }) => Plugin(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    version: version ?? this.version,
    directory: directory ?? this.directory,
    marketplaceOwner: clearMarketplace ? null : (marketplaceOwner ?? this.marketplaceOwner),
    marketplaceName: clearMarketplace ? null : (marketplaceName ?? this.marketplaceName),
    marketplaceBranch: clearMarketplace ? null : (marketplaceBranch ?? this.marketplaceBranch),
    homepageUrl: clearMarketplace ? null : (homepageUrl ?? this.homepageUrl),
    readmeUrl: clearMarketplace ? null : (readmeUrl ?? this.readmeUrl),
    capabilities: capabilities ?? this.capabilities,
    contentHash: contentHash ?? this.contentHash,
    installedAt: installedAt ?? this.installedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'directory': directory,
    'marketplaceOwner': marketplaceOwner,
    'marketplaceName': marketplaceName,
    'marketplaceBranch': marketplaceBranch,
    'homepageUrl': homepageUrl,
    'readmeUrl': readmeUrl,
    'capabilities': capabilities.toJson(),
    'contentHash': contentHash,
    'installedAt': installedAt,
    'updatedAt': updatedAt,
  };

  factory Plugin.fromJson(Map<String, Object?> json) => Plugin(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    version: json['version'] as String? ?? '0.0.0',
    directory: json['directory'] as String,
    marketplaceOwner: json['marketplaceOwner'] as String?,
    marketplaceName: json['marketplaceName'] as String?,
    marketplaceBranch: json['marketplaceBranch'] as String?,
    homepageUrl: json['homepageUrl'] as String?,
    readmeUrl: json['readmeUrl'] as String?,
    capabilities: json['capabilities'] is Map
        ? PluginCapabilities.fromJson((json['capabilities'] as Map).cast<String, Object?>())
        : const PluginCapabilities(),
    contentHash: json['contentHash'] as String?,
    installedAt: (json['installedAt'] as num?)?.toInt() ?? 0,
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Plugin &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          version == other.version &&
          directory == other.directory &&
          marketplaceOwner == other.marketplaceOwner &&
          marketplaceName == other.marketplaceName &&
          marketplaceBranch == other.marketplaceBranch &&
          capabilities == other.capabilities &&
          contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(
    id, name, version, directory, marketplaceOwner, marketplaceName,
    marketplaceBranch, capabilities, contentHash);
}

class PluginCapabilities {
  const PluginCapabilities({
    this.commands = const [],
    this.agents = const [],
    this.skills = const [],
    this.hooks = const [],
    this.mcpServers = const [],
  });

  final List<PluginCommand> commands;
  final List<PluginAgent> agents;
  final List<PluginSkillRef> skills;
  final List<PluginHook> hooks;
  final List<PluginMcpServer> mcpServers;

  Map<String, Object?> toJson() => {
    'commands': commands.map((c) => c.toJson()).toList(),
    'agents': agents.map((a) => a.toJson()).toList(),
    'skills': skills.map((s) => s.toJson()).toList(),
    'hooks': hooks.map((h) => h.toJson()).toList(),
    'mcpServers': mcpServers.map((m) => m.toJson()).toList(),
  };

  factory PluginCapabilities.fromJson(Map<String, Object?> json) => PluginCapabilities(
    commands: (json['commands'] as List? ?? const [])
        .whereType<Map>().map((m) => PluginCommand.fromJson(m.cast<String, Object?>())).toList(),
    agents: (json['agents'] as List? ?? const [])
        .whereType<Map>().map((m) => PluginAgent.fromJson(m.cast<String, Object?>())).toList(),
    skills: (json['skills'] as List? ?? const [])
        .whereType<Map>().map((m) => PluginSkillRef.fromJson(m.cast<String, Object?>())).toList(),
    hooks: (json['hooks'] as List? ?? const [])
        .whereType<Map>().map((m) => PluginHook.fromJson(m.cast<String, Object?>())).toList(),
    mcpServers: (json['mcpServers'] as List? ?? const [])
        .whereType<Map>().map((m) => PluginMcpServer.fromJson(m.cast<String, Object?>())).toList(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginCapabilities &&
          _listEq(commands, other.commands) &&
          _listEq(agents, other.agents) &&
          _listEq(skills, other.skills) &&
          _listEq(hooks, other.hooks) &&
          _listEq(mcpServers, other.mcpServers);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(commands), Object.hashAll(agents), Object.hashAll(skills),
    Object.hashAll(hooks), Object.hashAll(mcpServers));
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class PluginCommand {
  const PluginCommand({required this.name, this.description});
  final String name;
  final String? description;
  Map<String, Object?> toJson() => {'name': name, 'description': description};
  factory PluginCommand.fromJson(Map<String, Object?> j) =>
      PluginCommand(name: j['name'] as String, description: j['description'] as String?);
  @override
  bool operator ==(Object o) => o is PluginCommand && o.name == name && o.description == description;
  @override
  int get hashCode => Object.hash(name, description);
}

class PluginAgent {
  const PluginAgent({required this.name, this.description});
  final String name;
  final String? description;
  Map<String, Object?> toJson() => {'name': name, 'description': description};
  factory PluginAgent.fromJson(Map<String, Object?> j) =>
      PluginAgent(name: j['name'] as String, description: j['description'] as String?);
  @override
  bool operator ==(Object o) => o is PluginAgent && o.name == name && o.description == description;
  @override
  int get hashCode => Object.hash(name, description);
}

class PluginSkillRef {
  const PluginSkillRef({required this.name, this.description});
  final String name;
  final String? description;
  Map<String, Object?> toJson() => {'name': name, 'description': description};
  factory PluginSkillRef.fromJson(Map<String, Object?> j) =>
      PluginSkillRef(name: j['name'] as String, description: j['description'] as String?);
  @override
  bool operator ==(Object o) => o is PluginSkillRef && o.name == name && o.description == description;
  @override
  int get hashCode => Object.hash(name, description);
}

class PluginHook {
  const PluginHook({required this.event, required this.matcher});
  final String event;
  final String matcher;
  Map<String, Object?> toJson() => {'event': event, 'matcher': matcher};
  factory PluginHook.fromJson(Map<String, Object?> j) =>
      PluginHook(event: j['event'] as String, matcher: j['matcher'] as String? ?? '');
  @override
  bool operator ==(Object o) => o is PluginHook && o.event == event && o.matcher == matcher;
  @override
  int get hashCode => Object.hash(event, matcher);
}

class PluginMcpServer {
  const PluginMcpServer({required this.name, required this.type});
  final String name;
  final String type;
  Map<String, Object?> toJson() => {'name': name, 'type': type};
  factory PluginMcpServer.fromJson(Map<String, Object?> j) =>
      PluginMcpServer(name: j['name'] as String, type: j['type'] as String? ?? 'stdio');
  @override
  bool operator ==(Object o) => o is PluginMcpServer && o.name == name && o.type == type;
  @override
  int get hashCode => Object.hash(name, type);
}

class PluginMarketplace {
  const PluginMarketplace({
    required this.owner,
    required this.name,
    this.branch = 'main',
    this.enabled = true,
    this.displayName,
  });

  final String owner;
  final String name;
  final String branch;
  final bool enabled;
  final String? displayName;

  String get fullName => '$owner/$name';
  String get githubUrl => 'https://github.com/$owner/$name';

  PluginMarketplace copyWith({
    String? owner, String? name, String? branch, bool? enabled, String? displayName,
    bool clearDisplayName = false,
  }) => PluginMarketplace(
    owner: owner ?? this.owner,
    name: name ?? this.name,
    branch: branch ?? this.branch,
    enabled: enabled ?? this.enabled,
    displayName: clearDisplayName ? null : (displayName ?? this.displayName),
  );

  Map<String, Object?> toJson() => {
    'owner': owner, 'name': name, 'branch': branch,
    'enabled': enabled, 'displayName': displayName,
  };

  factory PluginMarketplace.fromJson(Map<String, Object?> json) => PluginMarketplace(
    owner: json['owner'] as String,
    name: json['name'] as String,
    branch: json['branch'] as String? ?? 'main',
    enabled: json['enabled'] as bool? ?? true,
    displayName: json['displayName'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginMarketplace &&
          runtimeType == other.runtimeType &&
          owner == other.owner &&
          name == other.name &&
          branch == other.branch &&
          enabled == other.enabled &&
          displayName == other.displayName;

  @override
  int get hashCode => Object.hash(owner, name, branch, enabled, displayName);
}

class DiscoverablePlugin {
  const DiscoverablePlugin({
    required this.key,
    required this.name,
    required this.description,
    required this.version,
    this.readmeUrl,
    required this.marketplaceOwner,
    required this.marketplaceName,
    required this.marketplaceBranch,
    required this.source,
    this.localInstall = true,
    this.categories = const [],
    this.keywords = const [],
  });

  final String key;
  final String name;
  final String description;
  final String version;
  final String? readmeUrl;
  final String marketplaceOwner;
  final String marketplaceName;
  final String marketplaceBranch;
  /// Relative path inside the synced marketplace repo (install from cache).
  final String source;
  /// When false, plugin is listed for discovery but must be installed via Claude Code / external fetch.
  final bool localInstall;
  final List<String> categories;
  final List<String> keywords;

  String get marketplaceFullName => '$marketplaceOwner/$marketplaceName';

  Map<String, Object?> toJson() => {
    'key': key, 'name': name, 'description': description, 'version': version,
    'readmeUrl': readmeUrl,
    'marketplaceOwner': marketplaceOwner,
    'marketplaceName': marketplaceName,
    'marketplaceBranch': marketplaceBranch,
    'source': source,
    'localInstall': localInstall,
    'categories': categories,
    'keywords': keywords,
  };

  factory DiscoverablePlugin.fromJson(Map<String, Object?> json) => DiscoverablePlugin(
    key: json['key'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    version: json['version'] as String? ?? '0.0.0',
    readmeUrl: json['readmeUrl'] as String?,
    marketplaceOwner: json['marketplaceOwner'] as String,
    marketplaceName: json['marketplaceName'] as String,
    marketplaceBranch: json['marketplaceBranch'] as String? ?? 'main',
    source: json['source'] as String? ?? '.',
    localInstall: json['localInstall'] as bool? ?? true,
    categories: (json['categories'] as List? ?? const []).whereType<String>().toList(),
    keywords: (json['keywords'] as List? ?? const []).whereType<String>().toList(),
  );

  DiscoverablePlugin copyWith({
    String? key, String? name, String? description, String? version,
    String? readmeUrl, String? marketplaceOwner, String? marketplaceName,
    String? marketplaceBranch, String? source, bool? localInstall,
    List<String>? categories, List<String>? keywords,
    bool clearReadmeUrl = false,
  }) => DiscoverablePlugin(
    key: key ?? this.key,
    name: name ?? this.name,
    description: description ?? this.description,
    version: version ?? this.version,
    readmeUrl: clearReadmeUrl ? null : (readmeUrl ?? this.readmeUrl),
    marketplaceOwner: marketplaceOwner ?? this.marketplaceOwner,
    marketplaceName: marketplaceName ?? this.marketplaceName,
    marketplaceBranch: marketplaceBranch ?? this.marketplaceBranch,
    source: source ?? this.source,
    localInstall: localInstall ?? this.localInstall,
    categories: categories ?? this.categories,
    keywords: keywords ?? this.keywords,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoverablePlugin &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          name == other.name &&
          description == other.description &&
          version == other.version &&
          readmeUrl == other.readmeUrl &&
          marketplaceOwner == other.marketplaceOwner &&
          marketplaceName == other.marketplaceName &&
          marketplaceBranch == other.marketplaceBranch &&
          source == other.source &&
          localInstall == other.localInstall &&
          _listEq(categories, other.categories) &&
          _listEq(keywords, other.keywords);

  @override
  int get hashCode => Object.hash(
    key, name, description, version, marketplaceOwner, marketplaceName,
    marketplaceBranch, readmeUrl, source, localInstall,
    Object.hashAll(categories), Object.hashAll(keywords));
}

class PluginUpdateInfo {
  const PluginUpdateInfo({
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
    'id': id, 'name': name, 'currentHash': currentHash, 'remoteHash': remoteHash,
  };

  factory PluginUpdateInfo.fromJson(Map<String, Object?> json) => PluginUpdateInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    currentHash: json['currentHash'] as String?,
    remoteHash: json['remoteHash'] as String,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginUpdateInfo &&
          runtimeType == other.runtimeType &&
          id == other.id && remoteHash == other.remoteHash &&
          currentHash == other.currentHash && name == other.name;

  @override
  int get hashCode => Object.hash(id, remoteHash, currentHash, name);
}

class PluginBackup {
  const PluginBackup({
    required this.backupId,
    required this.backupPath,
    required this.createdAt,
    required this.plugin,
  });

  final String backupId;
  final String backupPath;
  final int createdAt;
  final Plugin plugin;

  Map<String, Object?> toJson() => {
    'backupId': backupId,
    'backupPath': backupPath,
    'createdAt': createdAt,
    'plugin': plugin.toJson(),
  };

  factory PluginBackup.fromJson(Map<String, Object?> json) => PluginBackup(
    backupId: json['backupId'] as String,
    backupPath: json['backupPath'] as String,
    createdAt: (json['createdAt'] as num).toInt(),
    plugin: Plugin.fromJson((json['plugin'] as Map).cast<String, Object?>()),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginBackup &&
          runtimeType == other.runtimeType &&
          backupId == other.backupId &&
          backupPath == other.backupPath &&
          plugin == other.plugin;

  @override
  int get hashCode => Object.hash(backupId, backupPath, plugin);
}

class UnmanagedPlugin {
  const UnmanagedPlugin({
    required this.directory,
    required this.name,
    required this.path,
    this.description,
    this.version,
  });

  final String directory;
  final String name;
  final String? description;
  final String? version;
  final String path;
}
