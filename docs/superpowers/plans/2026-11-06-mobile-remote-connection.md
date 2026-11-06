# 移动端远程连接与 SSH 服务器拆分 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「远程连接」（本地 bootstrap + 连接生命周期）与「SSH 服务器」（远端完整配置）拆成两个功能，配置随 home plane 存远端并支持多设备共享。

**Architecture:** 存储层拆成 `RemoteTarget`（设备本地）与 `SshServerProfile`（远端 home）；运行时保留 `SshProfile` 作为两者的聚合视图，避免改动 120+ 个既有调用点。页面层拆成 `RemoteConnectionsPage`（连接）与 `SshServersPage`（配置）。同步采用「本地先行、远端权威、`updatedAt` 收敛」。

**Tech Stack:** Flutter / Dart、flutter_bloc、dartssh2、现有 `Filesystem` / `HomeStorage` 抽象、`dart run tool/run_tests.dart`。

## Global Constraints

- 禁止直接运行 `flutter test`；统一用 `cd client && dart run tool/run_tests.dart <path>`。
- 提交前跑 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`。
- 路径必须走注入的 `HomeStorage` / `RuntimeContext`，禁止 `Directory.current`。
- 用户可见文案只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`。
- 诊断日志用 `AppLogger`，禁止 `print`。
- 凭据永不写入远端 profile，也不进入日志。
- 每个任务结束前单独 commit，提交信息用 `feat:` / `test:` / `refactor:` 前缀。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `client/lib/models/ssh_auth_type.dart` | 从 `ssh_profile.dart` 抽出的认证方式枚举，避免循环依赖 |
| `client/lib/models/remote_target.dart` | 本地 bootstrap：连接字段 + 本机状态 |
| `client/lib/models/ssh_server_profile.dart` | 远端完整配置（不含凭据） |
| `client/lib/models/ssh_profile.dart` | 保留为运行时视图，新增 `fromTarget` |
| `client/lib/repositories/remote_target_repository.dart` | 读写 `<nativeAppData>/remote-targets.json` |
| `client/lib/repositories/ssh_server_profile_repository.dart` | 读写 `<home>/ssh_profiles/profiles.json` |
| `client/lib/repositories/ssh_profile_repository.dart` | 改为门面：聚合 target + server profile |
| `client/lib/services/storage/remote_target_migration.dart` | 旧 `profiles.json` 一次性拆分迁移 |
| `client/lib/services/ssh/remote_target_sync.dart` | 连上后 push / pull |
| `client/lib/services/storage/device_local_control_plane.dart` | 新增 `deviceLocalRemoteTargetRepository` |
| `client/lib/cubits/ssh_server_config_cubit.dart` | 远端 profile 的加载与编辑 |
| `client/lib/pages/remote_connections_page.dart` | 远程连接页 |
| `client/lib/pages/ssh_profiles_page.dart` | 改造为 SSH 服务器页 |
| `client/lib/pages/vault/vault_page.dart` | 去掉新建业务凭据入口 |
| `client/lib/pages/startup_gate.dart` | 未绑定 work home 时跳远程连接页 |

---

### Task 1: 抽出 `SshAuthType` 并新增 `RemoteTarget`

**Files:**
- Create: `client/lib/models/ssh_auth_type.dart`
- Modify: `client/lib/models/ssh_profile.dart:5`
- Create: `client/lib/models/remote_target.dart`
- Test: `client/test/models/remote_target_test.dart`

**Interfaces:**
- Produces: `enum SshAuthType { password, privateKey }`
- Produces: `class RemoteTarget`，字段 `id, name, host, port, username, authType, vaultEntryId, endpoints, hostKeyFingerprints, lastGoodKind, lastHome, lastAppDataRoot, embeddedTarget, relayUrl, pairedDesktopId, updatedAt, pendingSync`
- Produces: `RemoteTarget.fromJson(Map<String, Object?>)`、`toJson()`、`copyWith(...)`、`hostIdentifier`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/models/remote_target_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/models/ssh_auth_type.dart';

