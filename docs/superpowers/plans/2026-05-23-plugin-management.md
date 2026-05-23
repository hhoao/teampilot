# Plugin Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code-style plugin management system in TeamPilot: marketplace-based discovery, install/update/uninstall, and per-team enablement via `TeamConfig.pluginIds` mirroring the existing `skillIds` pattern.

**Architecture:** TeamPilot self-maintains plugin install dir (`<teampilotRoot>/plugins/`) and metadata (`plugins.json`). Team enablement is owned by `TeamConfig.pluginIds`; a new `TeamPluginLinkerService` projects enabled plugins to `config-profiles/teams/<teamId>/flashskyai/plugins/` where the CLI reads them, mirroring `TeamSkillLinkerService`.

**Tech Stack:** Dart / Flutter (`flutter_bloc`, `equatable`, `go_router`, `file_picker`); reuses existing `AppPaths`, `FlashskyaiStorageRoots`, `CliDataLayout`, fs abstraction (Local/SFTP), `parseGithubRepoUrl`.

**Spec:** [`docs/superpowers/specs/2026-05-23-plugin-management-design.md`](../specs/2026-05-23-plugin-management-design.md)

---

## Phase 1 — Data Layer (Tasks 1–11)

No UI. Each service is independently unit-testable.

---

### Task 1: Plugin model + sub-resource value types

**Files:**
- Create: `client/lib/models/plugin.dart`
- Test: `client/test/plugin_model_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/plugin_model_test.dart
import 'package:teampilot/models/plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Plugin round-trips through json with capabilities', () {
    const plugin = Plugin(
      id: 'acme/market/my-plugin',
      name: 'my-plugin',
      description: 'desc',
      version: '1.2.3',
      directory: 'acme__market__my-plugin',
      marketplaceOwner: 'acme',
      marketplaceName: 'market',
      marketplaceBranch: 'main',
      capabilities: PluginCapabilities(
        commands: [PluginCommand(name: 'deploy', description: 'd')],
        agents: [],
        skills: [PluginSkillRef(name: 'tdd', description: null)],
        hooks: [PluginHook(event: 'PreCommit', matcher: '*.dart')],
        mcpServers: [PluginMcpServer(name: 'github', type: 'stdio')],
      ),
      contentHash: 'abc123',
      installedAt: 1000,
      updatedAt: 2000,
    );

    final decoded = Plugin.fromJson(plugin.toJson());
    expect(decoded, plugin);
    expect(decoded.source, 'acme/market');
  });

  test('Plugin source is local when marketplaceOwner is null', () {
    const plugin = Plugin(
      id: 'local/dev-plugin',
      name: 'dev-plugin',
      description: '',
      version: '0.0.0+local',
      directory: 'local__dev-plugin',
      capabilities: PluginCapabilities(),
      installedAt: 0,
      updatedAt: 0,
    );
    expect(plugin.source, 'local');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/plugin_model_test.dart`
Expected: FAIL (`plugin.dart` not found)

- [ ] **Step 3: Create `client/lib/models/plugin.dart`**

```dart
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
```

- [ ] **Step 4: Run test to verify pass**

Run: `cd client && flutter test test/plugin_model_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/plugin.dart client/test/plugin_model_test.dart
git commit -m "feat(plugin): add Plugin model and capability value types"
```

---

### Task 2: PluginMarketplace + DiscoverablePlugin models

**Files:**
- Modify: `client/lib/models/plugin.dart` (append)
- Modify: `client/test/plugin_model_test.dart` (append)

- [ ] **Step 1: Add failing tests at end of `plugin_model_test.dart`**

```dart
  test('PluginMarketplace round-trips', () {
    const m = PluginMarketplace(
      owner: 'acme', name: 'market', branch: 'main',
      enabled: false, displayName: 'Acme Market');
    final decoded = PluginMarketplace.fromJson(m.toJson());
    expect(decoded, m);
    expect(decoded.fullName, 'acme/market');
    expect(decoded.githubUrl, 'https://github.com/acme/market');
  });

  test('DiscoverablePlugin round-trips', () {
    const d = DiscoverablePlugin(
      key: 'acme:market:p',
      name: 'p',
      description: 'desc',
      version: '1.0.0',
      readmeUrl: 'https://...',
      marketplaceOwner: 'acme',
      marketplaceName: 'market',
      marketplaceBranch: 'main',
      source: '.',
      categories: ['dev'],
      keywords: ['k1'],
    );
    final decoded = DiscoverablePlugin.fromJson(d.toJson());
    expect(decoded, d);
  });
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd client && flutter test test/plugin_model_test.dart`
Expected: FAIL (PluginMarketplace not defined)

- [ ] **Step 3: Append to `client/lib/models/plugin.dart`**

```dart
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
  }) => PluginMarketplace(
    owner: owner ?? this.owner,
    name: name ?? this.name,
    branch: branch ?? this.branch,
    enabled: enabled ?? this.enabled,
    displayName: displayName ?? this.displayName,
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
  final String source;
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
    categories: (json['categories'] as List? ?? const []).whereType<String>().toList(),
    keywords: (json['keywords'] as List? ?? const []).whereType<String>().toList(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoverablePlugin &&
          key == other.key &&
          name == other.name &&
          description == other.description &&
          version == other.version &&
          marketplaceOwner == other.marketplaceOwner &&
          marketplaceName == other.marketplaceName &&
          marketplaceBranch == other.marketplaceBranch &&
          source == other.source &&
          _listStringEq(categories, other.categories) &&
          _listStringEq(keywords, other.keywords);

  @override
  int get hashCode => Object.hash(
    key, name, version, marketplaceOwner, marketplaceName, marketplaceBranch);
}

bool _listStringEq(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
```

- [ ] **Step 4: Run to confirm pass**

Run: `cd client && flutter test test/plugin_model_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/plugin.dart client/test/plugin_model_test.dart
git commit -m "feat(plugin): add PluginMarketplace and DiscoverablePlugin models"
```

---

### Task 3: PluginUpdateInfo + PluginBackup + UnmanagedPlugin

**Files:**
- Modify: `client/lib/models/plugin.dart` (append)
- Modify: `client/test/plugin_model_test.dart` (append)

- [ ] **Step 1: Add tests for the three models**

```dart
  test('PluginUpdateInfo round-trips', () {
    const u = PluginUpdateInfo(
      id: 'acme/market/p', name: 'p', remoteHash: 'r1', currentHash: 'c1');
    expect(PluginUpdateInfo.fromJson(u.toJson()), u);
  });

  test('PluginBackup round-trips', () {
    const p = Plugin(
      id: 'a/b/c', name: 'c', description: '', version: '1.0.0',
      directory: 'a__b__c',
      capabilities: PluginCapabilities(),
      installedAt: 1, updatedAt: 2);
    const b = PluginBackup(
      backupId: 'bk1', backupPath: '/tmp/bk', createdAt: 100, plugin: p);
    expect(PluginBackup.fromJson(b.toJson()), b);
  });

  test('UnmanagedPlugin holds directory/name/path', () {
    const u = UnmanagedPlugin(directory: 'foo', name: 'foo', path: '/tmp/foo');
    expect(u.directory, 'foo');
  });
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd client && flutter test test/plugin_model_test.dart`
Expected: FAIL

- [ ] **Step 3: Append the three models to `plugin.dart`**

```dart
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
```

- [ ] **Step 4: Run + commit**

```bash
cd client && flutter test test/plugin_model_test.dart
git add client/lib/models/plugin.dart client/test/plugin_model_test.dart
git commit -m "feat(plugin): add PluginUpdateInfo, PluginBackup, UnmanagedPlugin"
```

---

### Task 4: Extend `TeamConfig` with `pluginIds`

**Files:**
- Modify: `client/lib/models/team_config.dart` (mirror `skillIds` pattern)
- Modify: `client/test/team_config_test.dart`

- [ ] **Step 1: Add failing test in `team_config_test.dart`**

```dart
  test('TeamConfig round-trips pluginIds', () {
    const team = TeamConfig(
      id: 't', name: 'T',
      pluginIds: ['acme/market/p1', 'beta/market/p2'],
    );
    final decoded = TeamConfig.fromJson(team.toJson());
    expect(decoded.pluginIds, ['acme/market/p1', 'beta/market/p2']);
    expect(decoded, team);
  });

  test('TeamConfig omits pluginIds when empty', () {
    const team = TeamConfig(id: 't', name: 'T');
    expect(team.toJson().containsKey('pluginIds'), isFalse);
  });
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd client && flutter test test/team_config_test.dart`
Expected: FAIL (`pluginIds` named param does not exist)

- [ ] **Step 3: Modify `team_config.dart`**

Add field, ctor param, decoder, fromJson/toJson, copyWith, equality:

1. In the `TeamConfig` ctor, add `this.pluginIds = const [],` after `this.skillIds`.
2. Add helper method below `decodeSkillIds`:

```dart
  static List<String> decodePluginIds(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
```

3. In `fromJson`, after `skillIds: decodeSkillIds(json['skillIds'])`, add:

```dart
      pluginIds: decodePluginIds(json['pluginIds']),
```

4. After `final List<String> skillIds;` add:

```dart
  /// `Plugin.id` values enabled for this team (mirrors [skillIds]).
  final List<String> pluginIds;
```

5. In `copyWith` add the `List<String>? pluginIds,` parameter and pass through.
6. In `toJson` after the skillIds emit, add:

```dart
      if (pluginIds.isNotEmpty) 'pluginIds': pluginIds,
```

7. In `==` and `hashCode` include `listEquals(pluginIds, other.pluginIds)` / `Object.hashAll(pluginIds)`.

- [ ] **Step 4: Run + commit**

```bash
cd client && flutter test test/team_config_test.dart
git add client/lib/models/team_config.dart client/test/team_config_test.dart
git commit -m "feat(team): add pluginIds to TeamConfig mirroring skillIds"
```

---

### Task 5: AppPaths plugin helpers + StorageRootsSnapshot extension

**Files:**
- Modify: `client/lib/services/app_storage.dart` (after the skills helpers)
- Modify: `client/lib/services/flashskyai_storage_roots.dart`
- Test: `client/test/app_storage_test.dart` (extend)

- [ ] **Step 1: Add tests for new path helpers**

Append to `client/test/app_storage_test.dart`:

