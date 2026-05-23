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