void main() {
  test('round-trips all fields', () {
    const target = RemoteTarget(
      id: 't1',
      name: 'dev-box',
      host: '10.0.0.5',
      port: 2222,
      username: 'alice',
      authType: SshAuthType.privateKey,
      vaultEntryId: 'v1',
      lastHome: '/home/alice',
      lastAppDataRoot: '/home/alice/.teampilot',
      embeddedTarget: true,
      relayUrl: 'wss://relay',
      pairedDesktopId: 'd1',
      updatedAt: 42,
      pendingSync: true,
    );
    final restored = RemoteTarget.fromJson(target.toJson());
    expect(restored, target);
    expect(restored.hostIdentifier, 'alice@10.0.0.5:2222');
  });

  test('defaults port and auth type', () {
    final target = RemoteTarget.fromJson({'id': 't1', 'host': 'h'});
    expect(target.port, 22);
    expect(target.authType, SshAuthType.password);
    expect(target.pendingSync, isFalse);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/remote_target_test.dart`
Expected: FAIL，`Target of URI doesn't exist: 'package:teampilot/models/remote_target.dart'`

- [ ] **Step 3: 抽出枚举**

```dart
// client/lib/models/ssh_auth_type.dart
enum SshAuthType { password, privateKey }
```

把 `ssh_profile.dart` 第 5 行的 `enum SshAuthType ...` 删掉，并在文件顶部加：

```dart
import 'ssh_auth_type.dart';
export 'ssh_auth_type.dart';
```

（`export` 保证现有 `import 'models/ssh_profile.dart'` 的调用点仍能拿到 `SshAuthType`。）

- [ ] **Step 4: 实现 `RemoteTarget`**

```dart
// client/lib/models/remote_target.dart
import 'package:flutter/foundation.dart';

import 'ssh_auth_type.dart';
import 'ssh_reachability.dart';

@immutable
class RemoteTarget {
  const RemoteTarget({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = SshAuthType.password,
    this.vaultEntryId,
    this.endpoints = const [],
    this.hostKeyFingerprints = const [],
    this.lastGoodKind,
    this.lastHome,
    this.lastAppDataRoot,
    this.embeddedTarget = false,
    this.relayUrl,
    this.pairedDesktopId,
    this.updatedAt = 0,
    this.pendingSync = false,
  });

  factory RemoteTarget.fromJson(Map<String, Object?> json) {
    final authRaw = json['authType'] as String? ?? 'password';
    return RemoteTarget(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String? ?? '',
      authType: SshAuthType.values.firstWhere(
        (e) => e.name == authRaw,
        orElse: () => SshAuthType.password,
      ),
      vaultEntryId: json['vaultEntryId']?.toString(),
      endpoints: (json['endpoints'] as List?)
              ?.whereType<Map>()
              .map((v) => SshReachabilityEndpoint.tryParse(v.cast<String, Object?>()))
              .whereType<SshReachabilityEndpoint>()
              .toList(growable: false) ??
          const [],
      hostKeyFingerprints:
          (json['hostKeyFingerprints'] as List?)?.whereType<String>().toList(
                growable: false,
              ) ??
              const [],
      lastGoodKind: SshEndpointKind.values
          .where((v) => v.name == json['lastGoodKind'])
          .firstOrNull,
      lastHome: json['lastHome'] as String?,
      lastAppDataRoot: json['lastAppDataRoot'] as String?,
      embeddedTarget: json['embeddedTarget'] is bool
          ? json['embeddedTarget'] as bool
          : false,
      relayUrl: json['relayUrl'] as String?,
      pairedDesktopId: json['pairedDesktopId'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      pendingSync: json['pendingSync'] is bool
          ? json['pendingSync'] as bool
          : false,
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final SshAuthType authType;
  final String? vaultEntryId;
  final List<SshReachabilityEndpoint> endpoints;
  final List<String> hostKeyFingerprints;
  final SshEndpointKind? lastGoodKind;
  final String? lastHome;
  final String? lastAppDataRoot;
  final bool embeddedTarget;
  final String? relayUrl;
  final String? pairedDesktopId;
  final int updatedAt;
  final bool pendingSync;

  String get hostIdentifier => '$username@$host:$port';

  RemoteTarget copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    SshAuthType? authType,
    String? vaultEntryId,
    List<SshReachabilityEndpoint>? endpoints,
    List<String>? hostKeyFingerprints,
    SshEndpointKind? lastGoodKind,
    String? lastHome,
    String? lastAppDataRoot,
    bool? embeddedTarget,
    String? relayUrl,
    String? pairedDesktopId,
    int? updatedAt,
    bool? pendingSync,
  }) {
    return RemoteTarget(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      vaultEntryId: vaultEntryId ?? this.vaultEntryId,
      endpoints: endpoints ?? this.endpoints,
      hostKeyFingerprints: hostKeyFingerprints ?? this.hostKeyFingerprints,
      lastGoodKind: lastGoodKind ?? this.lastGoodKind,
      lastHome: lastHome ?? this.lastHome,
      lastAppDataRoot: lastAppDataRoot ?? this.lastAppDataRoot,
      embeddedTarget: embeddedTarget ?? this.embeddedTarget,
      relayUrl: relayUrl ?? this.relayUrl,
      pairedDesktopId: pairedDesktopId ?? this.pairedDesktopId,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authType': authType.name,
        if (vaultEntryId != null) 'vaultEntryId': vaultEntryId,
        if (endpoints.isNotEmpty)
          'endpoints': endpoints.map((e) => e.toJson()).toList(),
        if (hostKeyFingerprints.isNotEmpty)
          'hostKeyFingerprints': hostKeyFingerprints,
        if (lastGoodKind != null) 'lastGoodKind': lastGoodKind!.name,
        if (lastHome != null) 'lastHome': lastHome,
        if (lastAppDataRoot != null) 'lastAppDataRoot': lastAppDataRoot,
        if (embeddedTarget) 'embeddedTarget': embeddedTarget,
        if (relayUrl != null) 'relayUrl': relayUrl,
        if (pairedDesktopId != null) 'pairedDesktopId': pairedDesktopId,
        'updatedAt': updatedAt,
        'pendingSync': pendingSync,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RemoteTarget &&
          id == other.id &&
          name == other.name &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          authType == other.authType &&
          vaultEntryId == other.vaultEntryId &&
          listEquals(endpoints, other.endpoints) &&
          listEquals(hostKeyFingerprints, other.hostKeyFingerprints) &&
          lastGoodKind == other.lastGoodKind &&
          lastHome == other.lastHome &&
          lastAppDataRoot == other.lastAppDataRoot &&
          embeddedTarget == other.embeddedTarget &&
          relayUrl == other.relayUrl &&
          pairedDesktopId == other.pairedDesktopId &&
          updatedAt == other.updatedAt &&
          pendingSync == other.pendingSync;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        host,
        port,
        username,
        authType,
        vaultEntryId,
        Object.hashAll(endpoints),
        Object.hashAll(hostKeyFingerprints),
        lastGoodKind,
        lastHome,
        lastAppDataRoot,
        embeddedTarget,
        relayUrl,
        pairedDesktopId,
        updatedAt,
        pendingSync,
      );
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/models/remote_target_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/ssh_auth_type.dart client/lib/models/ssh_profile.dart client/lib/models/remote_target.dart client/test/models/remote_target_test.dart
git commit -m "feat(models): add RemoteTarget and extract SshAuthType"
```

---

### Task 2: `RemoteTargetRepository`

**Files:**
- Create: `client/lib/repositories/remote_target_repository.dart`
- Test: `client/test/repositories/remote_target_repository_test.dart`

**Interfaces:**
- Consumes: `RemoteTarget`（Task 1）、`Filesystem`、`isStorageTransportFailure`
- Produces: `RemoteTargetRepository({required String rootDir, required Filesystem fs})`
- Produces: `loadAll()`、`saveAll(List<RemoteTarget>)`、`save(RemoteTarget)`、`delete(String)`、`findById(String)`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/repositories/remote_target_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late RemoteTargetRepository repo;

  setUp(() {
    repo = RemoteTargetRepository(
      rootDir: '/tp',
      fs: InMemoryFilesystem(),
    );
  });

  test('saves and loads a target', () async {
    const target = RemoteTarget(id: 't1', name: 'dev', host: 'h', username: 'u');
    await repo.save(target);
    final loaded = await repo.loadAll();
    expect(loaded, [target]);
  });

  test('updates existing target by id', () async {
    await repo.save(const RemoteTarget(id: 't1', name: 'a', host: 'h', username: 'u'));
    await repo.save(const RemoteTarget(id: 't1', name: 'b', host: 'h', username: 'u'));
    final loaded = await repo.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'b');
  });

  test('deletes target', () async {
    await repo.save(const RemoteTarget(id: 't1', name: 'a', host: 'h', username: 'u'));
    await repo.delete('t1');
    expect(await repo.loadAll(), isEmpty);
  });

  test('returns empty when file is missing', () async {
    expect(await repo.loadAll(), isEmpty);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/repositories/remote_target_repository_test.dart`
Expected: FAIL，找不到 `remote_target_repository.dart`

- [ ] **Step 3: 实现仓库**

```dart
// client/lib/repositories/remote_target_repository.dart
import 'dart:convert';

import '../models/remote_target.dart';
import '../services/io/filesystem.dart';
import '../services/storage/storage_failure.dart';

class RemoteTargetRepository {
  RemoteTargetRepository({required this.rootDir, required this.fs});

  final String rootDir;
  final Filesystem fs;

  String get _file => fs.pathContext.join(rootDir, 'remote-targets.json');

  Future<List<RemoteTarget>> loadAll() async {
    if (!(await fs.stat(_file)).isFile) return [];
    try {
      final raw = await fs.readString(_file);
      if (raw == null || raw.isEmpty) return [];
      final json = jsonDecode(raw);
      if (json is List) {
        return json
            .whereType<Map<String, Object?>>()
            .map(RemoteTarget.fromJson)
            .toList();
      }
    } on Object catch (error) {
      if (isStorageTransportFailure(error)) rethrow;
    }
    return [];
  }

  Future<void> saveAll(List<RemoteTarget> targets) async {
    await fs.ensureDir(rootDir);
    await fs.atomicWrite(
      _file,
      jsonEncode(targets.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> save(RemoteTarget target) async {
    final all = await loadAll();
    final idx = all.indexWhere((t) => t.id == target.id);
    if (idx >= 0) {
      all[idx] = target;
    } else {
      all.add(target);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((t) => t.id == id);
    await saveAll(all);
  }

  Future<RemoteTarget?> findById(String id) async {
    final all = await loadAll();
    for (final target in all) {
      if (target.id == id) return target;
    }
    return null;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/repositories/remote_target_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/remote_target_repository.dart client/test/repositories/remote_target_repository_test.dart
git commit -m "feat(repo): add device-local RemoteTargetRepository"
```

---

### Task 3: `SshServerProfile` 模型与仓库

**Files:**
- Create: `client/lib/models/ssh_server_profile.dart`
- Create: `client/lib/repositories/ssh_server_profile_repository.dart`
- Test: `client/test/models/ssh_server_profile_test.dart`
- Test: `client/test/repositories/ssh_server_profile_repository_test.dart`

**Interfaces:**
- Consumes: `SshAuthType`（Task 1）
- Produces: `SshServerProfile`，字段 `id, name, host, port, username, authType, embeddedTarget, relayUrl, pairedDesktopId, updatedAt`
- Produces: `SshServerProfileRepository({required HomeStorage storage})`，方法同上

- [ ] **Step 1: 写模型测试**

```dart
// client/test/models/ssh_server_profile_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_auth_type.dart';
import 'package:teampilot/models/ssh_server_profile.dart';

void main() {
  test('round-trips without credentials', () {
    const profile = SshServerProfile(
      id: 't1',
      name: 'dev',
      host: '10.0.0.5',
      port: 22,
      username: 'alice',
      authType: SshAuthType.privateKey,
      embeddedTarget: true,
      updatedAt: 7,
    );
    final json = profile.toJson();
    expect(json.containsKey('password'), isFalse);
    expect(json.containsKey('privateKey'), isFalse);
    expect(SshServerProfile.fromJson(json), profile);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/ssh_server_profile_test.dart`
Expected: FAIL，找不到文件

- [ ] **Step 3: 实现模型**

```dart
// client/lib/models/ssh_server_profile.dart
import 'package:flutter/foundation.dart';

import 'ssh_auth_type.dart';

@immutable
class SshServerProfile {
  const SshServerProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authType = SshAuthType.password,
    this.embeddedTarget = false,
    this.relayUrl,
    this.pairedDesktopId,
    this.updatedAt = 0,
  });

  factory SshServerProfile.fromJson(Map<String, Object?> json) {
    final authRaw = json['authType'] as String? ?? 'password';
    return SshServerProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: json['username'] as String? ?? '',
      authType: SshAuthType.values.firstWhere(
        (e) => e.name == authRaw,
        orElse: () => SshAuthType.password,
      ),
      embeddedTarget: json['embeddedTarget'] is bool
          ? json['embeddedTarget'] as bool
          : false,
      relayUrl: json['relayUrl'] as String?,
      pairedDesktopId: json['pairedDesktopId'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final SshAuthType authType;
  final bool embeddedTarget;
  final String? relayUrl;
  final String? pairedDesktopId;
  final int updatedAt;

  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authType': authType.name,
        if (embeddedTarget) 'embeddedTarget': embeddedTarget,
        if (relayUrl != null) 'relayUrl': relayUrl,
        if (pairedDesktopId != null) 'pairedDesktopId': pairedDesktopId,
        'updatedAt': updatedAt,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshServerProfile &&
          id == other.id &&
          name == other.name &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          authType == other.authType &&
          embeddedTarget == other.embeddedTarget &&
          relayUrl == other.relayUrl &&
          pairedDesktopId == other.pairedDesktopId &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        host,
        port,
        username,
        authType,
        embeddedTarget,
        relayUrl,
        pairedDesktopId,
        updatedAt,
      );
}
```

- [ ] **Step 4: 写仓库测试**

```dart
// client/test/repositories/ssh_server_profile_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_server_profile.dart';
import 'package:teampilot/repositories/ssh_server_profile_repository.dart';
import 'package:teampilot/services/storage/home_storage.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUpTestAppStorage();
  tearDownTestAppStorage();

  test('saves and loads on the home plane', () async {
    final repo = SshServerProfileRepository(storage: testHomeStorage);
    const profile = SshServerProfile(
      id: 't1',
      name: 'dev',
      host: 'h',
      username: 'u',
    );
    await repo.save(profile);
    expect(await repo.loadAll(), [profile]);
  });

  test('writes under ssh_profiles/profiles.json', () async {
    final repo = SshServerProfileRepository(storage: testHomeStorage);
    await repo.save(
      const SshServerProfile(id: 't1', name: 'dev', host: 'h', username: 'u'),
    );
    final path = testHomeStorage.fs.pathContext.join(
      testHomeStorage.paths.sshProfilesDir,
      'profiles.json',
    );
    expect((await testHomeStorage.fs.stat(path)).isFile, isTrue);
  });
}
```

- [ ] **Step 5: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/repositories/ssh_server_profile_repository_test.dart`
Expected: FAIL，找不到仓库文件

- [ ] **Step 6: 实现仓库**

```dart
// client/lib/repositories/ssh_server_profile_repository.dart
import 'dart:convert';

import '../models/ssh_server_profile.dart';
import '../services/io/filesystem.dart';
import '../services/storage/home_storage.dart';
import '../services/storage/storage_failure.dart';

class SshServerProfileRepository {
  SshServerProfileRepository({required HomeStorage storage}) : _storage = storage;

  final HomeStorage _storage;

  Filesystem get _fs => _storage.fs;

  String get _root => _storage.paths.sshProfilesDir;

  String get _file => _fs.pathContext.join(_root, 'profiles.json');

  Future<List<SshServerProfile>> loadAll() async {
    if (!(await _fs.stat(_file)).isFile) return [];
    try {
      final raw = await _fs.readString(_file);
      if (raw == null || raw.isEmpty) return [];
      final json = jsonDecode(raw);
      if (json is List) {
        return json
            .whereType<Map<String, Object?>>()
            .map(SshServerProfile.fromJson)
            .toList();
      }
    } on Object catch (error) {
      if (isStorageTransportFailure(error)) rethrow;
    }
    return [];
  }

  Future<void> saveAll(List<SshServerProfile> profiles) async {
    await _fs.ensureDir(_root);
    await _fs.atomicWrite(
      _file,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> save(SshServerProfile profile) async {
    final all = await loadAll();
    final idx = all.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      all[idx] = profile;
    } else {
      all.add(profile);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((p) => p.id == id);
    await saveAll(all);
  }

  Future<SshServerProfile?> findById(String id) async {
    for (final profile in await loadAll()) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}
```

- [ ] **Step 7: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/models/ssh_server_profile_test.dart test/repositories/ssh_server_profile_repository_test.dart`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add client/lib/models/ssh_server_profile.dart client/lib/repositories/ssh_server_profile_repository.dart client/test/models/ssh_server_profile_test.dart client/test/repositories/ssh_server_profile_repository_test.dart
git commit -m "feat(repo): add remote SshServerProfile and repository"
```

---

### Task 4: 旧 `profiles.json` 一次性迁移

**Files:**
- Create: `client/lib/services/storage/remote_target_migration.dart`
- Test: `client/test/services/storage/remote_target_migration_test.dart`

**Interfaces:**
- Consumes: `RemoteTarget`、`SshServerProfile`、`SshProfileRepository`、`RemoteTargetRepository`
- Produces: `Future<RemoteTargetMigrationResult> migrateSshProfiles({required String nativeAppDataPath, required Filesystem localFs, required SshProfileRepository legacyRepo, required RemoteTargetRepository targetRepo})`
- Produces: `RemoteTargetMigrationResult({required int migrated, required bool skipped})`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/storage/remote_target_migration_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';
import 'package:teampilot/services/storage/remote_target_migration.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('migrates legacy profiles into remote targets once', () async {
    final fs = InMemoryFilesystem();
    const root = '/tp';
    final legacyFile =
        fs.pathContext.join(root, 'ssh_profiles', 'profiles.json');
    await fs.ensureDir(fs.pathContext.dirname(legacyFile));
    await fs.atomicWrite(
      legacyFile,
      jsonEncode([
        const SshProfile(
          id: 'p1',
          name: 'dev',
          host: 'h',
          username: 'u',
        ).toJson(),
      ]),
    );
    final targetRepo = RemoteTargetRepository(rootDir: root, fs: fs);

    final first = await migrateSshProfiles(
      nativeAppDataPath: root,
      localFs: fs,
      targetRepo: targetRepo,
    );
    expect(first.migrated, 1);
    expect(first.skipped, isFalse);
    expect((await targetRepo.loadAll()).single.id, 'p1');

    final second = await migrateSshProfiles(
      nativeAppDataPath: root,
      localFs: fs,
      targetRepo: targetRepo,
    );
    expect(second.migrated, 0);
    expect(second.skipped, isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/remote_target_migration_test.dart`
Expected: FAIL，找不到 `remote_target_migration.dart`

- [ ] **Step 3: 实现迁移**

```dart
// client/lib/services/storage/remote_target_migration.dart
import 'dart:convert';

import '../../models/remote_target.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/remote_target_repository.dart';
import '../io/filesystem.dart';

class RemoteTargetMigrationResult {
  const RemoteTargetMigrationResult({
    required this.migrated,
    required this.skipped,
  });

  final int migrated;
  final bool skipped;
}

Future<RemoteTargetMigrationResult> migrateSshProfiles({
  required String nativeAppDataPath,
  required Filesystem localFs,
  required RemoteTargetRepository targetRepo,
}) async {
  final marker = localFs.pathContext.join(
    nativeAppDataPath,
    '.remote-targets-migrated.v1',
  );
  if ((await localFs.stat(marker)).exists) {
    return const RemoteTargetMigrationResult(migrated: 0, skipped: true);
  }

  final legacyFile = localFs.pathContext.join(
    nativeAppDataPath,
    'ssh_profiles',
    'profiles.json',
  );
  final legacy = <SshProfile>[];
  if ((await localFs.stat(legacyFile)).isFile) {
    try {
      final raw = await localFs.readString(legacyFile);
      final json = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      if (json is List) {
        legacy.addAll(
          json.whereType<Map<String, Object?>>().map(SshProfile.fromJson),
        );
      }
    } on Object {
      // 解析失败：保留原文件，不写标记，下次启动重试。
      return const RemoteTargetMigrationResult(migrated: 0, skipped: false);
    }
  }

  final existing = {for (final t in await targetRepo.loadAll()) t.id};
  final migrated = <RemoteTarget>[
    for (final profile in legacy)
      if (!existing.contains(profile.id)) _toTarget(profile),
  ];
  if (migrated.isNotEmpty) {
    await targetRepo.saveAll([...await targetRepo.loadAll(), ...migrated]);
  }
  await localFs.atomicWrite(marker, '1');
  return RemoteTargetMigrationResult(
    migrated: migrated.length,
    skipped: false,
  );
}

RemoteTarget _toTarget(SshProfile profile) => RemoteTarget(
      id: profile.id,
      name: profile.name,
      host: profile.host,
      port: profile.port,
      username: profile.username,
      authType: profile.authType,
      vaultEntryId: profile.vaultEntryId,
      endpoints: profile.endpoints,
      hostKeyFingerprints: profile.hostKeyFingerprints,
      lastGoodKind: profile.lastGoodKind,
      lastHome: profile.lastHome,
      lastAppDataRoot: profile.lastAppDataRoot,
      embeddedTarget: profile.embeddedTarget,
      relayUrl: profile.relayUrl,
      pairedDesktopId: profile.pairedDesktopId,
      updatedAt: profile.updatedAt,
    );
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/remote_target_migration_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/remote_target_migration.dart client/test/services/storage/remote_target_migration_test.dart
git commit -m "feat(storage): migrate legacy ssh profiles into RemoteTarget"
```

---

### Task 5: `SshProfile` 聚合视图 + `SshProfileRepository` 门面

**Files:**
- Modify: `client/lib/models/ssh_profile.dart`
- Modify: `client/lib/repositories/ssh_profile_repository.dart`
- Test: `client/test/repositories/ssh_profile_repository_test.dart`（新增用例）

**Interfaces:**
- Consumes: `RemoteTarget`、`RemoteTargetRepository`
- Produces: `SshProfile.fromTarget(RemoteTarget target)`
- Produces: `SshProfileRepository({required RemoteTargetRepository targetRepo, String? rootDir, Filesystem? fs, required HomeStorage storage})`
- 保留现有 `loadAll/saveAll/save/delete/findById/loadSelectedProfileId/saveSelectedProfileId`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/repositories/ssh_profile_repository_test.dart（追加）
test('projects a RemoteTarget into a runtime SshProfile', () {
  const target = RemoteTarget(
    id: 't1',
    name: 'dev',
    host: 'h',
    port: 22,
    username: 'u',
    embeddedTarget: true,
    updatedAt: 10,
  );
  final profile = SshProfile.fromTarget(target);
  expect(profile.id, 't1');
  expect(profile.name, 'dev');
  expect(profile.embeddedTarget, isTrue);
  expect(profile.updatedAt, 10);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/repositories/ssh_profile_repository_test.dart`
Expected: FAIL，`fromTarget` 未定义

- [ ] **Step 3: 实现 `fromTarget`**

在 `SshProfile` 中新增：

```dart
factory SshProfile.fromTarget(RemoteTarget target) {
  return SshProfile(
    id: target.id,
    name: target.name,
    host: target.host,
    port: target.port,
    username: target.username,
    authType: target.authType,
    createdAt: target.updatedAt,
    updatedAt: target.updatedAt,
    lastHome: target.lastHome,
    lastAppDataRoot: target.lastAppDataRoot,
    endpoints: target.endpoints,
    hostKeyFingerprints: target.hostKeyFingerprints,
    pairedDesktopId: target.pairedDesktopId,
    relayUrl: target.relayUrl,
    lastGoodKind: target.lastGoodKind,
    embeddedTarget: target.embeddedTarget,
    vaultEntryId: target.vaultEntryId,
  );
}
```

顶部补 import：

```dart
import 'remote_target.dart';
```

- [ ] **Step 4: 改造仓库为本地投影**

```dart
class SshProfileRepository {
  SshProfileRepository({
    required this.targetRepo,
    String? rootDir,
    Filesystem? fs,
    required HomeStorage storage,
  }) : _rootDirOverride = rootDir,
       _fsOverride = fs,
       _storage = storage;

  final RemoteTargetRepository targetRepo;
  final String? _rootDirOverride;
  final Filesystem? _fsOverride;
  final HomeStorage _storage;

  String get _root => _rootDirOverride ?? _storage.paths.sshProfilesDir;
  Filesystem get _fs => _fsOverride ?? _storage.fs;
  String get _selectedProfileFile =>
      _fs.pathContext.join(_root, 'selected_profile.txt');

  Future<List<SshProfile>> loadAll() async {
    final targets = await targetRepo.loadAll();
    return targets.map(SshProfile.fromTarget).toList();
  }

  Future<void> save(SshProfile profile) async {
    final existing = await targetRepo.findById(profile.id);
    final target = (existing ??
            RemoteTarget(
              id: profile.id,
              name: profile.name,
              host: profile.host,
              port: profile.port,
              username: profile.username,
            ))
        .copyWith(
      name: profile.name,
      host: profile.host,
      port: profile.port,
      username: profile.username,
      authType: profile.authType,
      vaultEntryId: profile.vaultEntryId,
      endpoints: profile.endpoints,
      hostKeyFingerprints: profile.hostKeyFingerprints,
      lastGoodKind: profile.lastGoodKind,
      lastHome: profile.lastHome,
      lastAppDataRoot: profile.lastAppDataRoot,
      embeddedTarget: profile.embeddedTarget,
      relayUrl: profile.relayUrl,
      pairedDesktopId: profile.pairedDesktopId,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      pendingSync: true,
    );
    await targetRepo.save(target);
  }

  Future<void> saveAll(List<SshProfile> profiles) async {
    for (final profile in profiles) {
      await save(profile);
    }
  }

  Future<void> delete(String id) => targetRepo.delete(id);

  Future<SshProfile?> findById(String id) async {
    final target = await targetRepo.findById(id);
    return target == null ? null : SshProfile.fromTarget(target);
  }

  // loadSelectedProfileId / saveSelectedProfileId 保持原实现
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/repositories/ssh_profile_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/ssh_profile.dart client/lib/repositories/ssh_profile_repository.dart client/test/repositories/ssh_profile_repository_test.dart
git commit -m "refactor(repo): make SshProfileRepository a target+server facade"
```

---

### Task 6: 同步服务 `RemoteTargetSync`

**Files:**
- Create: `client/lib/services/ssh/remote_target_sync.dart`
- Test: `client/test/services/ssh/remote_target_sync_test.dart`

**Interfaces:**
- Consumes: `RemoteTarget`、`SshServerProfile`、`RemoteTargetRepository`、`SshServerProfileRepository`
- Produces: `RemoteTargetSync({required RemoteTargetRepository targets, required SshServerProfileRepository servers})`
- Produces: `Future<void> push(RemoteTarget)`、`Future<RemoteTarget> pull(RemoteTarget)`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/ssh/remote_target_sync_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/models/ssh_server_profile.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';
import 'package:teampilot/repositories/ssh_server_profile_repository.dart';
import 'package:teampilot/services/ssh/remote_target_sync.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late RemoteTargetRepository targetRepo;
  late SshServerProfileRepository serverRepo;
  late RemoteTargetSync sync;

  setUp(() {
    final fs = InMemoryFilesystem();
    targetRepo = RemoteTargetRepository(rootDir: '/tp', fs: fs);
    serverRepo = SshServerProfileRepository(
      storage: fakeHomeStorage(filesystem: fs),
    );
    sync = RemoteTargetSync(targets: targetRepo, servers: serverRepo);
  });

  test('push writes server profile and clears pendingSync', () async {
    await targetRepo.save(const RemoteTarget(
      id: 't1',
      name: 'dev',
      host: 'h',
      username: 'u',
      pendingSync: true,
    ));
    await sync.push((await targetRepo.findById('t1'))!);
    expect((await serverRepo.findById('t1'))!.name, 'dev');
    expect((await targetRepo.findById('t1'))!.pendingSync, isFalse);
  });

  test('pull overwrites local connection fields when remote is newer', () async {
    await targetRepo.save(const RemoteTarget(
      id: 't1',
      name: 'old',
      host: 'h',
      username: 'u',
      updatedAt: 10,
    ));
    await serverRepo.save(const SshServerProfile(
      id: 't1',
      name: 'new',
      host: 'h2',
      username: 'u',
      updatedAt: 20,
    ));
    final merged = await sync.pull((await targetRepo.findById('t1'))!);
    expect(merged.name, 'new');
    expect(merged.host, 'h2');
    expect(merged.vaultEntryId, isNull); // 凭据不动
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/remote_target_sync_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现同步**

```dart
// client/lib/services/ssh/remote_target_sync.dart
import '../../models/remote_target.dart';
import '../../models/ssh_server_profile.dart';
import '../../repositories/remote_target_repository.dart';
import '../../repositories/ssh_server_profile_repository.dart';
import '../../utils/logging/logger.dart';

class RemoteTargetSync {
  const RemoteTargetSync({required this.targets, required this.servers});

  final RemoteTargetRepository targets;
  final SshServerProfileRepository servers;

  Future<void> push(RemoteTarget target) async {
    await servers.save(SshServerProfile(
      id: target.id,
      name: target.name,
      host: target.host,
      port: target.port,
      username: target.username,
      authType: target.authType,
      embeddedTarget: target.embeddedTarget,
      relayUrl: target.relayUrl,
      pairedDesktopId: target.pairedDesktopId,
      updatedAt: target.updatedAt,
    ));
    await targets.save(target.copyWith(pendingSync: false));
  }

  Future<RemoteTarget> pull(RemoteTarget target) async {
    final server = await servers.findById(target.id);
    if (server == null) return target;
    if (server.updatedAt <= target.updatedAt) return target;
    final merged = target.copyWith(
      name: server.name,
      host: server.host,
      port: server.port,
      username: server.username,
      authType: server.authType,
      embeddedTarget: server.embeddedTarget,
      relayUrl: server.relayUrl,
      pairedDesktopId: server.pairedDesktopId,
      updatedAt: server.updatedAt,
    );
    await targets.save(merged);
    appLogger.d('[remote-target-sync] pulled ${target.id}');
    return merged;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/remote_target_sync_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ssh/remote_target_sync.dart client/test/services/ssh/remote_target_sync_test.dart
git commit -m "feat(ssh): add RemoteTargetSync push/pull"
```

---

### Task 7: 接线 `deviceLocalControlPlane` 与启动迁移

**Files:**
- Modify: `client/lib/services/storage/device_local_control_plane.dart:21-40`
- Modify: `client/lib/app/app_shell.dart:911`
- Test: `client/test/services/storage/device_local_control_plane_test.dart`（新增用例）

**Interfaces:**
- Produces: `RemoteTargetRepository deviceLocalRemoteTargetRepository(String nativeAppDataPath)`
- `deviceLocalSshProfileRepository` 改为返回基于 `targetRepo` 的视图仓库

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/storage/device_local_control_plane_test.dart（追加）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/services/storage/device_local_control_plane.dart';

void main() {
  test('remote target repo is pinned to native app data', () async {
    final root = Directory.systemTemp.createTempSync('remote_target_pin_');
    addTearDown(() => root.deleteSync(recursive: true));
    final repo = deviceLocalRemoteTargetRepository(root.path);
    await repo.save(
      const RemoteTarget(id: 't1', name: 'dev', host: 'h', username: 'u'),
    );
    expect(File('${root.path}/remote-targets.json').existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/device_local_control_plane_test.dart`
Expected: FAIL，函数未定义

- [ ] **Step 3: 实现工厂**

```dart
RemoteTargetRepository deviceLocalRemoteTargetRepository(String nativeAppDataPath) {
  final fs = LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  );
  return RemoteTargetRepository(
    rootDir: nativeAppDataPath,
    fs: fs,
  );
}
```

把 `deviceLocalSshProfileRepository` 改为：

```dart
SshProfileRepository deviceLocalSshProfileRepository(String nativeAppDataPath) {
  final paths = AppPaths(nativeAppDataPath);
  final fs = LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  );
  return SshProfileRepository(
    targetRepo: RemoteTargetRepository(rootDir: nativeAppDataPath, fs: fs),
    rootDir: paths.sshProfilesDir,
    fs: fs,
    storage: HomeStorage(
      RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: nativeAppDataPath,
        cwd: nativeAppDataPath,
        appDataRoot: nativeAppDataPath,
        paths: paths,
      ),
    ),
  );
}
```

- [ ] **Step 4: 在 app_shell 启动时执行迁移**

在 `app_shell.dart` 创建 `sshProfileRepo` 后、`SshProfileCubit` 前插入：

```dart
await migrateSshProfiles(
  nativeAppDataPath: nativeAppDataPath,
  localFs: LocalFilesystem(
    pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
  ),
  targetRepo: deviceLocalRemoteTargetRepository(nativeAppDataPath),
);
```

该函数必须是 `async`，且迁移要在 `SshProfileCubit` 第一次 `load()` 之前完成；若当前不是 `async`，改为 `async` 并让调用方 `await`。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/device_local_control_plane_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/storage/device_local_control_plane.dart client/lib/app/app_shell.dart client/test/services/storage/device_local_control_plane_test.dart
git commit -m "feat(storage): pin RemoteTarget repo and run legacy migration at boot"
```

---

### Task 8: `SshServerConfigCubit`

**Files:**
- Create: `client/lib/cubits/ssh_server_config_cubit.dart`
- Test: `client/test/cubits/ssh_server_config_cubit_test.dart`

**Interfaces:**
- Consumes: `SshServerProfileRepository`
- Produces: `SshServerConfigCubit`，状态 `profiles`、`isLoading`、`error`；方法 `load()`、`save(SshServerProfile)`、`delete(String)`

- [ ] **Step 1: 写失败测试**

```dart
test('loads server profiles from repository', () async {
  final cubit = SshServerConfigCubit(repository: repo);
  await cubit.load();
  expect(cubit.state.profiles, isEmpty);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/ssh_server_config_cubit_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 Cubit**

```dart
// client/lib/cubits/ssh_server_config_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_server_profile.dart';
import '../repositories/ssh_server_profile_repository.dart';

class SshServerConfigState extends Equatable {
  const SshServerConfigState({
    this.profiles = const [],
    this.isLoading = false,
    this.error,
  });

  final List<SshServerProfile> profiles;
  final bool isLoading;
  final Object? error;

  @override
  List<Object?> get props => [profiles, isLoading, error];
}

class SshServerConfigCubit extends Cubit<SshServerConfigState> {
  SshServerConfigCubit({required SshServerProfileRepository repository})
      : _repository = repository,
        super(const SshServerConfigState());

  final SshServerProfileRepository _repository;

  Future<void> load() async {
    emit(const SshServerConfigState(isLoading: true));
    try {
      final profiles = await _repository.loadAll();
      emit(SshServerConfigState(profiles: profiles));
    } on Object catch (error) {
      emit(SshServerConfigState(error: error));
    }
  }

  Future<void> save(SshServerProfile profile) async {
    await _repository.save(profile);
    await load();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/ssh_server_config_cubit_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/ssh_server_config_cubit.dart client/test/cubits/ssh_server_config_cubit_test.dart
git commit -m "feat(cubit): add SshServerConfigCubit"
```

---

### Task 9: `RemoteConnectionsPage` 与启动门控

**Files:**
- Create: `client/lib/pages/remote_connections_page.dart`
- Modify: `client/lib/pages/startup_gate.dart:35-37`

**Interfaces:**
- Consumes: `SshProfileCubit`（数据源已是本地 target）、`SshConnectionCubit`
- Produces: `RemoteConnectionsPage`，含目标列表、连接/断开、新建/编辑、切换 home

- [ ] **Step 1: 实现页面**

复用 `SshProfilesSection` 的卡片与表单，去掉 `onConfigure`（那是远端配置）：

```dart
// client/lib/pages/remote_connections_page.dart
import 'package:flutter/material.dart';

import 'ssh_profiles/ssh_profiles_section.dart';

class RemoteConnectionsPage extends StatelessWidget {
  const RemoteConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: SshProfilesSection(showRemoteConfig: false),
      ),
    );
  }
}
```

在 `SshProfilesSection` 增加 `showRemoteConfig` 参数（默认 `true`），为 `false` 时隐藏 `onConfigure` 入口：

```dart
class SshProfilesSection extends StatefulWidget {
  const SshProfilesSection({super.key, this.showRemoteConfig = true});

  final bool showRemoteConfig;

  @override
  State<SshProfilesSection> createState() => _SshProfilesSectionState();
}
```

其余成员与 `_SshProfilesSectionState` 保持不变。

对应 `SshProfileTargetCard` 传 `onConfigure: widget.showRemoteConfig ? ... : null`。

- [ ] **Step 2: 改启动门控**

`startup_gate.dart`：

```dart
if (mode.requiresSshProfileSetup) {
  return const RemoteConnectionsPage();
}
```

顶部 import 改为 `remote_connections_page.dart`。

- [ ] **Step 3: 验证编译与现有 smoke 测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error

Run: `cd client && dart run tool/run_tests.dart test/smoke/app_shell_smoke_test.dart`
Expected: PASS

- [ ] **Step 4: 手动验证**

启动 app，确认远程连接页有「添加目标」、没有远端配置入口；未配置 profile 时启动门控进入此页。

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/remote_connections_page.dart client/lib/pages/ssh_profiles/ssh_profiles_section.dart client/lib/pages/startup_gate.dart
git commit -m "feat(ui): add RemoteConnectionsPage and route startup gate to it"
```

---

### Task 10: `SshServersPage` 改造（远端配置）

**Files:**
- Modify: `client/lib/pages/ssh_profiles_page.dart`
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_target_card.dart`

**Interfaces:**
- Consumes: `SshServerConfigCubit`、`SshConnectionCubit`
- Produces: `SshServersPage`，连上后展示远端 profile，无连接按钮、无添加目标

- [ ] **Step 1: 实现页面**

```dart
// client/lib/pages/ssh_profiles_page.dart
class SshServersPage extends StatelessWidget {
  const SshServersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<SshConnectionCubit>().state.connectedHosts;
    if (connected.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.sshServersTitle)),
        body: Center(child: Text(context.l10n.sshServersNotConnected)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.sshServersTitle)),
      body: BlocBuilder<SshServerConfigCubit, SshServerConfigState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              for (final profile in state.profiles)
                SshServerProfileCard(profile: profile),
            ],
          );
        },
      ),
    );
  }
}
```

`SshServerProfileCard` 新建在同文件或 `pages/ssh_profiles/ssh_server_profile_card.dart`，只展示名称/host/embeddedTarget，编辑走 `showSshProfileTargetConfigDialog`。

- [ ] **Step 2: 验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error

Run: `cd client && dart run tool/run_tests.dart test/smoke/app_shell_smoke_test.dart`
Expected: PASS

- [ ] **Step 3: 手动验证**

启动 app，未连接时 SSH 服务器页显示「未连接」提示且没有连接按钮；连上后展示远端 profile。

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/ssh_profiles_page.dart client/lib/pages/ssh_profiles/ssh_profile_target_card.dart
git commit -m "feat(ui): turn SshProfilesPage into remote-only SshServersPage"
```

---

### Task 11: vault 页去掉新建业务凭据入口

**Files:**
- Modify: `client/lib/pages/vault/vault_page.dart:70-90`
- Modify: `client/lib/l10n/app_en.arb`、`app_zh.arb`

**Interfaces:**
- Produces: vault 页不再渲染 `vaultNewEntry` 按钮；SSH 登录凭据仍可见

- [ ] **Step 1: 删除按钮**

删除 `vault_page.dart` 中 `FilledButton.icon(... l10n.vaultNewEntry ...)` 整段。保留列表与解锁流程。

在 `app_en.arb` / `app_zh.arb` 中删除 `vaultNewEntry` 条目，并运行 `flutter gen-l10n`（若项目脚本要求）或让 CI 生成。

- [ ] **Step 2: 验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error

Run: `cd client && dart run tool/run_tests.dart test/smoke/app_shell_smoke_test.dart`
Expected: PASS

- [ ] **Step 3: 手动验证**

启动 app，保险库页没有「新建条目」按钮；已有 SSH 登录凭据仍可查看。

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/vault/vault_page.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "feat(vault): remove new business entry action"
```

---

### Task 12: 连上后触发同步

**Files:**
- Modify: `client/lib/cubits/ssh_connection_cubit.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/cubits/ssh_connection_cubit_sync_test.dart`

**Interfaces:**
- Consumes: `RemoteTargetSync`
- Produces: 连接成功后调用 `pull`，本地 `pendingSync` 时调用 `push`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/cubits/ssh_connection_cubit_sync_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/remote_target.dart';
import 'package:teampilot/repositories/remote_target_repository.dart';
import 'package:teampilot/repositories/ssh_server_profile_repository.dart';
import 'package:teampilot/services/ssh/remote_target_sync.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('pull then push reconciles a pending target', () async {
    final fs = InMemoryFilesystem();
    final targets = RemoteTargetRepository(rootDir: '/tp', fs: fs);
    final servers = SshServerProfileRepository(
      storage: fakeHomeStorage(filesystem: fs),
    );
    final sync = RemoteTargetSync(targets: targets, servers: servers);

    await targets.save(const RemoteTarget(
      id: 't1',
      name: 'dev',
      host: 'h',
      username: 'u',
      pendingSync: true,
      updatedAt: 10,
    ));

    final merged = await sync.pull((await targets.findById('t1'))!);
    await sync.push(merged);

    expect((await servers.findById('t1'))!.name, 'dev');
    expect((await targets.findById('t1'))!.pendingSync, isFalse);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/ssh_connection_cubit_sync_test.dart`
Expected: FAIL

- [ ] **Step 3: 接线**

`SshConnectionCubit` 构造增加可选参数：

```dart
SshConnectionCubit({
  required SshClientFactory factory,
  required SshProfileConnectionCoordinator coordinator,
  Future<void> Function(String id)? selectProfileOnConnect,
  PairedConnectAttempt? pairedConnectAttempt,
  PairedRelayTunnelRegistry? relayTunnels,
  RemoteTargetSync? sync,
}) : _factory = factory,
     _coordinator = coordinator,
     _selectProfileOnConnect = selectProfileOnConnect,
     _pairedConnectAttempt = pairedConnectAttempt,
     _relayTunnels = relayTunnels,
     _sync = sync,
     super(const SshConnectionState()) {
  _poolSubscription = _factory.storagePoolChanges.listen(_onPoolChanged);
}

final RemoteTargetSync? _sync;
```

在 `connect` 里 `_connectProfile(profile)` 成功后：

```dart
final target = await _sync?.targets.findById(profileId);
if (target != null) {
  final merged = await _sync!.pull(target);
  if (merged.pendingSync) await _sync.push(merged);
}
```

`app_shell.dart:2913` 注入：

```dart
final remoteTargetSync = RemoteTargetSync(
  targets: sshProfileRepo.targetRepo,
  servers: SshServerProfileRepository(storage: homeStorage),
);
final sshConnectionCubit = SshConnectionCubit(
  factory: sshClientFactory,
  coordinator: sshProfileConnectionCoordinator,
  sync: remoteTargetSync,
  ...
);
```

`homeStorage` 用该文件里 app-scoped 的 `HomeStorage` 实例（不能复用 `SshProfileRepository` 内部的 device-local storage）。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/ssh_connection_cubit_sync_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/ssh_connection_cubit.dart client/lib/app/app_shell.dart client/test/cubits/ssh_connection_cubit_sync_test.dart
git commit -m "feat(ssh): sync targets after connect"
```

---

### Task 13: 回归与全量验证

**Files:**
- Create: `client/test/services/storage/remote_target_pin_test.dart`
- Modify: `docs/ARCHITECTURE.md`（新增「移动端远程连接契约」一节）

- [ ] **Step 1: 写回归测试**

```dart
// client/test/services/storage/remote_target_pin_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/device_local_control_plane.dart';

void main() {
  test('target repo stays device-local after home rebinds to ssh', () async {
    final repo = deviceLocalRemoteTargetRepository('/tmp/native');
    expect(repo.fs, isA<LocalFilesystem>());
    expect(repo.rootDir, '/tmp/native');
  });
}
```

- [ ] **Step 2: 运行确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/remote_target_pin_test.dart`
Expected: PASS

- [ ] **Step 3: 文档**

在 `docs/ARCHITECTURE.md` 末尾新增：

```markdown
## Mobile remote connection contract

- 远程连接（本地）：所有目标条目、连接/断开/重连、切换 home；断线可用。
- SSH 服务器（远端）：仅连上后可用，读写 `<home>/ssh_profiles/` 与远端 `vault/`，不提供连接操作。
- 字段归属：断线重连要用的字段放本地；只有连上后才用的配置放远端。
- 同步：本地先行（`pendingSync`），连上后 `updatedAt` 新者胜。
```

- [ ] **Step 4: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error

Run: `cd client && dart run tool/run_tests.dart`
Expected: 全部通过

- [ ] **Step 5: Commit**

```bash
git add client/test/services/storage/remote_target_pin_test.dart docs/ARCHITECTURE.md
git commit -m "test(storage): pin RemoteTarget repo and document mobile remote contract"
```

---

## 自审记录

- **Spec 覆盖**：两页拆分（Task 9/10）、远端权威（Task 3/5/6）、本地 bootstrap（Task 1/2）、vault 调整（Task 11）、迁移（Task 4/7）、测试（Task 13）均有对应任务。
- **类型一致性**：`RemoteTarget` / `SshServerProfile` 字段在 Task 1/3 定义，Task 5/6 使用一致；`SshProfile.fromTarget` 在 Task 5 定义，Task 6/12 通过 `RemoteTarget` 使用。
- **未覆盖**：端口转发 / root sandbox 的具体编辑 UI 目前只有 credential push，新增字段留到后续 spec；本计划只保证结构就位。