```dart
  test('AppPaths exposes plugin paths under teampilotRoot', () {
    final root = '/tmp/tp';
    expect(AppPaths.pluginsDirForTeampilotRoot(root), '/tmp/tp/plugins');
    expect(AppPaths.pluginBackupsDirForTeampilotRoot(root), '/tmp/tp/plugin-backups');
    expect(AppPaths.pluginsJsonForTeampilotRoot(root), '/tmp/tp/plugins.json');
    expect(AppPaths.pluginMarketplacesConfigPathForTeampilotRoot(root),
      '/tmp/tp/plugin-marketplaces.json');
    expect(AppPaths.pluginMarketplaceCacheDirForTeampilotRoot(root),
      '/tmp/tp/plugin-marketplace-cache');
  });
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd client && flutter test test/app_storage_test.dart`
Expected: FAIL

- [ ] **Step 3: Add static helpers to `AppPaths` class** (after the existing skill helpers around line 89-93)

```dart
  static String pluginsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins');

  static String pluginBackupsDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugin-backups');

  static String pluginsJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugins.json');

  static String pluginMarketplacesConfigPathForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugin-marketplaces.json');

  static String pluginMarketplaceCacheDirForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'plugin-marketplace-cache');
```

Also add instance getters mirroring the existing `skillReposConfigPath` style:

```dart
  String get pluginsJson => _ctx.join(basePath, 'plugins.json');
  String get pluginMarketplacesConfigPath => _ctx.join(basePath, 'plugin-marketplaces.json');
```

- [ ] **Step 4: Extend `StorageRootsSnapshot`**

In `client/lib/services/flashskyai_storage_roots.dart`:

Add to ctor params + fields after `skillReposConfigPath`:

```dart
    required this.pluginsRoot,
    required this.pluginBackupsDir,
    required this.pluginsJsonPath,
    required this.pluginMarketplacesConfigPath,
    required this.pluginMarketplaceCacheDir,
```

Add fields:

```dart
  final String pluginsRoot;
  final String pluginBackupsDir;
  final String pluginsJsonPath;
  final String pluginMarketplacesConfigPath;
  final String pluginMarketplaceCacheDir;
```

In `fromContext`, add:

```dart
      pluginsRoot: AppPaths.pluginsDirForTeampilotRoot(root),
      pluginBackupsDir: AppPaths.pluginBackupsDirForTeampilotRoot(root),
      pluginsJsonPath: AppPaths.pluginsJsonForTeampilotRoot(root),
      pluginMarketplacesConfigPath: AppPaths.pluginMarketplacesConfigPathForTeampilotRoot(root),
      pluginMarketplaceCacheDir: AppPaths.pluginMarketplaceCacheDirForTeampilotRoot(root),
```

- [ ] **Step 5: Run + commit**

```bash
cd client && flutter test test/app_storage_test.dart
git add client/lib/services/app_storage.dart client/lib/services/flashskyai_storage_roots.dart client/test/app_storage_test.dart
git commit -m "feat(plugin): add plugin storage paths to AppPaths and StorageRootsSnapshot"
```

---

### Task 6: `PluginException` hierarchy

**Files:**
- Create: `client/lib/services/plugin_exceptions.dart`

- [ ] **Step 1: Write file**

```dart
class PluginException implements Exception {
  PluginException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override String toString() =>
      cause == null ? 'PluginException: $message' : 'PluginException: $message (cause: $cause)';
}

class PluginNotFoundException extends PluginException {
  PluginNotFoundException(String id) : super('Plugin not found: $id');
}

class PluginManifestException extends PluginException {
  PluginManifestException(String path, {Object? cause})
      : super('Failed to parse plugin manifest at $path', cause: cause);
}

class PluginInstallException extends PluginException {
  PluginInstallException(String id, String reason, {Object? cause})
      : super('Plugin install failed [$id]: $reason', cause: cause);
}

class MarketplaceUnreachableException extends PluginException {
  MarketplaceUnreachableException(String marketplace, {Object? cause})
      : super('Marketplace unreachable: $marketplace', cause: cause);
}
```

- [ ] **Step 2: Commit**

```bash
git add client/lib/services/plugin_exceptions.dart
git commit -m "feat(plugin): add PluginException hierarchy"
```

---

### Task 7: `PluginManifestService` (parse plugin.json + sub-resources)

**Files:**
- Create: `client/lib/services/plugin_manifest_service.dart`
- Test: `client/test/plugin_manifest_service_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'dart:io';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/plugin_manifest_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('plugin-manifest-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('parses plugin.json with version and description', () async {
    final dir = Directory(p.join(tmp.path, 'my-plugin'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'plugin.json'))
        .writeAsStringSync('{"name":"my-plugin","version":"1.2.3","description":"hi"}');

    final svc = PluginManifestService();
    final result = await svc.parseDirectory(dir.path);
    expect(result.name, 'my-plugin');
    expect(result.version, '1.2.3');
    expect(result.description, 'hi');
  });

  test('falls back to directory name when plugin.json missing', () async {
    final dir = Directory(p.join(tmp.path, 'no-manifest'))..createSync();
    Directory(p.join(dir.path, 'commands')).createSync();
    File(p.join(dir.path, 'commands', 'deploy.md'))
        .writeAsStringSync('---\ndescription: Deploy current branch\n---\n# Deploy');

    final svc = PluginManifestService();
    final result = await svc.parseDirectory(dir.path);
    expect(result.name, 'no-manifest');
    expect(result.capabilities.commands.first.name, 'deploy');
    expect(result.capabilities.commands.first.description, 'Deploy current branch');
  });

  test('parses hooks.json and .mcp.json', () async {
    final dir = Directory(p.join(tmp.path, 'p'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'plugin.json'))
        .writeAsStringSync('{"name":"p","version":"1.0.0"}');
    Directory(p.join(dir.path, 'hooks')).createSync();
    File(p.join(dir.path, 'hooks', 'hooks.json')).writeAsStringSync(
      '{"hooks":{"PreCommit":[{"matcher":"*.dart"}]}}');
    File(p.join(dir.path, '.mcp.json')).writeAsStringSync(
      '{"mcpServers":{"github":{"type":"stdio","command":"gh"}}}');

    final svc = PluginManifestService();
    final result = await svc.parseDirectory(dir.path);
    expect(result.capabilities.hooks.first.event, 'PreCommit');
    expect(result.capabilities.hooks.first.matcher, '*.dart');
    expect(result.capabilities.mcpServers.first.name, 'github');
    expect(result.capabilities.mcpServers.first.type, 'stdio');
  });

  test('throws PluginManifestException for invalid JSON', () async {
    final dir = Directory(p.join(tmp.path, 'bad'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'plugin.json'))
        .writeAsStringSync('{not json');
    final svc = PluginManifestService();
    expect(() => svc.parseDirectory(dir.path), throwsA(isA<PluginManifestException>()));
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd client && flutter test test/plugin_manifest_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement service**

```dart
// client/lib/services/plugin_manifest_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/plugin.dart';
import 'plugin_exceptions.dart';

class ParsedPlugin {
  ParsedPlugin({
    required this.name,
    required this.version,
    required this.description,
    required this.homepageUrl,
    required this.capabilities,
  });
  final String name;
  final String version;
  final String description;
  final String? homepageUrl;
  final PluginCapabilities capabilities;
}

class PluginManifestService {
  Future<ParsedPlugin> parseDirectory(String pluginDir) async {
    final manifestPath = p.join(pluginDir, '.claude-plugin', 'plugin.json');
    Map<String, Object?>? manifest;
    final manifestFile = File(manifestPath);
    if (manifestFile.existsSync()) {
      try {
        manifest = (jsonDecode(manifestFile.readAsStringSync()) as Map).cast<String, Object?>();
      } catch (e) {
        throw PluginManifestException(manifestPath, cause: e);
      }
    }

    final name = (manifest?['name'] as String?)?.trim().isNotEmpty == true
        ? manifest!['name'] as String
        : p.basename(pluginDir);
    final version = (manifest?['version'] as String?) ?? '0.0.0';
    final description = (manifest?['description'] as String?) ?? '';
    final homepage = manifest?['homepage'] as String?;

    final capabilities = await _scanCapabilities(pluginDir);
    return ParsedPlugin(
      name: name,
      version: version,
      description: description,
      homepageUrl: homepage,
      capabilities: capabilities,
    );
  }

  Future<PluginCapabilities> _scanCapabilities(String dir) async {
    return PluginCapabilities(
      commands: _scanMdDir(p.join(dir, 'commands'),
          mapper: (name, fm) => PluginCommand(name: name, description: fm['description'])),
      agents: _scanMdDir(p.join(dir, 'agents'),
          mapper: (name, fm) => PluginAgent(name: name, description: fm['description'])),
      skills: _scanSkillsDir(p.join(dir, 'skills')),
      hooks: _scanHooks(p.join(dir, 'hooks', 'hooks.json')),
      mcpServers: _scanMcp(p.join(dir, '.mcp.json')),
    );
  }

  List<T> _scanMdDir<T>(
    String dir, {
    required T Function(String name, Map<String, String?> frontmatter) mapper,
  }) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final out = <T>[];
    for (final entry in d.listSync()) {
      if (entry is! File || !entry.path.endsWith('.md')) continue;
      final name = p.basenameWithoutExtension(entry.path);
      final fm = _parseFrontmatter(entry.readAsStringSync());
      out.add(mapper(name, fm));
    }
    return out;
  }

  List<PluginSkillRef> _scanSkillsDir(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final out = <PluginSkillRef>[];
    for (final entry in d.listSync()) {
      if (entry is! Directory) continue;
      final skillMd = File(p.join(entry.path, 'SKILL.md'));
      if (!skillMd.existsSync()) continue;
      final fm = _parseFrontmatter(skillMd.readAsStringSync());
      out.add(PluginSkillRef(
        name: fm['name'] ?? p.basename(entry.path),
        description: fm['description'],
      ));
    }
    return out;
  }

  List<PluginHook> _scanHooks(String path) {
    final f = File(path);
    if (!f.existsSync()) return const [];
    try {
      final json = jsonDecode(f.readAsStringSync()) as Map;
      final hooks = (json['hooks'] as Map?)?.cast<String, Object?>() ?? const {};
      final out = <PluginHook>[];
      hooks.forEach((event, value) {
        if (value is List) {
          for (final entry in value) {
            if (entry is Map) {
              out.add(PluginHook(
                event: event,
                matcher: (entry['matcher'] as String?) ?? '',
              ));
            }
          }
        }
      });
      return out;
    } catch (_) {
      return const [];
    }
  }

  List<PluginMcpServer> _scanMcp(String path) {
    final f = File(path);
    if (!f.existsSync()) return const [];
    try {
      final json = jsonDecode(f.readAsStringSync()) as Map;
      final servers = (json['mcpServers'] as Map?)?.cast<String, Object?>() ?? const {};
      return servers.entries.map((e) {
        final v = (e.value as Map?)?.cast<String, Object?>() ?? const {};
        return PluginMcpServer(name: e.key, type: (v['type'] as String?) ?? 'stdio');
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, String?> _parseFrontmatter(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return const {};
    final out = <String, String?>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim() == '---') break;
      final idx = line.indexOf(':');
      if (idx < 0) continue;
      final k = line.substring(0, idx).trim();
      final v = line.substring(idx + 1).trim();
      out[k] = v.isEmpty ? null : v;
    }
    return out;
  }
}
```

- [ ] **Step 4: Run + commit**

```bash
cd client && flutter test test/plugin_manifest_service_test.dart
git add client/lib/services/plugin_manifest_service.dart client/test/plugin_manifest_service_test.dart
git commit -m "feat(plugin): add PluginManifestService for plugin.json + sub-resource parsing"
```

---

### Task 8: `PluginRepoService` (marketplaces.json CRUD)

**Files:**
- Create: `client/lib/services/plugin_repo_service.dart`
- Test: `client/test/plugin_repo_service_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'dart:io';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/plugin_repo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-repo-svc-');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(tmp.path));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('loads default marketplaces on first call', () async {
    final svc = PluginRepoService();
    final list = await svc.loadMarketplaces();
    expect(list, isNotEmpty);
    // Default file persisted
    expect(File(p.join(tmp.path, 'plugin-marketplaces.json')).existsSync(), isTrue);
  });

  test('addMarketplace / removeMarketplace / setEnabled', () async {
    final svc = PluginRepoService();
    await svc.loadMarketplaces();
    await svc.addMarketplace(const PluginMarketplace(owner: 'a', name: 'b'));
    var list = await svc.loadMarketplaces();
    expect(list.where((m) => m.owner == 'a' && m.name == 'b'), hasLength(1));

    await svc.setEnabled('a', 'b', false);
    list = await svc.loadMarketplaces();
    expect(list.firstWhere((m) => m.owner == 'a').enabled, isFalse);

    await svc.removeMarketplace('a', 'b');
    list = await svc.loadMarketplaces();
    expect(list.where((m) => m.owner == 'a' && m.name == 'b'), isEmpty);
  });

  test('addMarketplace is idempotent on owner/name', () async {
    final svc = PluginRepoService();
    await svc.loadMarketplaces();
    await svc.addMarketplace(const PluginMarketplace(owner: 'x', name: 'y'));
    await svc.addMarketplace(const PluginMarketplace(owner: 'x', name: 'y', branch: 'dev'));
    final list = await svc.loadMarketplaces();
    expect(list.where((m) => m.owner == 'x' && m.name == 'y'), hasLength(1));
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd client && flutter test test/plugin_repo_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement**

```dart
// client/lib/services/plugin_repo_service.dart
import 'dart:convert';
import '../models/plugin.dart';
import 'app_storage.dart';
import 'flashskyai_storage_roots.dart';

class PluginRepoService {
  PluginRepoService({FlashskyaiStorageRoots? storageRoots})
      : _storageRoots = storageRoots;

  final FlashskyaiStorageRoots? _storageRoots;

  static const _defaults = [
    PluginMarketplace(owner: 'anthropics', name: 'claude-plugins-official'),
  ];

  Future<String> _configPath() async {
    if (_storageRoots != null) {
      return (await _storageRoots.resolve()).pluginMarketplacesConfigPath;
    }
    return AppStorage.paths.pluginMarketplacesConfigPath;
  }

  Future<List<PluginMarketplace>> loadMarketplaces() async {
    final cache = await _readManifest();
    if (cache.isEmpty) {
      await _writeManifest({
        'marketplaces': _defaults.map((m) => m.toJson()).toList(),
      });
      return _defaults.toList();
    }
    final raw = cache['marketplaces'] as List<dynamic>?;
    if (raw == null) return _defaults.toList();
    return raw
        .whereType<Map>()
        .map((m) => PluginMarketplace.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<void> saveMarketplaces(List<PluginMarketplace> list) async {
    final cache = await _readManifest();
    cache['marketplaces'] = list.map((m) => m.toJson()).toList();
    await _writeManifest(cache);
  }

  Future<void> addMarketplace(PluginMarketplace m) async {
    final list = await loadMarketplaces();
    if (list.any((x) => x.owner == m.owner && x.name == m.name)) return;
    list.add(m);
    await saveMarketplaces(list);
  }

  Future<void> removeMarketplace(String owner, String name) async {
    final list = await loadMarketplaces();
    list.removeWhere((m) => m.owner == owner && m.name == name);
    await saveMarketplaces(list);
  }

  Future<void> setEnabled(String owner, String name, bool enabled) async {
    final list = await loadMarketplaces();
    final idx = list.indexWhere((m) => m.owner == owner && m.name == name);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(enabled: enabled);
    await saveMarketplaces(list);
  }

  Future<Map<String, Object?>> _readManifest() async {
    final path = await _configPath();
    final fs = (_storageRoots != null
        ? (await _storageRoots.resolve()).fs
        : AppStorage.fs);
    if (!await fs.exists(path)) return <String, Object?>{};
    final bytes = await fs.readAsBytes(path);
    if (bytes.isEmpty) return <String, Object?>{};
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
  }

  Future<void> _writeManifest(Map<String, Object?> data) async {
    final path = await _configPath();
    final fs = (_storageRoots != null
        ? (await _storageRoots.resolve()).fs
        : AppStorage.fs);
    await fs.writeAsString(path, jsonEncode(data));
  }
}
```

**Note:** Verify `AppStorage.fs` has `exists` / `readAsBytes` / `writeAsString` — they do (see `skill_repo_service.dart`). If method names differ, adapt to existing fs interface.

- [ ] **Step 4: Run + commit**

```bash
cd client && flutter test test/plugin_repo_service_test.dart
git add client/lib/services/plugin_repo_service.dart client/test/plugin_repo_service_test.dart
git commit -m "feat(plugin): add PluginRepoService for marketplace config CRUD"
```

---

### Task 9: `PluginRepoGitService`

**Files:**
- Create: `client/lib/services/plugin_repo_git_service.dart`

- [ ] **Step 1: Implement (mirrors `skill_repo_git_service.dart`)**

Read `client/lib/services/skill_repo_git_service.dart` first to understand its exact API (`fetchTarball`, `headSha`, `compareHash`), then create a structurally identical service that operates on `PluginMarketplace` instead of `SkillRepo`. Both services do the same git plumbing — only the type names differ.

Key method signatures expected:

```dart
class PluginRepoGitService {
  Future<List<int>> fetchTarball(PluginMarketplace marketplace);
  Future<String?> headSha(PluginMarketplace marketplace);
}
```

- [ ] **Step 2: Commit**

```bash
git add client/lib/services/plugin_repo_git_service.dart
git commit -m "feat(plugin): add PluginRepoGitService mirroring skill repo git service"
```

---

### Task 10: `PluginRepoDiskCacheService` (sync marketplace, parse marketplace.json)

**Files:**
- Create: `client/lib/services/plugin_repo_disk_cache_service.dart`
- Test: `client/test/plugin_repo_disk_cache_service_test.dart`

- [ ] **Step 1: Write test for marketplace.json parsing**

```dart
import 'dart:io';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/plugin_repo_disk_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('plugin-cache-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('parses marketplace.json into DiscoverablePlugin list', () {
    final dir = Directory(p.join(tmp.path, 'mkt'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'marketplace.json')).writeAsStringSync('''
{
  "name": "acme-market",
  "plugins": [
    {
      "name": "p1",
      "description": "first",
      "version": "1.0.0",
      "source": "./plugins/p1",
      "category": "dev"
    },
    {
      "name": "p2",
      "description": "second",
      "version": "0.1.0",
      "source": ".",
      "keywords": ["k1"]
    }
  ]
}
''');

    final svc = PluginRepoDiskCacheService();
    final list = svc.parseMarketplaceManifest(
      directory: dir.path,
      marketplace: const PluginMarketplace(owner: 'acme', name: 'mkt'),
    );
    expect(list, hasLength(2));
    expect(list.first.name, 'p1');
    expect(list.first.categories, contains('dev'));
    expect(list.last.keywords, contains('k1'));
  });

  static String repoKeyFor(PluginMarketplace m) =>
      PluginRepoDiskCacheService.repoKey(m);
}
```

- [ ] **Step 2: Run failing**

Run: `cd client && flutter test test/plugin_repo_disk_cache_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement**

Read `client/lib/services/skill_repo_disk_cache_service.dart` for the existing pattern (tarball extract, repoKey, syncRepo). Create `plugin_repo_disk_cache_service.dart` with these methods:

```dart
class PluginRepoDiskCacheService {
  PluginRepoDiskCacheService({
    PluginRepoGitService? gitService,
    FlashskyaiStorageRoots? storageRoots,
  });

  static String repoKey(PluginMarketplace m) => '${m.owner}/${m.name}@${m.branch}';

  Future<String> syncMarketplace(PluginMarketplace m); // returns cache directory
  Future<List<DiscoverablePlugin>> discoverablePlugins(PluginMarketplace m);
  List<DiscoverablePlugin> parseMarketplaceManifest({
    required String directory,
    required PluginMarketplace marketplace,
  });
}
```

`parseMarketplaceManifest` reads `<directory>/.claude-plugin/marketplace.json`, iterates the `plugins` array, builds `DiscoverablePlugin` per entry. `key = '${owner}:${name}:${pluginName}'`. `source` field is read verbatim (default `'.'`). `categories` accepts either a string (wrap into single-element list) or list. `readmeUrl` is derived from the marketplace github URL when source is `.`.

- [ ] **Step 4: Run + commit**

```bash
cd client && flutter test test/plugin_repo_disk_cache_service_test.dart
git add client/lib/services/plugin_repo_disk_cache_service.dart client/test/plugin_repo_disk_cache_service_test.dart
git commit -m "feat(plugin): add PluginRepoDiskCacheService"
```

---

### Task 11: `PluginFetchService` + `PluginInstallService`

**Files:**
- Create: `client/lib/services/plugin_fetch_service.dart`
- Create: `client/lib/services/plugin_install_service.dart`
- Test: `client/test/plugin_install_service_test.dart`

- [ ] **Step 1: Write install test (using local-zip path to avoid network)**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/plugin_install_service.dart';
import 'package:teampilot/services/plugin_manifest_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-install-');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(tmp.path));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('installFromZip extracts plugin and persists Plugin record', () async {
    // Build a zip containing a valid plugin dir
    final archive = Archive();
    final manifest = '{"name":"my-plugin","version":"1.0.0","description":"hi"}';
    archive.addFile(ArchiveFile(
      '.claude-plugin/plugin.json',
      manifest.length,
      utf8.encode(manifest),
    ));
    final zipBytes = ZipEncoder().encode(archive)!;
    final zipFile = File(p.join(tmp.path, 'in.zip'))..writeAsBytesSync(zipBytes);

    final svc = PluginInstallService(manifestService: PluginManifestService());
    final installed = await svc.installFromZip(zipFile);

    expect(installed.name, 'my-plugin');
    expect(installed.id, startsWith('local/'));
    expect(installed.marketplaceOwner, isNull);
    final installedDir = Directory(p.join(tmp.path, 'plugins', installed.directory));
    expect(installedDir.existsSync(), isTrue);

    // plugins.json updated
    final jsonFile = File(p.join(tmp.path, 'plugins.json'));
    expect(jsonFile.existsSync(), isTrue);
  });

  test('uninstall removes directory and updates plugins.json', () async {
    final svc = PluginInstallService(manifestService: PluginManifestService());
    final installed = await _installMinimal(svc, tmp);
    final dir = Directory(p.join(tmp.path, 'plugins', installed.directory));
    expect(dir.existsSync(), isTrue);

    await svc.uninstall(installed);
    expect(dir.existsSync(), isFalse);
    final backups = Directory(p.join(tmp.path, 'plugin-backups'));
    expect(backups.existsSync() && backups.listSync().isNotEmpty, isTrue);
  });
}

Future<Plugin> _installMinimal(PluginInstallService svc, Directory tmp) async {
  // create a folder layout and call installFromDirectory
  final src = Directory(p.join(tmp.path, 'src-plugin'))..createSync();
  Directory(p.join(src.path, '.claude-plugin')).createSync();
  File(p.join(src.path, '.claude-plugin', 'plugin.json'))
      .writeAsStringSync('{"name":"foo","version":"0.1.0"}');
  return svc.installFromDirectory(src);
}
```

- [ ] **Step 2: Run failing**

Run: `cd client && flutter test test/plugin_install_service_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement `PluginFetchService`**

```dart
// client/lib/services/plugin_fetch_service.dart
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class PluginFetchService {
  /// Extract a zip into [destination]; creates [destination] if missing.
  Future<void> extractZip(File zip, Directory destination) async {
    final bytes = await zip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    if (!destination.existsSync()) destination.createSync(recursive: true);
    for (final entry in archive) {
      final out = p.join(destination.path, entry.name);
      if (entry.isFile) {
        File(out)
          ..createSync(recursive: true)
          ..writeAsBytesSync(entry.content as List<int>);
      } else {
        Directory(out).createSync(recursive: true);
      }
    }
  }

  /// Recursively copy [from] into [to].
  Future<void> copyDirectory(Directory from, Directory to) async {
    if (!to.existsSync()) to.createSync(recursive: true);
    for (final entry in from.listSync(recursive: true)) {
      final rel = p.relative(entry.path, from: from.path);
      final dest = p.join(to.path, rel);
      if (entry is File) {
        File(dest)..createSync(recursive: true)..writeAsBytesSync(entry.readAsBytesSync());
      } else if (entry is Directory) {
        Directory(dest).createSync(recursive: true);
      }
    }
  }
}
```

- [ ] **Step 4: Implement `PluginInstallService`**

```dart
// client/lib/services/plugin_install_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../models/plugin.dart';
import 'app_storage.dart';
import 'plugin_exceptions.dart';
import 'plugin_fetch_service.dart';
import 'plugin_manifest_service.dart';

class PluginInstallService {
  PluginInstallService({
    PluginManifestService? manifestService,
    PluginFetchService? fetchService,
  })  : _manifest = manifestService ?? PluginManifestService(),
        _fetch = fetchService ?? PluginFetchService();

  final PluginManifestService _manifest;
  final PluginFetchService _fetch;

  Future<Plugin> installFromZip(File zip) async {
    final stage = Directory.systemTemp.createTempSync('plugin-stage-');
    try {
      await _fetch.extractZip(zip, stage);
      final pluginDir = _findPluginRoot(stage) ?? stage;
      return _installFromStaged(pluginDir, marketplace: null);
    } finally {
      if (stage.existsSync()) stage.deleteSync(recursive: true);
    }
  }

  Future<Plugin> installFromDirectory(Directory source, {PluginMarketplace? marketplace}) async {
    return _installFromStaged(source, marketplace: marketplace);
  }

  Future<Plugin> _installFromStaged(Directory source, {PluginMarketplace? marketplace}) async {
    final parsed = await _manifest.parseDirectory(source.path);
    final id = marketplace == null
        ? 'local/${_sanitize(parsed.name)}'
        : '${marketplace.owner}/${marketplace.name}/${parsed.name}';
    final dirName = id.replaceAll('/', '__');
    final installRoot = AppStorage.paths.basePath;
    final installDir = Directory(p.join(installRoot, 'plugins', dirName));
    if (installDir.existsSync()) {
      await _backup(installDir);
      installDir.deleteSync(recursive: true);
    }
    await _fetch.copyDirectory(source, installDir);

    final now = DateTime.now().millisecondsSinceEpoch;
    final plugin = Plugin(
      id: id,
      name: parsed.name,
      description: parsed.description,
      version: parsed.version,
      directory: dirName,
      marketplaceOwner: marketplace?.owner,
      marketplaceName: marketplace?.name,
      marketplaceBranch: marketplace?.branch,
      homepageUrl: parsed.homepageUrl,
      capabilities: parsed.capabilities,
      contentHash: _hashDirectory(installDir),
      installedAt: now,
      updatedAt: now,
    );
    await _persistPlugin(plugin);
    return plugin;
  }

  Future<void> uninstall(Plugin plugin) async {
    final dir = Directory(p.join(AppStorage.paths.basePath, 'plugins', plugin.directory));
    if (dir.existsSync()) {
      await _backup(dir);
      dir.deleteSync(recursive: true);
    }
    await _removePersisted(plugin.id);
  }

  Future<Plugin> updateInPlace(Plugin existing, Directory newSource) async {
    final backupDir = await _backup(
      Directory(p.join(AppStorage.paths.basePath, 'plugins', existing.directory)));
    try {
      final updated = await _installFromStaged(
        newSource,
        marketplace: existing.marketplaceOwner != null
            ? PluginMarketplace(
                owner: existing.marketplaceOwner!,
                name: existing.marketplaceName!,
                branch: existing.marketplaceBranch ?? 'main',
              )
            : null,
      );
      return updated;
    } catch (e) {
      // restore backup
      final target = Directory(p.join(AppStorage.paths.basePath, 'plugins', existing.directory));
      if (target.existsSync()) target.deleteSync(recursive: true);
      await _fetch.copyDirectory(backupDir, target);
      throw PluginInstallException(existing.id, 'update failed; restored from backup', cause: e);
    }
  }

  Future<Directory> _backup(Directory dir) async {
    final backupsRoot = Directory(p.join(AppStorage.paths.basePath, 'plugin-backups'));
    if (!backupsRoot.existsSync()) backupsRoot.createSync(recursive: true);
    final id = '${p.basename(dir.path)}-${DateTime.now().millisecondsSinceEpoch}';
    final backup = Directory(p.join(backupsRoot.path, id));
    await _fetch.copyDirectory(dir, backup);
    return backup;
  }

  String _hashDirectory(Directory dir) {
    final hasher = sha256;
    final accumulator = AccumulatorSink<Digest>();
    final input = hasher.startChunkedConversion(accumulator);
    final files = dir.listSync(recursive: true).whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      input.add(utf8.encode(p.relative(f.path, from: dir.path)));
      input.add(f.readAsBytesSync());
    }
    input.close();
    return accumulator.events.single.toString();
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-').toLowerCase();

  Directory? _findPluginRoot(Directory stage) {
    // If the zip contains <root>/.claude-plugin/plugin.json directly, use stage.
    if (File(p.join(stage.path, '.claude-plugin', 'plugin.json')).existsSync()) return stage;
    // Otherwise look one level down (common when zips include a top-level dir).
    for (final entry in stage.listSync()) {
      if (entry is Directory &&
          File(p.join(entry.path, '.claude-plugin', 'plugin.json')).existsSync()) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _persistPlugin(Plugin plugin) async {
    final path = AppStorage.paths.pluginsJson;
    final fs = AppStorage.fs;
    final existing = await fs.exists(path)
        ? (jsonDecode(utf8.decode(await fs.readAsBytes(path))) as Map).cast<String, Object?>()
        : <String, Object?>{};
    final list = ((existing['plugins'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
        .toList();
    list.removeWhere((p) => p.id == plugin.id);
    list.add(plugin);
    existing['plugins'] = list.map((p) => p.toJson()).toList();
    await fs.writeAsString(path, jsonEncode(existing));
  }

  Future<void> _removePersisted(String id) async {
    final path = AppStorage.paths.pluginsJson;
    final fs = AppStorage.fs;
    if (!await fs.exists(path)) return;
    final existing = (jsonDecode(utf8.decode(await fs.readAsBytes(path))) as Map).cast<String, Object?>();
    final list = ((existing['plugins'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
        .toList()
        ..removeWhere((p) => p.id == id);
    existing['plugins'] = list.map((p) => p.toJson()).toList();
    await fs.writeAsString(path, jsonEncode(existing));
  }
}
```

Verify `crypto` and `archive` packages are in `client/pubspec.yaml` (skill services already use them — they should be). If not, add them and run `flutter pub get`.

- [ ] **Step 5: Run + commit**

```bash
cd client && flutter test test/plugin_install_service_test.dart
git add client/lib/services/plugin_fetch_service.dart client/lib/services/plugin_install_service.dart client/test/plugin_install_service_test.dart
git commit -m "feat(plugin): add PluginFetchService and PluginInstallService with install/uninstall/update"
```

---

### Task 12: `PluginRepository` (read-only facade for the cubit)

**Files:**
- Create: `client/lib/repositories/plugin_repository.dart`

- [ ] **Step 1: Implement**

```dart
import 'dart:convert';
import '../models/plugin.dart';
import '../services/app_storage.dart';
import '../services/flashskyai_storage_roots.dart';

class PluginRepository {
  PluginRepository({FlashskyaiStorageRoots? storageRoots})
      : _storageRoots = storageRoots;

  final FlashskyaiStorageRoots? _storageRoots;

  Future<List<Plugin>> loadAll() async {
    final path = _storageRoots != null
        ? (await _storageRoots.resolve()).pluginsJsonPath
        : AppStorage.paths.pluginsJson;
    final fs = _storageRoots != null
        ? (await _storageRoots.resolve()).fs
        : AppStorage.fs;
    if (!await fs.exists(path)) return const [];
    final bytes = await fs.readAsBytes(path);
    if (bytes.isEmpty) return const [];
    final root = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    final list = (root['plugins'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
        .toList();
    return list;
  }

  Future<Plugin?> findById(String id) async {
    final list = await loadAll();
    try {
      return list.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add client/lib/repositories/plugin_repository.dart
git commit -m "feat(plugin): add PluginRepository read facade"
```

---

## Phase 2 — Plugin Management Page (Tasks 13–18)

---

### Task 13: `PluginCubit` + `PluginState`

**Files:**
- Create: `client/lib/cubits/plugin_cubit.dart`
- Test: `client/test/plugin_cubit_test.dart`

- [ ] **Step 1: Write test for core events**

```dart
import 'dart:io';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/plugin_install_service.dart';
import 'package:teampilot/services/plugin_manifest_service.dart';
import 'package:teampilot/services/plugin_repo_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-cubit-');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(tmp.path));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('load() populates installed + marketplaces', () async {
    final cubit = PluginCubit(
      repository: PluginRepository(),
      installService: PluginInstallService(manifestService: PluginManifestService()),
      repoService: PluginRepoService(),
    );
    await cubit.load();
    expect(cubit.state.status, PluginLoadStatus.ready);
    expect(cubit.state.marketplaces, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run failing**

Run: `cd client && flutter test test/plugin_cubit_test.dart`
Expected: FAIL

- [ ] **Step 3: Implement cubit (mirrors `skill_cubit.dart` shape)**

Open `client/lib/cubits/skill_cubit.dart` for reference. Create `plugin_cubit.dart` with the state and methods listed in spec §4.4:

```dart
import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/plugin.dart';
import '../repositories/plugin_repository.dart';
import '../services/plugin_install_service.dart';
import '../services/plugin_repo_disk_cache_service.dart';
import '../services/plugin_repo_service.dart';

enum PluginLoadStatus { idle, loading, ready, error }

class PluginState extends Equatable {
  const PluginState({
    this.installed = const [],
    this.marketplaces = const [],
    this.discoverable = const [],
    this.updates = const [],
    this.status = PluginLoadStatus.idle,
    this.errorMessage,
    this.busyIds = const {},
    this.discoveryLoading = false,
    this.updatesLoading = false,
    this.marketplaceSyncingKeys = const {},
  });

  final List<Plugin> installed;
  final List<PluginMarketplace> marketplaces;
  final List<DiscoverablePlugin> discoverable;
  final List<PluginUpdateInfo> updates;
  final PluginLoadStatus status;
  final String? errorMessage;
  final Set<String> busyIds;
  final bool discoveryLoading;
  final bool updatesLoading;
  final Set<String> marketplaceSyncingKeys;

  PluginState copyWith({
    List<Plugin>? installed,
    List<PluginMarketplace>? marketplaces,
    List<DiscoverablePlugin>? discoverable,
    List<PluginUpdateInfo>? updates,
    PluginLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    Set<String>? busyIds,
    bool? discoveryLoading,
    bool? updatesLoading,
    Set<String>? marketplaceSyncingKeys,
  }) => PluginState(
    installed: installed ?? this.installed,
    marketplaces: marketplaces ?? this.marketplaces,
    discoverable: discoverable ?? this.discoverable,
    updates: updates ?? this.updates,
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    busyIds: busyIds ?? this.busyIds,
    discoveryLoading: discoveryLoading ?? this.discoveryLoading,
    updatesLoading: updatesLoading ?? this.updatesLoading,
    marketplaceSyncingKeys: marketplaceSyncingKeys ?? this.marketplaceSyncingKeys,
  );

  @override
  List<Object?> get props => [
    installed, marketplaces, discoverable, updates, status, errorMessage,
    busyIds, discoveryLoading, updatesLoading, marketplaceSyncingKeys,
  ];
}

class PluginCubit extends Cubit<PluginState> {
  PluginCubit({
    required this.repository,
    required this.installService,
    required this.repoService,
    PluginRepoDiskCacheService? diskCache,
  })  : _diskCache = diskCache ?? PluginRepoDiskCacheService(),
        super(const PluginState());

  final PluginRepository repository;
  final PluginInstallService installService;
  final PluginRepoService repoService;
  final PluginRepoDiskCacheService _diskCache;

  Future<void> load() async {
    emit(state.copyWith(status: PluginLoadStatus.loading, clearError: true));
    try {
      final installed = await repository.loadAll();
      final markets = await repoService.loadMarketplaces();
      emit(state.copyWith(
        installed: installed,
        marketplaces: markets,
        status: PluginLoadStatus.ready,
      ));
    } catch (e) {
      emit(state.copyWith(status: PluginLoadStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> refreshDiscoverable() async {
    emit(state.copyWith(discoveryLoading: true, clearError: true));
    try {
      final all = <DiscoverablePlugin>[];
      for (final m in state.marketplaces.where((m) => m.enabled)) {
        try {
          all.addAll(await _diskCache.discoverablePlugins(m));
        } catch (e) {
          // log + continue
        }
      }
      emit(state.copyWith(discoverable: all, discoveryLoading: false));
    } catch (e) {
      emit(state.copyWith(discoveryLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> installFromDiscovery(DiscoverablePlugin d) async {
    final ids = Set<String>.from(state.busyIds)..add(d.key);
    emit(state.copyWith(busyIds: ids));
    try {
      final marketDir = await _diskCache.syncMarketplace(PluginMarketplace(
        owner: d.marketplaceOwner, name: d.marketplaceName, branch: d.marketplaceBranch));
      final sourceDir = Directory('$marketDir/${d.source}');
      await installService.installFromDirectory(
        sourceDir,
        marketplace: PluginMarketplace(
          owner: d.marketplaceOwner, name: d.marketplaceName, branch: d.marketplaceBranch),
      );
      await load();
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    } finally {
      final next = Set<String>.from(state.busyIds)..remove(d.key);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> installFromZip(File zip) async {
    try {
      await installService.installFromZip(zip);
      await load();
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> uninstall(Plugin plugin) async {
    final ids = Set<String>.from(state.busyIds)..add(plugin.id);
    emit(state.copyWith(busyIds: ids));
    try {
      await installService.uninstall(plugin);
      await load();
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    } finally {
      final next = Set<String>.from(state.busyIds)..remove(plugin.id);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> addMarketplace(PluginMarketplace m) async {
    await repoService.addMarketplace(m);
    await load();
  }

  Future<void> removeMarketplace(String owner, String name) async {
    await repoService.removeMarketplace(owner, name);
    await load();
  }

  Future<void> toggleMarketplaceEnabled(PluginMarketplace m, bool enabled) async {
    await repoService.setEnabled(m.owner, m.name, enabled);
    await load();
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
```

- [ ] **Step 4: Run + commit**

```bash
cd client && flutter test test/plugin_cubit_test.dart
git add client/lib/cubits/plugin_cubit.dart client/test/plugin_cubit_test.dart
git commit -m "feat(plugin): add PluginCubit with load/install/uninstall/marketplace events"
```

---

### Task 14: i18n keys for plugin management

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Run: code-gen to regenerate `app_localizations*.dart`

- [ ] **Step 1: Add keys to `app_en.arb`** (insert after the `skills*` block)

```json
"pluginsTitle": "Plugins",
"pluginsSubtitle": "Manage Claude Code-style plugin bundles",
"pluginsNavInstalled": "Installed",
"pluginsNavDiscovery": "Discovery",
"pluginsNavMarketplaces": "Marketplaces",
"pluginsInstalledCount": "{count} installed",
"@pluginsInstalledCount": {
  "placeholders": { "count": { "type": "int" } }
},
"pluginsUpdateAll": "Update all ({count})",
"@pluginsUpdateAll": {
  "placeholders": { "count": { "type": "int" } }
},
"pluginsImportFromDisk": "Import from disk",
"pluginsInstallFromZip": "Install from ZIP",
"pluginsCheckUpdates": "Check updates",
"pluginsCheckingUpdates": "Checking…",
"pluginsNoInstalled": "No plugins installed",
"pluginsNoInstalledHint": "Add a marketplace and install plugins from the Discovery tab.",
"pluginsGoDiscovery": "Browse marketplace",
"pluginsCardInstall": "Install",
"pluginsCardInstalled": "Installed",
"pluginsCardUpdate": "Update",
"pluginsCardUninstall": "Uninstall",
"pluginsMarketplaceAdd": "Add marketplace",
"pluginsMarketplaceUrl": "GitHub repository URL",
"pluginsMarketplaceUrlHint": "https://github.com/owner/marketplace",
"pluginsMarketplaceBranch": "Branch",
"pluginsMarketplaceRemove": "Remove marketplace",
"pluginsMarketplaceRemoveConfirm": "Remove marketplace {url}? Installed plugins are kept.",
"@pluginsMarketplaceRemoveConfirm": {
  "placeholders": { "url": { "type": "String" } }
},
"pluginsMarketplaceInvalidUrl": "Please enter a valid GitHub repository URL.",
"pluginsMarketplacesEmpty": "No marketplaces configured",
"pluginsSearchPlaceholder": "Search plugins",
"pluginsFilterMarketplaceAll": "All marketplaces",
"pluginsFilterAll": "All",
"pluginsFilterInstalled": "Installed",
"pluginsFilterUninstalled": "Not installed",
"pluginsDiscoveryEmpty": "No matching plugins",
"pluginsUninstallConfirm": "Uninstall {name}? This may affect {n} team(s).",
"@pluginsUninstallConfirm": {
  "placeholders": { "name": { "type": "String" }, "n": { "type": "int" } }
},
"pluginsUninstallSuccess": "Uninstalled {name}",
"@pluginsUninstallSuccess": {
  "placeholders": { "name": { "type": "String" } }
}
```

- [ ] **Step 2: Add same keys to `app_zh.arb`** with Chinese values:

```json
"pluginsTitle": "插件",
"pluginsSubtitle": "管理 Claude Code 风格插件包",
"pluginsNavInstalled": "已安装",
"pluginsNavDiscovery": "发现",
"pluginsNavMarketplaces": "Marketplaces",
"pluginsInstalledCount": "已安装 {count} 个",
"pluginsUpdateAll": "全部更新 ({count})",
"pluginsImportFromDisk": "从目录导入",
"pluginsInstallFromZip": "从 ZIP 安装",
"pluginsCheckUpdates": "检查更新",
"pluginsCheckingUpdates": "检查中…",
"pluginsNoInstalled": "尚未安装插件",
"pluginsNoInstalledHint": "在 Marketplaces 选项卡添加 marketplace，然后在 Discovery 中安装。",
"pluginsGoDiscovery": "浏览 marketplace",
"pluginsCardInstall": "安装",
"pluginsCardInstalled": "已安装",
"pluginsCardUpdate": "更新",
"pluginsCardUninstall": "卸载",
"pluginsMarketplaceAdd": "添加 marketplace",
"pluginsMarketplaceUrl": "GitHub 仓库地址",
"pluginsMarketplaceUrlHint": "https://github.com/owner/marketplace",
"pluginsMarketplaceBranch": "分支",
"pluginsMarketplaceRemove": "移除 marketplace",
"pluginsMarketplaceRemoveConfirm": "确认移除 marketplace {url}？已安装的插件会保留。",
"pluginsMarketplaceInvalidUrl": "请输入合法的 GitHub 仓库地址。",
"pluginsMarketplacesEmpty": "尚未配置 marketplace",
"pluginsSearchPlaceholder": "搜索插件",
"pluginsFilterMarketplaceAll": "全部 marketplace",
"pluginsFilterAll": "全部",
"pluginsFilterInstalled": "已安装",
"pluginsFilterUninstalled": "未安装",
"pluginsDiscoveryEmpty": "无匹配的插件",
"pluginsUninstallConfirm": "确认卸载 {name}？将影响 {n} 个团队。",
"pluginsUninstallSuccess": "已卸载 {name}"
```

- [ ] **Step 3: Regenerate localizations**

Run: `cd client && flutter gen-l10n`
Expected: updates `app_localizations*.dart` files

- [ ] **Step 4: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations*.dart
git commit -m "feat(plugin): add i18n keys for plugin management UI"
```

---

### Task 15: Router registration

**Files:**
- Modify: `client/lib/router/app_router.dart`
- Modify: `client/lib/router/android_shell_chrome.dart` (titles)
- Modify wherever skills hub entry lives — find it via:

```bash
grep -rn "skillsHub\|/skills" client/lib --include='*.dart'
```

Locate the place where the skills entry is added to the workspace shell. The plugin entry must appear at the same level.

- [ ] **Step 1: Add `PluginCubit` to MultiBlocProvider**

In `client/lib/app/app_shell.dart` (mirror skill cubit registration). Find skill cubit registration:

```bash
grep -n "SkillCubit" client/lib/app/app_shell.dart
```

Then add right next to it:

```dart
BlocProvider(create: (ctx) => PluginCubit(
  repository: PluginRepository(),
  installService: PluginInstallService(),
  repoService: PluginRepoService(),
)..load()),
```

with the matching import.

- [ ] **Step 2: Add routes (in `app_router.dart`, around lines 243-264)**

```dart
GoRoute(
  path: '/plugins',
  redirect: (context, state) {
    if (state.uri.path == '/plugins') return '/plugins/installed';
    return null;
  },
),
GoRoute(
  path: '/plugins/installed',
  builder: (_, __) => const PluginManagementPage(section: PluginSection.installed),
),
GoRoute(
  path: '/plugins/discovery',
  builder: (_, __) => const PluginManagementPage(section: PluginSection.discovery),
),
GoRoute(
  path: '/plugins/marketplaces',
  builder: (_, __) => const PluginManagementPage(section: PluginSection.marketplaces),
),
```

with import: `import '../pages/plugin_management_page.dart';`

- [ ] **Step 3: Commit (without page yet — gives a broken build but lets us split work)**

Actually, do not commit until Task 16 creates the page; otherwise build fails. Move this to the end of Task 16.

---

### Task 16: `PluginManagementPage` shell (Hub + three-section split)

**Files:**
- Create: `client/lib/pages/plugin_management_page.dart`
- Modify: `client/lib/utils/app_keys.dart` (add `pluginsHub` / `pluginsWorkspace` keys)

- [ ] **Step 1: Mirror skill page structure exactly**

The simplest path is to copy `client/lib/pages/skill_management_page.dart` to `plugin_management_page.dart`, rename:
- `SkillSection` → `PluginSection { installed, discovery, marketplaces }`
- `SkillManagementHubPage` / `SkillManagementPage` → `PluginManagementHubPage` / `PluginManagementPage`
- `SkillCubit` → `PluginCubit`
- `SkillState` → `PluginState`
- Strip out: `_DiscoverySection`'s source-toggle (`_SearchSource` toggles between repos/skillsSh — plugins only have marketplaces, drop the toggle and skills.sh code path)
- Replace `repos` field references with `marketplaces`
- Replace skill l10n keys with `pluginsXxx`
- Remove the `_SkillsNavPanel` "Repos"/"Skills" enum mapping, swap for plugin equivalents

Sections to keep:
- Installed (no enable Switch, no team count badge — keep only Update/Uninstall trailing buttons)
- Discovery (marketplace dropdown filter + status filter; no skills.sh toggle/grid)
- Marketplaces (mirrors `_ReposSection` 1:1)

This is mechanical translation. After the copy, run `flutter analyze` and fix import errors / dropped fields.

- [ ] **Step 2: Add app keys**

In `client/lib/utils/app_keys.dart` add:

```dart
static const pluginsHub = ValueKey('plugins-hub');
static const pluginsWorkspace = ValueKey('plugins-workspace');
```

- [ ] **Step 3: Add Hub entry**

In the workspace shell (the file you found via `grep -rn "skillsHub"`), duplicate the skills entry to add plugins entry under it.

- [ ] **Step 4: Verify build**

Run:

```bash
cd client && flutter pub get && flutter analyze
```

Expected: 0 errors. Warnings about unused widgets are OK if any remain from copying.

- [ ] **Step 5: Run app smoke test**

Run: `cd client && flutter run -d windows` (or `linux`/`macos`). Navigate to `/plugins`. Expect to see the three-section layout with empty state and the default marketplace listed.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/plugin_management_page.dart client/lib/router/app_router.dart client/lib/app/app_shell.dart client/lib/utils/app_keys.dart
git commit -m "feat(plugin): add plugin management page with three-section nav"
```

---

### Task 17: Widget test for Plugin management page

**Files:**
- Create: `client/test/plugin_management_page_test.dart`

- [ ] **Step 1: Write smoke test**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/plugin_management_page.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/plugin_install_service.dart';
import 'package:teampilot/services/plugin_repo_service.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-page-');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(tmp.path));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget _wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider(
      create: (_) => PluginCubit(
        repository: PluginRepository(),
        installService: PluginInstallService(),
        repoService: PluginRepoService(),
      )..load(),
      child: child,
    ),
  );

  testWidgets('Installed section renders empty state', (tester) async {
    await tester.pumpWidget(_wrap(const PluginManagementPage(section: PluginSection.installed)));
    await tester.pumpAndSettle();
    expect(find.text('No plugins installed'), findsOneWidget);
  });

  testWidgets('Marketplaces section lists default marketplace', (tester) async {
    await tester.pumpWidget(_wrap(const PluginManagementPage(section: PluginSection.marketplaces)));
    await tester.pumpAndSettle();
    expect(find.textContaining('github.com/anthropics/claude-plugins-official'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run + commit**

```bash
cd client && flutter test test/plugin_management_page_test.dart
git add client/test/plugin_management_page_test.dart
git commit -m "test(plugin): smoke-test plugin management page sections"
```

---

### Task 18: `flutter test` and `flutter analyze` pass for Phase 2

- [ ] **Step 1: Run full test suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: All pass.

- [ ] **Step 2: Run analyzer**

Run: `cd client && flutter analyze`
Expected: 0 errors.

- [ ] **Step 3: If failures, fix root cause** (no `--no-verify`, no skipping tests)

---

## Phase 3 — Team Integration (Tasks 19–23)

---

### Task 19: `TeamPluginLinkerService`

**Files:**
- Create: `client/lib/services/team_plugin_linker_service.dart`
- Test: `client/test/team_plugin_linker_service_test.dart`

- [ ] **Step 1: Read existing skill linker for the exact pattern**

Open `client/lib/services/team_skill_linker_service.dart` end-to-end. The plugin version is structurally identical — read it before writing the plugin one.

- [ ] **Step 2: Write test**

```dart
import 'dart:io';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/cli_data_layout.dart';
import 'package:teampilot/services/team_plugin_linker_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-link-');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(tmp.path));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('syncTeam creates link/copy under team plugin dir for each enabled plugin', () async {
    // Create a plugin source dir
    final pluginsRoot = Directory(p.join(tmp.path, 'plugins'))..createSync();
    Directory(p.join(pluginsRoot.path, 'acme__market__p1'))..createSync();

    final layout = CliDataLayout(teampilotRoot: tmp.path, fs: AppStorage.fs);
    final svc = TeamPluginLinkerService(appPluginsRoot: pluginsRoot.path);
    final result = await svc.syncTeam(
      teamId: 't1',
      enabledPluginIds: ['acme/market/p1'],
      allInstalledPlugins: const [
        Plugin(
          id: 'acme/market/p1',
          name: 'p1',
          description: '',
          version: '1.0.0',
          directory: 'acme__market__p1',
          marketplaceOwner: 'acme',
          marketplaceName: 'market',
          marketplaceBranch: 'main',
          capabilities: PluginCapabilities(),
          installedAt: 0,
          updatedAt: 0,
        ),
      ],
      layout: layout,
    );

    expect(result.errors, isEmpty);
    expect(result.linked, ['acme/market/p1']);

    final teamPluginDir = p.join(layout.teamCliRoot('t1', 'flashskyai'), 'plugins', 'p1');
    expect(Directory(teamPluginDir).existsSync() || File(teamPluginDir).existsSync(), isTrue);
  });

  test('syncTeam removes stale links not in enabledPluginIds', () async {
    // setup: pre-populate team plugins dir with a stale entry
    final layout = CliDataLayout(teampilotRoot: tmp.path, fs: AppStorage.fs);
    final teamPluginsDir = Directory(p.join(layout.teamCliRoot('t1', 'flashskyai'), 'plugins'))
      ..createSync(recursive: true);
    Directory(p.join(teamPluginsDir.path, 'old-plugin'))..createSync();

    final svc = TeamPluginLinkerService(appPluginsRoot: p.join(tmp.path, 'plugins'));
    final result = await svc.syncTeam(
      teamId: 't1',
      enabledPluginIds: const [],
      allInstalledPlugins: const [],
      layout: layout,
    );
    expect(result.linked, isEmpty);
    expect(Directory(p.join(teamPluginsDir.path, 'old-plugin')).existsSync(), isFalse);
  });

  test('syncTeam reports skippedMissingIds when plugin source is missing', () async {
    final layout = CliDataLayout(teampilotRoot: tmp.path, fs: AppStorage.fs);
    final svc = TeamPluginLinkerService(appPluginsRoot: p.join(tmp.path, 'plugins'));
    final result = await svc.syncTeam(
      teamId: 't1',
      enabledPluginIds: ['gone/market/p'],
      allInstalledPlugins: const [],
      layout: layout,
    );
    expect(result.skippedMissingIds, ['gone/market/p']);
  });
}
```

- [ ] **Step 3: Run failing**

Run: `cd client && flutter test test/team_plugin_linker_service_test.dart`
Expected: FAIL

- [ ] **Step 4: Implement** by copying `team_skill_linker_service.dart` and substituting:

- `Skill` → `Plugin`
- `skillIds` → `pluginIds`
- `appSkillsDir` → `appPluginsDir`
- `teamSkillsDir(teamId)` → `teamPluginsDir(teamId)` (new method on CliDataLayout) **OR** inline the path `${layout.teamCliRoot(teamId, 'flashskyai')}/plugins`
- `TeamSkillSyncResult` → `TeamPluginSyncResult`

If `CliDataLayout.teamPluginsDir` doesn't exist, add it:

```dart
// in client/lib/services/cli_data_layout.dart
String teamPluginsDir(String teamId) =>
    fs.pathContext.join(teamCliRoot(teamId, 'flashskyai'), 'plugins');
```

(check the exact existing method `teamSkillsDir` for the shape).

The linker's `sourceDirFor(Plugin p)` is `${appPluginsDir}/${p.directory}`.

Target dir name in team is `${plugin.name}` (or fallback `${marketplaceOwner}__${plugin.name}` on collision, recorded in `result.conflictResolutions`).

- [ ] **Step 5: Run + commit**

```bash
cd client && flutter test test/team_plugin_linker_service_test.dart
git add client/lib/services/team_plugin_linker_service.dart client/lib/services/cli_data_layout.dart client/test/team_plugin_linker_service_test.dart
git commit -m "feat(team): add TeamPluginLinkerService mirroring TeamSkillLinkerService"
```

---

### Task 20: TeamCubit integration — sync plugins on team save

**Files:**
- Modify: `client/lib/cubits/team_cubit.dart` (find the place where `skillIds` change triggers `TeamSkillLinkerService`)

- [ ] **Step 1: Locate hook point**

```bash
grep -n "TeamSkillLinker\|skillIds\|isSyncingSkills" client/lib/cubits/team_cubit.dart
```

- [ ] **Step 2: Add parallel plugin sync**

For every place where `TeamSkillLinkerService.syncTeam` is invoked, add the corresponding `TeamPluginLinkerService.syncTeam` call. Add an `isSyncingPlugins` boolean to `TeamState` if needed (mirror `isSyncingSkills`).

Specifically:

1. Add field `TeamPluginLinkerService linkerPlugins` to `TeamCubit` ctor.
2. In the method that fires after `team.copyWith(skillIds: ...)`, also include `pluginIds`. Pattern: any call that does

```dart
await linkerSkills.syncTeam(
  teamId: team.id,
  enabledSkillIds: team.skillIds,
  allInstalledSkills: installed,
  layout: layout,
);
```

Add immediately after:

```dart
await linkerPlugins.syncTeam(
  teamId: team.id,
  enabledPluginIds: team.pluginIds,
  allInstalledPlugins: pluginsInstalled,
  layout: layout,
);
```

where `pluginsInstalled` comes from `await pluginRepository.loadAll()` (inject `PluginRepository` into `TeamCubit`).

3. On team deletion, after removing skill team dir, also remove `${layout.teamCliRoot(teamId, 'flashskyai')}/plugins` entirely.

- [ ] **Step 3: Update TeamCubit test**

Open `client/test/team_cubit_test.dart`. Find the test setup that constructs `TeamCubit` and add `linkerPlugins: FakeLinker()` + `pluginRepository: ...` as needed (mirroring how skill linker is faked).

- [ ] **Step 4: Run + commit**

```bash
cd client && flutter test test/team_cubit_test.dart
git add client/lib/cubits/team_cubit.dart client/test/team_cubit_test.dart
git commit -m "feat(team): sync TeamPluginLinkerService alongside skill linker"
```

---

### Task 21: Team config page — plugin section

**Files:**
- Modify: `client/lib/pages/team_config_page.dart`

- [ ] **Step 1: Add `plugins` to `TeamConfigSection` enum**

Locate `enum TeamConfigSection { team, skills, members }` and change to:

```dart
enum TeamConfigSection { team, skills, plugins, members }
```

Update the `_segmentFor` (line 28-37 area) and any nav builder to include `plugins`.

- [ ] **Step 2: Add nav entry and route**

In the nav hub list section (around line 111), add an entry after skills:

```dart
WorkspaceHubEntry(
  title: l10n.teamPluginsNav,
  icon: Icons.extension_outlined,
  onTap: () => context.push('/team-config/plugins'),
),
```

In `client/lib/router/app_router.dart` add the route mirroring `/team-config/skills`:

```dart
GoRoute(
  path: '/team-config/plugins',
  builder: (_, __) => const TeamConfigPage(section: TeamConfigSection.plugins),
),
```

- [ ] **Step 3: Add the `_TeamPluginsSection` widget**

Copy `_TeamSkillsSection` (lines 540-617) to `_TeamPluginsSection`. Substitute:

- `SkillCubit` → `PluginCubit`
- `skillState.installed` → `pluginState.installed`
- `team.skillIds` → `team.pluginIds`
- `cubit.updateSelected(team.copyWith(skillIds: ids))` → `cubit.updateSelected(team.copyWith(pluginIds: ids))`
- `_TeamSkillRow` widget → `_TeamPluginRow` (copy + substitute)
- `l10n.teamSkills*` keys → `l10n.teamPlugins*` keys
- `'/skills'` route → `'/plugins'` route
- Drop the "syncing" spinner if `isSyncingPlugins` isn't surfaced yet; keep it as TODO-free by reading `context.watch<TeamCubit>().state.isSyncingPlugins` once added in Task 20

Add a CLI-unsupported banner at the top:

```dart
if (team.cli == TeamCli.codex)
  Container(
    padding: const EdgeInsets.all(10),
    color: Colors.amber.withValues(alpha: 0.15),
    child: Text(l10n.teamPluginsCliUnsupportedBanner),
  ),
```

Add missing-plugin badge:

```dart
final installedIds = pluginState.installed.map((p) => p.id).toSet();
final missing = team.pluginIds.where((id) => !installedIds.contains(id)).toList();
if (missing.isNotEmpty)
  Container(
    // ...
    child: Text(l10n.teamPluginsMissing(missing.length)),
  ),
```

- [ ] **Step 4: Add team-plugin i18n keys**

In `app_en.arb`:

```json
"teamPluginsNav": "Plugins",
"teamPluginsAssignedCount": "{count} enabled",
"@teamPluginsAssignedCount": { "placeholders": { "count": { "type": "int" } } },
"teamPluginsManage": "Manage plugins",
"teamPluginsEmpty": "No plugins installed yet.",
"teamPluginsEmptyHint": "Install plugins from Discovery to enable them per team.",
"teamPluginsCliUnsupportedBanner": "This team's CLI does not support plugins yet. Selections are saved but ignored at launch.",
"teamPluginsMissing": "{count} enabled plugin(s) missing on disk. Reinstall to restore.",
"@teamPluginsMissing": { "placeholders": { "count": { "type": "int" } } }
```

In `app_zh.arb`:

```json
"teamPluginsNav": "插件",
"teamPluginsAssignedCount": "已启用 {count} 个",
"teamPluginsManage": "管理插件",
"teamPluginsEmpty": "尚未安装插件。",
"teamPluginsEmptyHint": "在「发现」中安装插件后，可在此处按团队启用。",
"teamPluginsCliUnsupportedBanner": "当前团队 CLI 暂不支持插件，启用记录已保存但不会生效。",
"teamPluginsMissing": "有 {count} 个已启用插件在磁盘上缺失，重新安装可恢复。"
```

Regenerate:

```bash
cd client && flutter gen-l10n
```

- [ ] **Step 5: Run app + commit**

```bash
cd client && flutter analyze
git add client/lib/pages/team_config_page.dart client/lib/router/app_router.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations*.dart
git commit -m "feat(team): add plugin section to team config page with missing/unsupported banners"
```

---

### Task 22: Session startup sync

**Files:**
- Modify: `client/lib/services/session_lifecycle_service.dart` (or wherever team launch happens)

- [ ] **Step 1: Locate the existing skill-sync call**

```bash
grep -rn "TeamSkillLinker\|syncTeam" client/lib --include='*.dart'
```

The session lifecycle pre-launch hook should already call `TeamSkillLinkerService.syncTeam`. Add the parallel plugin sync immediately after.

- [ ] **Step 2: Add the call**

Wherever the existing skill sync runs (likely in `SessionLifecycleService` or `TeamCubit.launchTeam`), append:

```dart
await teamPluginLinker.syncTeam(
  teamId: team.id,
  enabledPluginIds: team.pluginIds,
  allInstalledPlugins: await pluginRepository.loadAll(),
  layout: layout,
);
```

Wire `teamPluginLinker` and `pluginRepository` through DI (constructor params on the affected service).

- [ ] **Step 3: Run app, launch a team, verify**

Run: `cd client && flutter run -d windows` → start a team → check that `<teampilotRoot>/config-profiles/teams/<teamId>/flashskyai/plugins/` exists when `pluginIds` non-empty, is empty (or absent) when not.

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/session_lifecycle_service.dart  # or whichever file changed
git commit -m "feat(team): sync plugin links before team session launch"
```

---

### Task 23: Phase 3 test + analyze

- [ ] Run: `cd client && flutter test --exclude-tags integration`
- [ ] Run: `cd client && flutter analyze`
- [ ] Both must be clean. Fix root causes if not.

---

## Phase 4 — Edge cases and observability (Tasks 24–27)

---

### Task 24: Uninstall impact dialog

**Files:**
- Modify: `client/lib/pages/plugin_management_page.dart`
- Modify: `client/lib/cubits/plugin_cubit.dart`

- [ ] **Step 1: Add `computeUninstallImpact(pluginId)` to `PluginCubit`**

```dart
Future<List<String>> computeUninstallImpact(String pluginId, List<TeamConfig> teams) {
  return Future.value(teams
      .where((t) => t.pluginIds.contains(pluginId))
      .map((t) => t.name)
      .toList());
}
```

- [ ] **Step 2: In Installed section row's uninstall handler**

Before calling `uninstall`, fetch `teamCubit.state.teams`, compute impact via `cubit.computeUninstallImpact(plugin.id, teams)`, render confirm dialog using `pluginsUninstallConfirm(plugin.name, impact.length)` with impacted team names listed in the body.

- [ ] **Step 3: After confirmed uninstall, remove pluginId from each impacted team**

```dart
for (final t in impactedTeams) {
  final updated = t.copyWith(pluginIds: t.pluginIds.where((id) => id != plugin.id).toList());
  await teamCubit.update(updated);
}
await pluginCubit.uninstall(plugin);
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/plugin_management_page.dart client/lib/cubits/plugin_cubit.dart
git commit -m "feat(plugin): show uninstall impact and cascade-remove from teams"
```

---

### Task 25: ID conflict resolution in linker

**Files:**
- Modify: `client/lib/services/team_plugin_linker_service.dart`

- [ ] **Step 1: Add conflict test in `team_plugin_linker_service_test.dart`**

```dart
  test('syncTeam falls back to owner__name on plugin-name collision', () async {
    final pluginsRoot = Directory(p.join(tmp.path, 'plugins'))..createSync();
    Directory(p.join(pluginsRoot.path, 'acmeA__market__shared'))..createSync();
    Directory(p.join(pluginsRoot.path, 'acmeB__market__shared'))..createSync();
    final layout = CliDataLayout(teampilotRoot: tmp.path, fs: AppStorage.fs);

    final svc = TeamPluginLinkerService(appPluginsRoot: pluginsRoot.path);
    final result = await svc.syncTeam(
      teamId: 't1',
      enabledPluginIds: ['acmeA/market/shared', 'acmeB/market/shared'],
      allInstalledPlugins: [
        const Plugin(id: 'acmeA/market/shared', name: 'shared', description: '',
          version: '1.0.0', directory: 'acmeA__market__shared',
          marketplaceOwner: 'acmeA', marketplaceName: 'market', marketplaceBranch: 'main',
          capabilities: PluginCapabilities(), installedAt: 0, updatedAt: 0),
        const Plugin(id: 'acmeB/market/shared', name: 'shared', description: '',
          version: '1.0.0', directory: 'acmeB__market__shared',
          marketplaceOwner: 'acmeB', marketplaceName: 'market', marketplaceBranch: 'main',
          capabilities: PluginCapabilities(), installedAt: 0, updatedAt: 0),
      ],
      layout: layout,
    );
    expect(result.conflictResolutions, hasLength(1));
    final teamDir = p.join(layout.teamCliRoot('t1', 'flashskyai'), 'plugins');
    expect(Directory(p.join(teamDir, 'shared')).existsSync(), isTrue);
    expect(Directory(p.join(teamDir, 'acmeB__shared')).existsSync(), isTrue);
  });
```

- [ ] **Step 2: Implement conflict handling in `syncTeam`**

Maintain a `Set<String> usedNames` while iterating enabled plugins. If `plugin.name` already used, derive `'${plugin.marketplaceOwner}__${plugin.name}'` and append `(id, fallbackName)` to `result.conflictResolutions`. Add field `List<(String,String)> conflictResolutions` to `TeamPluginSyncResult`.

- [ ] **Step 3: Run + commit**

```bash
cd client && flutter test test/team_plugin_linker_service_test.dart
git add client/lib/services/team_plugin_linker_service.dart client/test/team_plugin_linker_service_test.dart
git commit -m "feat(plugin): resolve plugin-name collisions in team linker with owner prefix"
```

---

### Task 26: Integration test — end-to-end lifecycle

**Files:**
- Create: `client/test/integration/plugin_team_lifecycle_test.dart`

- [ ] **Step 1: Write integration test**

```dart
@Tags(['integration'])
library plugin_team_lifecycle_test;

import 'dart:io';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/cli_data_layout.dart';
import 'package:teampilot/services/plugin_install_service.dart';
import 'package:teampilot/services/team_plugin_linker_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-integ-');
    AppPathsBootstrapper.setCurrentForTesting(AppPaths(tmp.path));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('full lifecycle: install → enable for team → sync → uninstall', () async {
    // 1. Install a local plugin
    final src = Directory(p.join(tmp.path, 'pluginsrc'))..createSync();
    Directory(p.join(src.path, '.claude-plugin')).createSync();
    File(p.join(src.path, '.claude-plugin', 'plugin.json'))
        .writeAsStringSync('{"name":"p1","version":"1.0.0"}');

    final installSvc = PluginInstallService();
    final plugin = await installSvc.installFromDirectory(src);

    // 2. Build a team with this plugin enabled
    final team = TeamConfig(id: 't1', name: 'T1', pluginIds: [plugin.id]);

    // 3. Sync linker
    final layout = CliDataLayout(teampilotRoot: tmp.path, fs: AppStorage.fs);
    final linker = TeamPluginLinkerService(appPluginsRoot: p.join(tmp.path, 'plugins'));
    final repo = PluginRepository();
    final installed = await repo.loadAll();

    final result = await linker.syncTeam(
      teamId: team.id,
      enabledPluginIds: team.pluginIds,
      allInstalledPlugins: installed,
      layout: layout,
    );
    expect(result.linked, hasLength(1));
    final teamPluginDir = p.join(layout.teamCliRoot('t1', 'flashskyai'), 'plugins', 'p1');
    expect(Directory(teamPluginDir).existsSync() || File(teamPluginDir).existsSync(), isTrue);

    // 4. Uninstall + sync again
    await installSvc.uninstall(plugin);
    final repoAfter = PluginRepository();
    final installedAfter = await repoAfter.loadAll();
    await linker.syncTeam(
      teamId: team.id,
      enabledPluginIds: const [],
      allInstalledPlugins: installedAfter,
      layout: layout,
    );
    expect(Directory(teamPluginDir).existsSync() || File(teamPluginDir).existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: Run**

Run: `cd client && flutter test test/integration/plugin_team_lifecycle_test.dart --tags integration`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add client/test/integration/plugin_team_lifecycle_test.dart
git commit -m "test(plugin): add end-to-end lifecycle integration test"
```

---

### Task 27: Final analyze + full test sweep

- [ ] Run: `cd client && flutter analyze`
- [ ] Run: `cd client && flutter test --exclude-tags integration`
- [ ] Run: `cd client && flutter test --tags integration` (on Linux; Windows/macOS where PTY/symlink test infra allows)
- [ ] If `pluginsTitle` or any other key is missing in `app_localizations*.dart`, regenerate with `flutter gen-l10n`
- [ ] All three commands must exit 0. Fix root causes; do not skip tests, do not bypass hooks.

---

## Self-Review Summary

**Spec coverage check** (mapping spec §s to tasks):

| Spec § | Task |
|--------|------|
| §2 Architecture | Implemented across Tasks 1–22 |
| §3.1 Plugin model | Task 1 |
| §3.2 PluginCapabilities | Task 1 |
| §3.3 TeamConfig.pluginIds | Task 4 |
| §3.4 PluginMarketplace | Task 2 |
| §3.5 DiscoverablePlugin / UpdateInfo / Backup / Unmanaged | Tasks 2, 3 |
| §3.6 plugins.json + plugin-marketplaces.json | Tasks 5, 8, 11 |
| §4.1 PluginManifestService | Task 7 |
| §4.2 PluginInstallService | Task 11 |
| §4.3 TeamPluginLinkerService | Task 19 |
| §4.4 PluginCubit | Task 13 |
| §5.1 Routes | Task 15 |
| §5.2 Installed section | Task 16 |
| §5.3 Discovery section | Task 16 |
| §5.4 Marketplaces section | Task 16 |
| §5.5 Team config plugin section | Task 21 |
| §5.6 i18n | Tasks 14, 21 |
| §6 Edge cases — missing source | Task 21 (banner) + Task 19 (linker reports) |
| §6 Edge cases — uninstall impact | Task 24 |
| §6 Edge cases — CLI unsupported | Task 21 (banner) |
| §6 Edge cases — id conflict | Task 25 |
| §6 Edge cases — marketplace removal | Implicit in Task 8 (does not cascade) |
| §7 Errors | Task 6 (exceptions); cubit emits errorMessage throughout |
| §8 Tests | Tests in every task; integration in Task 26 |
| §9 Phase split | Phases 1/2/3/4 above |
