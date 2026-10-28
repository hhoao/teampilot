# 保险库（Vault）凭据管理实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增设备本地的凭据保险库（钥匙串默认 / 可选主密码加密文件），集中管理 SSH 密码、私钥、供应商 API Key 等密钥，并让 SSH profile 与供应商配置显式引用条目。

**Architecture:** 一个 `VaultDocument`（条目列表）经 `CredentialBackend` 持久化：`KeychainVaultBackend` 写 `SecureKeyValueStore` 单 key，`EncryptedVaultBackend` 写 `<nativeAppDataPath>/vault/vault.json`（Argon2id + AES-256-GCM）。`VaultService` 持有内存文档、锁定状态与 CRUD；`VaultCubit` 负责 UI 状态与引用反查。SSH 与供应商通过 `readField(entryId, field)` 取值，不感知底层后端。

**Tech Stack:** Flutter 3 / Dart 3.8、flutter_bloc、equatable、pointycastle 4.0.0（Argon2id、AES-GCM）、flutter_secure_storage、uuid、shared_ui（`Tp*`）。

## Global Constraints

- 测试必须用 `cd client && dart run tool/run_tests.dart <路径>`；**禁止直接运行 `flutter test`**。
- 每次声明完成前：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`。
- 保险库是**设备本地**数据，固定在 `nativeAppDataPath`（同 `ssh_profiles/`），不得使用 `HomeStorage.paths` 跟随远端 home。
- 密钥值不得写入日志、异常消息或 `toString()`；所有异常保持 secret-free。
- 新 UI 文本只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`，然后运行 `cd client && flutter gen-l10n`。
- 仅使用 `Filesystem` / 注入依赖；不得使用 `Directory.current`、`print`。
- 遵守分层：`models/` 纯数据、`services/vault/` 领域逻辑、`repositories/` 文件读写、`cubits/` 状态、`pages/vault/` 路由 UI。
- 单个文件超过约 400 行时拆分（见 `docs/CODE_QUALITY.md`）。
- 每个任务结束提交一次，提交信息用 `feat(vault): ...` / `test(vault): ...`。

---

## File Structure

**新建**

| 文件 | 职责 |
|------|------|
| `client/lib/models/vault_entry.dart` | 条目模型、类型预设、字段模板、序列化 |
| `client/lib/models/vault_document.dart` | 文档模型（版本化） |
| `client/lib/models/vault_reference.dart` | 引用反查结果 |
| `client/lib/services/vault/vault_errors.dart` | secret-free 异常类型 |
| `client/lib/services/vault/vault_crypto.dart` | Argon2id + AES-256-GCM 信封 |
| `client/lib/services/vault/credential_backend.dart` | 后端接口 |
| `client/lib/services/vault/keychain_vault_backend.dart` | 钥匙串后端 |
| `client/lib/services/vault/encrypted_vault_backend.dart` | 加密文件后端 |
| `client/lib/services/vault/vault_service.dart` | 文档状态、CRUD、后端切换 |
| `client/lib/repositories/vault_repository.dart` | `vault.json` 读写与归档 |
| `client/lib/cubits/vault_cubit.dart` | UI 状态、搜索过滤、引用反查 |
| `client/lib/pages/vault/vault_page.dart` | 页面主体 |
| `client/lib/pages/vault/vault_status_section.dart` | 解锁/锁定/启用/停用 |
| `client/lib/pages/vault/vault_entry_list.dart` | 搜索、过滤、列表 |
| `client/lib/pages/vault/vault_entry_detail.dart` | 掩码/揭示/复制/引用 |
| `client/lib/pages/vault/vault_entry_editor.dart` | 新建/编辑对话框 |
| `client/lib/pages/config/vault_config_section.dart` | 设置页壳 |

**修改**

| 文件 | 改动 |
|------|------|
| `client/lib/services/storage/app_paths.dart` | `vaultDir` / `vaultFile` / `vaultBackupFile` |
| `client/lib/services/storage/device_local_control_plane.dart` | `deviceLocalVaultRepository` |
| `client/lib/cubits/config_cubit.dart` | `ConfigSection.vault` + 标题/面包屑 |
| `client/lib/router/app_router.dart` | `/config/vault` |
| `client/lib/pages/config/config_workspace.dart` | 页面 switch + hub/sidebar 入口 |
| `client/lib/utils/ui/app_keys.dart` | `configVaultSectionButton` |
| `client/lib/app/app_shell.dart` | 构造 `VaultService`、`VaultCubit`、注入 factory、引用反查 |
| `client/lib/main.dart` | `RepositoryProvider<VaultService>`、`BlocProvider<VaultCubit>` |
| `client/lib/models/ssh_profile.dart` | `vaultEntryId` |
| `client/lib/services/ssh/ssh_client_factory.dart` | `VaultCredentialReader` 可选注入与解析 |
| `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart` | 凭据来源 + 保存到保险库 |
| `client/lib/pages/ssh_profile_setup_page.dart` | 同上（Android 全页） |
| `client/lib/pages/ssh_profiles/ssh_profiles_section.dart` | 保险库徽标 + 迁移动作 |
| `client/lib/app/app_shell.dart` | `appProviderLinkedCredentialLookup` 支持 `vault:` |
| `client/lib/widgets/app_provider/app_provider_form_sheet.dart` | 条目选项与 label |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | 文案 |
| `docs/workspace-storage-layout.md` | 记录 `vault/` |
| `docs/ARCHITECTURE.md` | 记录 `services/vault/` 边界（如适用） |

---

## Task 1: VaultEntry 模型

**Files:**
- Create: `client/lib/models/vault_entry.dart`
- Test: `client/test/models/vault_entry_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `VaultEntryType`（含 `storageValue`、`defaultFields`、`secretFields`）、`VaultEntry`（`id/type/title/fields/tags/notes/favorite/revealable/createdAt/updatedAt/extra`、`copyWith`、`toJson`、`fromJson`、`isSecretField`、`revealAllowed`）

- [ ] **Step 1: 写失败测试**

```dart
// client/test/models/vault_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_entry.dart';

void main() {
  test('round-trips every built-in type', () {
    for (final type in VaultEntryType.values) {
      final entry = VaultEntry(
        id: 'id-${type.storageValue}',
        type: type,
        title: 'title',
        fields: {for (final f in type.defaultFields) f: 'v-$f'},
        tags: const ['work'],
        notes: 'note',
        favorite: true,
        revealable: type != VaultEntryType.sshPrivateKey,
        createdAt: 1,
        updatedAt: 2,
      );
      expect(VaultEntry.fromJson(entry.toJson()), entry);
    }
  });

  test('unknown type falls back to custom and keeps unknown top-level keys', () {
    final entry = VaultEntry.fromJson({
      'id': 'a',
      'type': 'future_type',
      'title': 'x',
      'fields': {'k': 'v'},
      'unknownTopLevel': 42,
    });
    expect(entry.type, VaultEntryType.custom);
    expect(entry.extra['unknownTopLevel'], 42);
    expect(entry.toJson()['unknownTopLevel'], 42);
  });

  test('secret fields are masked per type and custom fields are always secret', () {
    const ssh = VaultEntry(id: '1', type: VaultEntryType.sshPassword, title: 's');
    expect(ssh.isSecretField('password'), isTrue);
    expect(ssh.isSecretField('username'), isFalse);

    const custom = VaultEntry(id: '2', type: VaultEntryType.custom, title: 'c');
    expect(custom.isSecretField('anything'), isTrue);
  });

  test('private keys are never revealable', () {
    const entry = VaultEntry(
      id: '1',
      type: VaultEntryType.sshPrivateKey,
      title: 'k',
      revealable: true,
    );
    expect(entry.revealAllowed, isFalse);
  });

  test('toString never contains field values', () {
    const entry = VaultEntry(
      id: '1',
      type: VaultEntryType.apiKey,
      title: 'openai',
      fields: {'apiKey': 'sk-super-secret'},
    );
    expect(entry.toString(), isNot(contains('sk-super-secret')));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/vault_entry_test.dart`
Expected: FAIL，`Error: Couldn't resolve the package 'teampilot'` 之后紧跟找不到 `models/vault_entry.dart`。

- [ ] **Step 3: 实现模型**

```dart
// client/lib/models/vault_entry.dart
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

enum VaultEntryType {
  sshPassword('ssh_password'),
  sshPrivateKey('ssh_private_key'),
  apiKey('api_key'),
  login('login'),
  token('token'),
  secureNote('secure_note'),
  custom('custom');

  const VaultEntryType(this.storageValue);

  final String storageValue;

  static VaultEntryType fromStorage(Object? raw) {
    for (final type in values) {
      if (type.storageValue == raw) return type;
    }
    return VaultEntryType.custom;
  }

  List<String> get defaultFields => switch (this) {
    VaultEntryType.sshPassword => const ['host', 'port', 'username', 'password'],
    VaultEntryType.sshPrivateKey => const ['privateKey', 'passphrase'],
    VaultEntryType.apiKey => const ['provider', 'apiKey', 'baseUrl'],
    VaultEntryType.login => const ['url', 'username', 'password'],
    VaultEntryType.token => const ['token'],
    VaultEntryType.secureNote => const ['note'],
    VaultEntryType.custom => const [],
  };

  Set<String> get secretFields => switch (this) {
    VaultEntryType.sshPassword => const {'password'},
    VaultEntryType.sshPrivateKey => const {'privateKey', 'passphrase'},
    VaultEntryType.apiKey => const {'apiKey'},
    VaultEntryType.login => const {'password'},
    VaultEntryType.token => const {'token'},
    VaultEntryType.secureNote => const {'note'},
    VaultEntryType.custom => const {},
  };
}

@immutable
class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.type,
    required this.title,
    this.fields = const {},
    this.tags = const [],
    this.notes = '',
    this.favorite = false,
    this.revealable = true,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.extra = const {},
  });

  factory VaultEntry.fromJson(Map<String, Object?> json) {
    const known = {
      'id',
      'type',
      'title',
      'fields',
      'tags',
      'notes',
      'favorite',
      'revealable',
      'createdAt',
      'updatedAt',
    };
    final rawFields = json['fields'];
    return VaultEntry(
      id: json['id']?.toString() ?? '',
      type: VaultEntryType.fromStorage(json['type']),
      title: json['title']?.toString() ?? '',
      fields: rawFields is Map
          ? {
              for (final entry in rawFields.entries)
                entry.key.toString(): entry.value?.toString() ?? '',
            }
          : const {},
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      notes: json['notes']?.toString() ?? '',
      favorite: json['favorite'] == true,
      revealable: json['revealable'] != false,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      extra: {
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  final String id;
  final VaultEntryType type;
  final String title;
  final Map<String, String> fields;
  final List<String> tags;
  final String notes;
  final bool favorite;
  final bool revealable;
  final int createdAt;
  final int updatedAt;
  final Map<String, Object?> extra;

  /// 私钥永远不可揭示；其余类型遵循条目标记。
  bool get revealAllowed =>
      type != VaultEntryType.sshPrivateKey && revealable;

  bool isSecretField(String field) {
    if (type == VaultEntryType.custom) return true;
    return type.secretFields.contains(field);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.storageValue,
    'title': title,
    'fields': fields,
    'tags': tags,
    'notes': notes,
    'favorite': favorite,
    'revealable': revealable,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    ...extra,
  };

  VaultEntry copyWith({
    String? id,
    VaultEntryType? type,
    String? title,
    Map<String, String>? fields,
    List<String>? tags,
    String? notes,
    bool? favorite,
    bool? revealable,
    int? createdAt,
    int? updatedAt,
    Map<String, Object?>? extra,
  }) {
    return VaultEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      fields: fields ?? this.fields,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      favorite: favorite ?? this.favorite,
      revealable: revealable ?? this.revealable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      extra: extra ?? this.extra,
    );
  }

  @override
  bool operator ==(Object other) {
    const deep = DeepCollectionEquality();
    const list = ListEquality<String>();
    return other is VaultEntry &&
        other.id == id &&
        other.type == type &&
        other.title == title &&
        deep.equals(other.fields, fields) &&
        list.equals(other.tags, tags) &&
        other.notes == notes &&
        other.favorite == favorite &&
        other.revealable == revealable &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        deep.equals(other.extra, extra);
  }

  @override
  int get hashCode {
    const deep = DeepCollectionEquality();
    const list = ListEquality<String>();
    return Object.hash(
      id,
      type,
      title,
      deep.hash(fields),
      list.hash(tags),
      notes,
      favorite,
      revealable,
      createdAt,
      updatedAt,
      deep.hash(extra),
    );
  }

  @override
  String toString() => 'VaultEntry(${type.storageValue}, $title, <redacted>)';
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/models/vault_entry_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add client/lib/models/vault_entry.dart client/test/models/vault_entry_test.dart
git commit -m "feat(vault): add vault entry model"
```

---

## Task 2: VaultDocument、异常与加密信封

**Files:**
- Create: `client/lib/models/vault_document.dart`
- Create: `client/lib/services/vault/vault_errors.dart`
- Create: `client/lib/services/vault/vault_crypto.dart`
- Test: `client/test/services/vault/vault_crypto_test.dart`
- Test: `client/test/models/vault_document_test.dart`

**Interfaces:**
- Consumes: `VaultEntry`
- Produces:
  - `VaultDocument({int version = 1, List<VaultEntry> entries = const []})`、`toJson`、`fromJson`、`copyWith`
  - `VaultLockedException`、`VaultFormatException`、`VaultDecryptException`
  - `VaultCrypto({int memoryKiB = 65536, int iterations = 3, int parallelism = 1})`
  - `Future<VaultEnvelope> encrypt(VaultDocument doc, String passphrase)`
  - `Future<VaultDocument> decrypt(VaultEnvelope envelope, String passphrase)`
  - `VaultEnvelope({int version, Uint8List salt, Uint8List nonce, Uint8List payload, int memoryKiB, int iterations, int parallelism})`、`toJson`、`fromJson`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/models/vault_document_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';

void main() {
  test('round-trips entries and version', () {
    const document = VaultDocument(
      entries: [
        VaultEntry(
          id: '1',
          type: VaultEntryType.login,
          title: 'GitHub',
          fields: {'username': 'me', 'password': 'p'},
        ),
      ],
    );
    expect(VaultDocument.fromJson(document.toJson()), document);
  });

  test('rejects unknown document versions', () {
    expect(
      () => VaultDocument.fromJson({'version': 99, 'entries': []}),
      throwsA(isA<FormatException>()),
    );
  });
}
```

```dart
// client/test/services/vault/vault_crypto_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_errors.dart';

const _document = VaultDocument(
  entries: [
    VaultEntry(
      id: '1',
      type: VaultEntryType.apiKey,
      title: 'OpenAI',
      fields: {'apiKey': 'sk-secret'},
    ),
  ],
);

void main() {
  // 低参数只为跑得快；生产默认值另测。
  const crypto = VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1);

  test('encrypts and decrypts the document', () async {
    final envelope = await crypto.encrypt(_document, 'pass');
    final decoded = await crypto.decrypt(envelope, 'pass');
    expect(decoded, _document);
  });

  test('ciphertext does not contain plaintext', () async {
    final envelope = await crypto.encrypt(_document, 'pass');
    expect(utf8.decode(envelope.payload, allowMalformed: true),
        isNot(contains('sk-secret')));
  });

  test('wrong passphrase fails without leaking secrets', () async {
    final envelope = await crypto.encrypt(_document, 'pass');
    await expectLater(
      crypto.decrypt(envelope, 'wrong'),
      throwsA(isA<VaultDecryptException>()),
    );
  });

  test('tampered payload fails authentication', () async {
    final envelope = await crypto.encrypt(_document, 'pass');
    final payload = Uint8List.fromList(envelope.payload);
    payload[0] ^= 0xff;
    final tampered = VaultEnvelope(
      version: envelope.version,
      salt: envelope.salt,
      nonce: envelope.nonce,
      payload: payload,
      memoryKiB: envelope.memoryKiB,
      iterations: envelope.iterations,
      parallelism: envelope.parallelism,
    );
    await expectLater(
      crypto.decrypt(tampered, 'pass'),
      throwsA(isA<VaultDecryptException>()),
    );
  });

  test('envelope json round-trips and rejects unknown versions', () {
    // 同步构造一个信封只为验证编解码。
    final envelope = VaultEnvelope(
      version: 1,
      salt: Uint8List.fromList(List.filled(16, 1)),
      nonce: Uint8List.fromList(List.filled(12, 2)),
      payload: Uint8List.fromList([1, 2, 3]),
      memoryKiB: 1024,
      iterations: 2,
      parallelism: 1,
    );
    expect(VaultEnvelope.fromJson(envelope.toJson()), envelope);
    expect(
      () => VaultEnvelope.fromJson({...envelope.toJson(), 'v': 2}),
      throwsA(isA<VaultFormatException>()),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/vault_document_test.dart test/services/vault/vault_crypto_test.dart`
Expected: FAIL，找不到 `models/vault_document.dart` / `services/vault/vault_crypto.dart`。

- [ ] **Step 3: 实现文档与异常**

```dart
// client/lib/models/vault_document.dart
import 'package:collection/collection.dart';

import 'vault_entry.dart';

class VaultDocument {
  const VaultDocument({this.version = 1, this.entries = const []});

  factory VaultDocument.fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? 1;
    if (version != 1) {
      throw const FormatException('Unsupported vault document version');
    }
    final rawEntries = json['entries'];
    return VaultDocument(
      version: version,
      entries: rawEntries is List
          ? [
              for (final raw in rawEntries)
                if (raw is Map)
                  VaultEntry.fromJson(Map<String, Object?>.from(raw)),
            ]
          : const [],
    );
  }

  final int version;
  final List<VaultEntry> entries;

  Map<String, Object?> toJson() => {
    'version': version,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  VaultDocument copyWith({List<VaultEntry>? entries}) =>
      VaultDocument(version: version, entries: entries ?? this.entries);

  @override
  bool operator ==(Object other) =>
      other is VaultDocument &&
      other.version == version &&
      const ListEquality<VaultEntry>().equals(other.entries, entries);

  @override
  int get hashCode =>
      Object.hash(version, const ListEquality<VaultEntry>().hash(entries));
}
```

```dart
// client/lib/services/vault/vault_errors.dart
/// 保险库操作失败。所有异常只带错误码，不带任何密钥值。
sealed class VaultException implements Exception {
  const VaultException(this.code);

  final String code;

  @override
  String toString() => 'VaultException($code)';
}

class VaultLockedException extends VaultException {
  const VaultLockedException() : super('locked');
}

class VaultFormatException extends VaultException {
  const VaultFormatException([this.detail = '']) : super('format');

  final String detail;

  @override
  String toString() => 'VaultFormatException($detail)';
}

class VaultDecryptException extends VaultException {
  const VaultDecryptException() : super('decrypt');
}

class VaultStorageException extends VaultException {
  const VaultStorageException(super.code);
}
```

- [ ] **Step 4: 实现加密信封**

```dart
// client/lib/services/vault/vault_crypto.dart
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:pointycastle/export.dart';

import '../../models/vault_document.dart';
import 'vault_errors.dart';

class VaultEnvelope {
  const VaultEnvelope({
    required this.version,
    required this.salt,
    required this.nonce,
    required this.payload,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  factory VaultEnvelope.fromJson(Map<String, Object?> json) {
    if ((json['v'] as num?)?.toInt() != 1) {
      throw const VaultFormatException('unsupported envelope version');
    }
    final kdf = json['kdf'];
    final cipher = json['cipher'];
    if (kdf is! Map || cipher is! Map) {
      throw const VaultFormatException('missing kdf/cipher');
    }
    try {
      return VaultEnvelope(
        version: 1,
        salt: base64Decode(kdf['salt'] as String),
        nonce: base64Decode(cipher['nonce'] as String),
        payload: base64Decode(json['payload'] as String),
        memoryKiB: (kdf['memoryKiB'] as num).toInt(),
        iterations: (kdf['iterations'] as num).toInt(),
        parallelism: (kdf['parallelism'] as num).toInt(),
      );
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException('malformed envelope');
    }
  }

  final int version;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List payload;
  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Map<String, Object?> toJson() => {
    'v': version,
    'kdf': {
      'name': 'argon2id',
      'salt': base64Encode(salt),
      'memoryKiB': memoryKiB,
      'iterations': iterations,
      'parallelism': parallelism,
    },
    'cipher': {'name': 'aes-256-gcm', 'nonce': base64Encode(nonce)},
    'payload': base64Encode(payload),
  };

  @override
  bool operator ==(Object other) {
    const bytes = ListEquality<int>();
    return other is VaultEnvelope &&
        other.version == version &&
        bytes.equals(other.salt, salt) &&
        bytes.equals(other.nonce, nonce) &&
        bytes.equals(other.payload, payload) &&
        other.memoryKiB == memoryKiB &&
        other.iterations == iterations &&
        other.parallelism == parallelism;
  }

  @override
  int get hashCode {
    const bytes = ListEquality<int>();
    return Object.hash(
      version,
      bytes.hash(salt),
      bytes.hash(nonce),
      bytes.hash(payload),
      memoryKiB,
      iterations,
      parallelism,
    );
  }
}

class VaultCrypto {
  const VaultCrypto({
    this.memoryKiB = 65536,
    this.iterations = 3,
    this.parallelism = 1,
  });

  static const _keyLength = 32;
  static const _saltLength = 16;
  static const _nonceLength = 12;

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  Future<VaultEnvelope> encrypt(
    VaultDocument document,
    String passphrase,
  ) async {
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final plaintext = jsonEncode(document.toJson());
    final payload = await Isolate.run(
      () => _encryptSync(
        plaintext: plaintext,
        passphrase: passphrase,
        salt: salt,
        nonce: nonce,
        memoryKiB: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
      ),
    );
    return VaultEnvelope(
      version: 1,
      salt: salt,
      nonce: nonce,
      payload: payload,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );
  }

  Future<VaultDocument> decrypt(
    VaultEnvelope envelope,
    String passphrase,
  ) async {
    final plaintext = await Isolate.run(
      () => _decryptSync(
        payload: envelope.payload,
        passphrase: passphrase,
        salt: envelope.salt,
        nonce: envelope.nonce,
        memoryKiB: envelope.memoryKiB,
        iterations: envelope.iterations,
        parallelism: envelope.parallelism,
      ),
    );
    try {
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map) throw const FormatException();
      return VaultDocument.fromJson(Map<String, Object?>.from(decoded));
    } on VaultFormatException {
      rethrow;
    } on Object {
      throw const VaultFormatException('decrypted payload is not a vault');
    }
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

Uint8List _encryptSync({
  required String plaintext,
  required String passphrase,
  required Uint8List salt,
  required Uint8List nonce,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
}) {
  final key = _deriveKey(
    passphrase: passphrase,
    salt: salt,
    memoryKiB: memoryKiB,
    iterations: iterations,
    parallelism: parallelism,
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
    );
  return cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
}

String _decryptSync({
  required Uint8List payload,
  required String passphrase,
  required Uint8List salt,
  required Uint8List nonce,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
}) {
  final key = _deriveKey(
    passphrase: passphrase,
    salt: salt,
    memoryKiB: memoryKiB,
    iterations: iterations,
    parallelism: parallelism,
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)),
    );
  try {
    return utf8.decode(cipher.process(payload));
  } on Object {
    // GCM tag mismatch 与结构损坏不可区分；都不泄露任何明文。
    throw const VaultDecryptException();
  }
}

Uint8List _deriveKey({
  required String passphrase,
  required Uint8List salt,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
}) {
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: 32,
        iterations: iterations,
        memory: memoryKiB,
        lanes: parallelism,
      ),
    );
  return generator.process(Uint8List.fromList(utf8.encode(passphrase)));
}
```

> 如果 `Isolate.run` 在某些平台关闭了 isolate，`encrypt` 会抛错；计划不处理该平台分支，测试在桌面/CI 均启用 isolate。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/models/vault_document_test.dart test/services/vault/vault_crypto_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: 提交**

```bash
git add client/lib/models/vault_document.dart client/lib/services/vault/vault_errors.dart client/lib/services/vault/vault_crypto.dart client/test/models/vault_document_test.dart client/test/services/vault/vault_crypto_test.dart
git commit -m "feat(vault): add document envelope with argon2id and aes-gcm"
```

---

## Task 3: 后端接口与钥匙串后端

**Files:**
- Create: `client/lib/services/vault/credential_backend.dart`
- Create: `client/lib/services/vault/keychain_vault_backend.dart`
- Test: `client/test/services/vault/keychain_vault_backend_test.dart`

**Interfaces:**
- Consumes: `VaultDocument`、`SecureKeyValueStore`、`VaultLockedException`
- Produces:
  - `abstract interface class CredentialBackend { String get kind; bool get needsUnlock; Future<VaultDocument?> load(); Future<void> save(VaultDocument doc); Future<void> clear(); }`
  - `KeychainVaultBackend(SecureKeyValueStore store)`，`static const storageKey = 'teampilot.vault.v1.document'`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/vault/keychain_vault_backend_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('returns null before the first save', () async {
    final backend = KeychainVaultBackend(_FakeStore());
    expect(await backend.load(), isNull);
    expect(backend.needsUnlock, isFalse);
  });

  test('round-trips the document under one key', () async {
    final store = _FakeStore();
    final backend = KeychainVaultBackend(store);
    const document = VaultDocument(
      entries: [
        VaultEntry(id: '1', type: VaultEntryType.token, title: 't'),
      ],
    );

    await backend.save(document);

    expect(store.values.keys, [KeychainVaultBackend.storageKey]);
    expect(await backend.load(), document);
  });

  test('clear removes the stored document', () async {
    final store = _FakeStore();
    final backend = KeychainVaultBackend(store);
    await backend.save(const VaultDocument());
    await backend.clear();
    expect(await backend.load(), isNull);
    expect(store.values, isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/keychain_vault_backend_test.dart`
Expected: FAIL，找不到 `keychain_vault_backend.dart`。

- [ ] **Step 3: 实现接口与后端**

```dart
// client/lib/services/vault/credential_backend.dart
import '../../models/vault_document.dart';

abstract interface class CredentialBackend {
  String get kind;
  bool get needsUnlock;

  /// 无文档返回 null；存在但锁定抛 [VaultLockedException]。
  Future<VaultDocument?> load();

  Future<void> save(VaultDocument document);

  /// 删除（钥匙串）或归档（加密文件）本后端持有的文档。
  Future<void> clear();
}
```

```dart
// client/lib/services/vault/keychain_vault_backend.dart
import 'dart:convert';

import '../../models/vault_document.dart';
import '../../repositories/ssh_credential_store.dart';
import 'credential_backend.dart';
import 'vault_errors.dart';

/// 默认后端：整份文档放在系统钥匙串的单个 key 下。
class KeychainVaultBackend implements CredentialBackend {
  const KeychainVaultBackend(this._store);

  static const storageKey = 'teampilot.vault.v1.document';

  final SecureKeyValueStore _store;

  @override
  String get kind => 'keychain';

  @override
  bool get needsUnlock => false;

  @override
  Future<VaultDocument?> load() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      return VaultDocument.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      throw const VaultFormatException('keychain document is malformed');
    }
  }

  @override
  Future<void> save(VaultDocument document) async {
    try {
      await _store.write(storageKey, jsonEncode(document.toJson()));
    } on Object {
      throw const VaultStorageException('keychainWriteFailed');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _store.delete(storageKey);
    } on Object {
      throw const VaultStorageException('keychainDeleteFailed');
    }
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/keychain_vault_backend_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/vault/credential_backend.dart client/lib/services/vault/keychain_vault_backend.dart client/test/services/vault/keychain_vault_backend_test.dart
git commit -m "feat(vault): add credential backend and keychain backend"
```

---

## Task 4: VaultRepository 与加密文件后端

**Files:**
- Modify: `client/lib/services/storage/app_paths.dart`（在 `sshProfilesDir` 附近）
- Modify: `client/lib/services/storage/device_local_control_plane.dart`
- Create: `client/lib/repositories/vault_repository.dart`
- Create: `client/lib/services/vault/encrypted_vault_backend.dart`
- Test: `client/test/repositories/vault_repository_test.dart`
- Test: `client/test/services/vault/encrypted_vault_backend_test.dart`

**Interfaces:**
- Consumes: `Filesystem`、`AppPaths.vaultDir/vaultFile/vaultBackupFile`、`VaultCrypto`、`CredentialBackend`
- Produces:
  - `VaultRepository({required String rootDir, required Filesystem fs})`，`vaultFile`、`backupFile`、`exists()`、`readRaw()`、`writeRaw(String)`、`archive()`
  - `deviceLocalVaultRepository(String nativeAppDataPath)`
  - `EncryptedVaultBackend({required VaultRepository repository, VaultCrypto crypto = const VaultCrypto()})`
  - `Future<bool> get isInitialized`、`unlock(String)`、`initialize(VaultDocument, String)`、`lock()`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/repositories/vault_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  test('app paths expose the vault file and backup', () {
    final paths = AppPaths('/root');
    expect(paths.vaultDir, p.join('/root', 'vault'));
    expect(paths.vaultFile, p.join('/root', 'vault', 'vault.json'));
    expect(
      paths.vaultBackupFile,
      p.join('/root', 'vault', 'vault.json.bak'),
    );
  });

  test('writes atomically and archives to the backup path', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final repo = VaultRepository(rootDir: '/root/vault', fs: fs);

    expect(await repo.exists(), isFalse);
    await repo.writeRaw('{"v":1}');
    expect(await repo.exists(), isTrue);
    expect(await repo.readRaw(), '{"v":1}');

    await repo.archive();
    expect(await repo.exists(), isFalse);
    expect(await fs.readString(p.join('/root/vault', 'vault.json.bak')),
        '{"v":1}');
  });
}
```

```dart
// client/test/services/vault/encrypted_vault_backend_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_errors.dart';
import '../../support/in_memory_filesystem.dart';

const _document = VaultDocument(
  entries: [VaultEntry(id: '1', type: VaultEntryType.token, title: 't')],
);

void main() {
  const crypto = VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1);

  EncryptedVaultBackend buildBackend(InMemoryFilesystem fs) =>
      EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: crypto,
      );

  test('needs initialization before any file exists', () async {
    final backend = buildBackend(
      InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
    );
    expect(await backend.isInitialized, isFalse);
    expect(await backend.load(), isNull);
  });

  test('initialize writes an unlockable file', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final backend = buildBackend(fs);

    await backend.initialize(_document, 'pass');
    expect(await backend.isInitialized, isTrue);
    expect(backend.needsUnlock, isFalse);

    backend.lock();
    expect(backend.needsUnlock, isTrue);
    await expectLater(backend.load(), throwsA(isA<VaultLockedException>()));

    await backend.unlock('pass');
    expect(backend.needsUnlock, isFalse);
    expect(await backend.load(), _document);
  });

  test('save updates the file only after unlock', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final backend = buildBackend(fs);
    await backend.initialize(_document, 'pass');

    const next = VaultDocument(
      entries: [VaultEntry(id: '2', type: VaultEntryType.login, title: 'x')],
    );
    await backend.save(next);
    backend.lock();
    await backend.unlock('pass');
    expect((await backend.load())?.entries.single.id, '2');
  });

  test('clear archives the file so the backend becomes uninitialized', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final backend = buildBackend(fs);
    await backend.initialize(_document, 'pass');
    await backend.clear();
    expect(await backend.isInitialized, isFalse);
    expect(backend.needsUnlock, isFalse);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/repositories/vault_repository_test.dart test/services/vault/encrypted_vault_backend_test.dart`
Expected: FAIL，找不到 `vault_repository.dart`。

- [ ] **Step 3: 加路径与设备本地工厂**

`AppPaths`（`sshProfilesDir` 之后）：

```dart
  String get vaultDir => _ctx.join(basePath, 'vault');
  String get vaultFile => _ctx.join(vaultDir, 'vault.json');
  String get vaultBackupFile => _ctx.join(vaultDir, 'vault.json.bak');
```

`device_local_control_plane.dart` 顶部加 import：

```dart
import '../../repositories/vault_repository.dart';
```

文件末尾加：

```dart
/// 设备本地保险库（`vault/vault.json` under native app data）。
///
/// 与 [deviceLocalSshProfileRepository] 同一 pin：Android Connect 会把 home
/// 重绑到远端，保险库绝不能跟着走。
VaultRepository deviceLocalVaultRepository(String nativeAppDataPath) {
  final paths = AppPaths(nativeAppDataPath);
  return VaultRepository(
    rootDir: paths.vaultDir,
    fs: LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(nativeAppDataPath),
    ),
  );
}
```

- [ ] **Step 4: 实现仓储**

```dart
// client/lib/repositories/vault_repository.dart
import '../services/io/filesystem.dart';

/// `<root>/vault/vault.json` 的读写。
///
/// 始终使用设备本地 root（见 `deviceLocalVaultRepository`），因此这里直接
/// 接收 root + fs，不依赖 HomeStorage。
class VaultRepository {
  VaultRepository({required String rootDir, required Filesystem fs})
    : _root = rootDir,
      _fs = fs;

  final String _root;
  final Filesystem _fs;

  String get vaultFile => _fs.pathContext.join(_root, 'vault.json');
  String get backupFile => _fs.pathContext.join(_root, 'vault.json.bak');

  Future<bool> exists() async => (await _fs.stat(vaultFile)).isFile;

  Future<String?> readRaw() async {
    if (!await exists()) return null;
    return _fs.readString(vaultFile);
  }

  Future<void> writeRaw(String content) async {
    await _fs.ensureDir(_root);
    await _fs.atomicWrite(vaultFile, content);
  }

  /// 停用加密后端时把文件移到 `.bak`，保留最近一次可恢复副本。
  Future<void> archive() async {
    if (!await exists()) return;
    final backupExists = (await _fs.stat(backupFile)).isFile;
    if (backupExists) await _fs.removeRecursive(backupFile);
    await _fs.rename(vaultFile, backupFile);
  }
}
```

InMemoryFilesystem 是否实现 `rename` / `removeRecursive` / `ensureDir` / `atomicWrite`？测试通过前若缺失先补实现（见 `client/test/support/in_memory_filesystem.dart`；现有测试已使用这些方法，正常无需改动）。

- [ ] **Step 5: 实现加密后端**

```dart
// client/lib/services/vault/encrypted_vault_backend.dart
import 'dart:convert';

import '../../models/vault_document.dart';
import '../../repositories/vault_repository.dart';
import 'credential_backend.dart';
import 'vault_crypto.dart';
import 'vault_errors.dart';

/// 可选后端：主密码加密的 `vault.json`。解锁后文档只驻留内存。
class EncryptedVaultBackend implements CredentialBackend {
  EncryptedVaultBackend({
    required VaultRepository repository,
    VaultCrypto crypto = const VaultCrypto(),
  }) : _repository = repository,
       _crypto = crypto;

  final VaultRepository _repository;
  final VaultCrypto _crypto;
  VaultDocument? _unlocked;

  @override
  String get kind => 'encrypted';

  @override
  bool get needsUnlock => _unlocked == null;

  Future<bool> get isInitialized => _repository.exists();

  @override
  Future<VaultDocument?> load() async {
    final unlocked = _unlocked;
    if (unlocked != null) return unlocked;
    if (!await _repository.exists()) return null;
    throw const VaultLockedException();
  }

  Future<void> unlock(String passphrase) async {
    final raw = await _repository.readRaw();
    if (raw == null) {
      throw const VaultFormatException('vault file missing');
    }
    final VaultDocument document;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const VaultFormatException('not an object');
      document = await _crypto.decrypt(
        VaultEnvelope.fromJson(Map<String, Object?>.from(decoded)),
        passphrase,
      );
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultFormatException('unreadable vault file');
    }
    _unlocked = document;
  }

  Future<void> initialize(VaultDocument document, String passphrase) async {
    final envelope = await _crypto.encrypt(document, passphrase);
    await _repository.writeRaw(jsonEncode(envelope.toJson()));
    // 回读校验：解不开就不要把用户数据留在半成品文件里。
    final raw = await _repository.readRaw();
    if (raw == null) throw const VaultStorageException('vaultWriteFailed');
    final verified = await _crypto.decrypt(
      VaultEnvelope.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      ),
      passphrase,
    );
    if (verified.entries.length != document.entries.length) {
      throw const VaultStorageException('vaultVerifyFailed');
    }
    _unlocked = document;
  }

  @override
  Future<void> save(VaultDocument document) async {
    if (needsUnlock) throw const VaultLockedException();
    final envelope = await _crypto.encrypt(document, _lastPassphrase!);
    await _repository.writeRaw(jsonEncode(envelope.toJson()));
    _unlocked = document;
  }

  void lock() => _unlocked = null;

  @override
  Future<void> clear() async {
    _unlocked = null;
    await _repository.archive();
  }

  String? _lastPassphrase;
}
```

> 上面 `save` 需要主密码，但后端不应长期持有明文密码。改为：`unlock()` 只保存派生密钥不可行（每次加密需要重新派生），因此把密码保存在 `EncryptedVaultBackend` 的内存字段 `_lastPassphrase`，在 `lock()` / `clear()` 时清空。补上：

```dart
  Future<void> unlock(String passphrase) async {
    // ... 现有解密逻辑 ...
    _unlocked = document;
    _lastPassphrase = passphrase;
  }

  void lock() {
    _unlocked = null;
    _lastPassphrase = null;
  }

  @override
  Future<void> clear() async {
    _unlocked = null;
    _lastPassphrase = null;
    await _repository.archive();
  }
```

并在 `initialize` 末尾加 `_lastPassphrase = passphrase;`。

- [ ] **Step 6: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/repositories/vault_repository_test.dart test/services/vault/encrypted_vault_backend_test.dart`
Expected: `All tests passed!`

- [ ] **Step 7: 提交**

```bash
git add client/lib/services/storage/app_paths.dart client/lib/services/storage/device_local_control_plane.dart client/lib/repositories/vault_repository.dart client/lib/services/vault/encrypted_vault_backend.dart client/test/repositories/vault_repository_test.dart client/test/services/vault/encrypted_vault_backend_test.dart
git commit -m "feat(vault): add encrypted vault backend and device-local repository"
```

---

## Task 5: VaultService

**Files:**
- Create: `client/lib/services/vault/vault_service.dart`
- Test: `client/test/services/vault/vault_service_test.dart`

**Interfaces:**
- Consumes: `CredentialBackend`、`KeychainVaultBackend`、`EncryptedVaultBackend`、`VaultDocument`、`VaultEntry`
- Produces:
  - `VaultService({required KeychainVaultBackend keychainBackend, required EncryptedVaultBackend encryptedBackend})`
  - `initialize`、`unlock`、`lock`、`isEncrypted`、`isLocked`、`isUnlocked`
  - `list({String query, VaultEntryType? type, Set<String> tags})`
  - `get`、`upsert`、`delete`、`readField`
  - `enableEncryptedBackend(String passphrase)`、`disableEncryptedBackend()`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/vault/vault_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_errors.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import '../../support/in_memory_filesystem.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  const crypto = VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1);

  VaultService buildService({_FakeStore? store}) {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    return VaultService(
      keychainBackend: KeychainVaultBackend(store ?? _FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: crypto,
      ),
    );
  }

  test('starts on the keychain backend and creates entries', () async {
    final service = buildService();
    await service.initialize();
    expect(service.isEncrypted, isFalse);
    expect(service.isUnlocked, isTrue);

    await service.upsert(
      const VaultEntry(id: 'a', type: VaultEntryType.token, title: 'A'),
    );
    expect((await service.list()).single.title, 'A');
    expect(await service.readField('a', 'token'), isNull);
  });

  test('search matches title, tag and field values', () async {
    final service = buildService();
    await service.initialize();
    await service.upsert(
      const VaultEntry(
        id: 'a',
        type: VaultEntryType.login,
        title: 'GitHub',
        fields: {'username': 'octocat', 'password': 'pw'},
        tags: ['work'],
      ),
    );

    expect(await service.list(query: 'git'), hasLength(1));
    expect(await service.list(query: 'octo'), hasLength(1));
    expect(await service.list(query: 'work'), hasLength(1));
    expect(await service.list(query: 'nope'), isEmpty);
    expect(
      await service.list(type: VaultEntryType.token),
      isEmpty,
    );
  });

  test('enabling encryption migrates the document and locks on reload', () async {
    final store = _FakeStore();
    final service = buildService(store: store);
    await service.initialize();
    await service.upsert(
      const VaultEntry(id: 'a', type: VaultEntryType.token, title: 'A'),
    );

    await service.enableEncryptedBackend('master');
    expect(service.isEncrypted, isTrue);
    expect(service.isUnlocked, isTrue);
    expect(store.values, isEmpty);
    expect((await service.list()).single.id, 'a');

    service.lock();
    expect(service.isLocked, isTrue);
    await expectLater(service.list(), throwsA(isA<VaultLockedException>()));
    await service.unlock('master');
    expect((await service.list()).single.id, 'a');
  });

  test('initialize does not re-lock an already unlocked vault', () async {
    final service = buildService();
    await service.initialize();
    await service.enableEncryptedBackend('master');
    await service.initialize();
    expect(service.isLocked, isFalse);
  });

  test('disabling encryption returns the document to the keychain', () async {
    final store = _FakeStore();
    final service = buildService(store: store);
    await service.initialize();
    await service.upsert(
      const VaultEntry(id: 'a', type: VaultEntryType.token, title: 'A'),
    );
    await service.enableEncryptedBackend('master');
    await service.disableEncryptedBackend();

    expect(service.isEncrypted, isFalse);
    expect(store.values, isNotEmpty);
    expect((await service.list()).single.id, 'a');
  });

  test('deleting removes the entry', () async {
    final service = buildService();
    await service.initialize();
    await service.upsert(
      const VaultEntry(id: 'a', type: VaultEntryType.token, title: 'A'),
    );
    await service.delete('a');
    expect(await service.list(), isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/vault_service_test.dart`
Expected: FAIL，找不到 `vault_service.dart`。

- [ ] **Step 3: 实现 VaultService**

```dart
// client/lib/services/vault/vault_service.dart
import 'dart:async';

import '../../models/vault_document.dart';
import '../../models/vault_entry.dart';
import 'encrypted_vault_backend.dart';
import 'keychain_vault_backend.dart';
import 'vault_errors.dart';

class VaultService {
  VaultService({
    required KeychainVaultBackend keychainBackend,
    required EncryptedVaultBackend encryptedBackend,
  }) : _keychainBackend = keychainBackend,
       _encryptedBackend = encryptedBackend;

  final KeychainVaultBackend _keychainBackend;
  final EncryptedVaultBackend _encryptedBackend;

  VaultDocument? _document;
  bool _encrypted = false;
  bool _locked = false;
  bool _initialized = false;
  Future<void>? _writeTail;

  bool get isEncrypted => _encrypted;

  bool get isLocked => _locked;

  bool get isUnlocked => !_locked;

  Future<void> initialize() async {
    if (_initialized) return;
    _encrypted = await _encryptedBackend.isInitialized;
    if (_encrypted) {
      _locked = true;
      _document = null;
      _initialized = true;
      return;
    }
    _locked = false;
    _document = await _keychainBackend.load();
    _initialized = true;
  }

  Future<void> unlock(String passphrase) async {
    if (!_encrypted) return;
    await _encryptedBackend.unlock(passphrase);
    _document = await _encryptedBackend.load();
    _locked = false;
  }

  void lock() {
    if (!_encrypted) return;
    _encryptedBackend.lock();
    _document = null;
    _locked = true;
  }

  Future<List<VaultEntry>> list({
    String query = '',
    VaultEntryType? type,
    Set<String> tags = const {},
  }) async {
    final document = _requireDocument();
    final needle = query.trim().toLowerCase();
    final matches = document.entries.where((entry) {
      if (type != null && entry.type != type) return false;
      if (tags.isNotEmpty && !tags.every(entry.tags.contains)) return false;
      if (needle.isEmpty) return true;
      if (entry.title.toLowerCase().contains(needle)) return true;
      if (entry.tags.any((tag) => tag.toLowerCase().contains(needle))) {
        return true;
      }
      return entry.fields.values.any(
        (value) => value.toLowerCase().contains(needle),
      );
    }).toList();
    matches.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return List.unmodifiable(matches);
  }

  Future<VaultEntry?> get(String id) async {
    for (final entry in _requireDocument().entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> upsert(VaultEntry entry) {
    return _mutate((document) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final normalized = entry.copyWith(
        createdAt: entry.createdAt == 0 ? now : entry.createdAt,
        updatedAt: now,
      );
      final entries = [...document.entries];
      final index = entries.indexWhere((e) => e.id == entry.id);
      if (index >= 0) {
        entries[index] = normalized;
      } else {
        entries.add(normalized);
      }
      return document.copyWith(entries: entries);
    });
  }

  Future<void> delete(String id) {
    return _mutate(
      (document) => document.copyWith(
        entries: [
          for (final entry in document.entries)
            if (entry.id != id) entry,
        ],
      ),
    );
  }

  Future<String?> readField(String entryId, String field) async {
    final entry = await get(entryId);
    final value = entry?.fields[field];
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> enableEncryptedBackend(String passphrase) async {
    if (_encrypted) throw const VaultStorageException('alreadyEncrypted');
    final document = _requireDocument();
    await _encryptedBackend.initialize(document, passphrase);
    await _keychainBackend.clear();
    _document = document;
    _encrypted = true;
    _locked = false;
  }

  Future<void> disableEncryptedBackend() async {
    if (!_encrypted) throw const VaultStorageException('notEncrypted');
    final document = _requireDocument();
    await _keychainBackend.save(document);
    final verified = await _keychainBackend.load();
    if (verified == null) {
      throw const VaultStorageException('keychainVerifyFailed');
    }
    await _encryptedBackend.clear();
    _document = verified;
    _encrypted = false;
    _locked = false;
  }

  VaultDocument _requireDocument() {
    if (_locked) throw const VaultLockedException();
    return _document ?? const VaultDocument();
  }

  Future<void> _mutate(VaultDocument Function(VaultDocument) update) {
    final previous = _writeTail ?? Future<void>.value();
    final next = previous.then((_) async {
      final document = update(_requireDocument());
      if (_encrypted) {
        await _encryptedBackend.save(document);
      } else {
        await _keychainBackend.save(document);
      }
      _document = document;
    });
    _writeTail = next.catchError((_) {});
    return next;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/vault/vault_service_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/vault/vault_service.dart client/test/services/vault/vault_service_test.dart
git commit -m "feat(vault): add vault service with backend switching"
```

---

## Task 6: VaultCubit 与引用反查

**Files:**
- Create: `client/lib/models/vault_reference.dart`
- Create: `client/lib/cubits/vault_cubit.dart`
- Test: `client/test/cubits/vault_cubit_test.dart`

**Interfaces:**
- Consumes: `VaultService`、`SshProfileRepository`、`AppProviderRepository`、`VaultReference`
- Produces:
  - `VaultReferenceKind { sshProfile, appProvider }`、`VaultReference({kind, id, label})`
  - `VaultState`（`status`、`entries`、`tags`、`query`、`typeFilter`、`tagFilter`、`selectedId`、`busy`、`errorMessage`）
  - `VaultCubit(service:, sshProfiles:, appProviders:)`，方法 `load`、`unlock`、`lock`、`setQuery`、`setTypeFilter`、`toggleTag`、`select`、`save`、`remove`、`enableEncryption`、`disableEncryption`、`referencesFor`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/cubits/vault_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/vault_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import '../support/in_memory_filesystem.dart';
import '../support/test_runtime_context.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  const crypto = VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1);

  late VaultCubit cubit;
  late SshProfileRepository sshRepo;

  setUp(() {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final service = VaultService(
      keychainBackend: KeychainVaultBackend(_FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: crypto,
      ),
    );
    sshRepo = SshProfileRepository(storage: fakeHomeStorage());
    cubit = VaultCubit(
      service: service,
      sshProfiles: sshRepo,
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
    );
  });

  tearDown(() => cubit.close());

  test('load exposes an unlocked keychain vault', () async {
    await cubit.load();
    expect(cubit.state.status, VaultStatus.ready);
    expect(cubit.state.entries, isEmpty);
  });

  test('save then search filters entries', () async {
    await cubit.load();
    await cubit.save(
      const VaultEntry(id: 'a', type: VaultEntryType.login, title: 'GitHub'),
    );
    await cubit.save(
      const VaultEntry(id: 'b', type: VaultEntryType.token, title: 'Stripe'),
    );
    expect(cubit.state.entries, hasLength(2));

    await cubit.setQuery('git');
    expect(cubit.state.entries.single.id, 'a');
  });

  test('referencesFor finds SSH profiles pointing at an entry', () async {
    await cubit.load();
    await cubit.save(
      const VaultEntry(id: 'a', type: VaultEntryType.sshPassword, title: 'A'),
    );
    await sshRepo.save(
      const SshProfile(
        id: 'p1',
        name: 'Server',
        host: 'example.com',
        username: 'u',
        vaultEntryId: 'a',
      ),
    );

    final refs = await cubit.referencesFor('a');
    expect(refs, hasLength(1));
    expect(refs.single.kind, VaultReferenceKind.sshProfile);
    expect(refs.single.label, 'Server');
  });
}
```

> `AppProviderRepository(storage: fakeHomeStorage())` 在测试里只用于读取；不涉及 provider 文件的用例不会创建文件。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/vault_cubit_test.dart`
Expected: FAIL，找不到 `cubits/vault_cubit.dart`。

- [ ] **Step 3: 实现引用模型与 cubit**

```dart
// client/lib/models/vault_reference.dart
import 'package:equatable/equatable.dart';

enum VaultReferenceKind { sshProfile, appProvider }

class VaultReference extends Equatable {
  const VaultReference({
    required this.kind,
    required this.id,
    required this.label,
  });

  final VaultReferenceKind kind;
  final String id;
  final String label;

  @override
  List<Object?> get props => [kind, id, label];
}
```

```dart
// client/lib/cubits/vault_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';
import '../models/vault_entry.dart';
import '../models/vault_reference.dart';
import '../repositories/app_provider_repository.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/vault/vault_errors.dart';
import '../services/vault/vault_service.dart';

enum VaultStatus { loading, ready, locked, error }

class VaultState extends Equatable {
  const VaultState({
    this.status = VaultStatus.loading,
    this.entries = const [],
    this.tags = const [],
    this.query = '',
    this.typeFilter,
    this.tagFilter = const {},
    this.selectedId,
    this.busy = false,
    this.errorMessage,
    this.encrypted = false,
    this.unlocked = true,
  });

  final VaultStatus status;
  final List<VaultEntry> entries;
  final List<String> tags;
  final String query;
  final VaultEntryType? typeFilter;
  final Set<String> tagFilter;
  final String? selectedId;
  final bool busy;
  final String? errorMessage;

  /// 当前后端是否为加密文件。
  final bool encrypted;

  /// 加密后端是否已解锁；钥匙串后端恒为 true。
  final bool unlocked;

  VaultEntry? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  VaultState copyWith({
    VaultStatus? status,
    List<VaultEntry>? entries,
    List<String>? tags,
    String? query,
    VaultEntryType? typeFilter,
    bool clearTypeFilter = false,
    Set<String>? tagFilter,
    String? selectedId,
    bool clearSelected = false,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
    bool? encrypted,
    bool? unlocked,
  }) {
    return VaultState(
      status: status ?? this.status,
      entries: entries ?? this.entries,
      tags: tags ?? this.tags,
      query: query ?? this.query,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      tagFilter: tagFilter ?? this.tagFilter,
      selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      encrypted: encrypted ?? this.encrypted,
      unlocked: unlocked ?? this.unlocked,
    );
  }

  @override
  List<Object?> get props => [
    status,
    entries,
    tags,
    query,
    typeFilter,
    tagFilter,
    selectedId,
    busy,
    errorMessage,
    encrypted,
    unlocked,
  ];
}

class VaultCubit extends Cubit<VaultState> {
  VaultCubit({
    required VaultService service,
    required SshProfileRepository sshProfiles,
    required AppProviderRepository appProviders,
  }) : _service = service,
       _sshProfiles = sshProfiles,
       _appProviders = appProviders,
       super(const VaultState());

  final VaultService _service;
  final SshProfileRepository _sshProfiles;
  final AppProviderRepository _appProviders;

  Future<void> load() async {
    emit(state.copyWith(status: VaultStatus.loading, clearError: true));
    try {
      await _service.initialize();
      if (_service.isLocked) {
        emit(
          state.copyWith(
            status: VaultStatus.locked,
            entries: const [],
            encrypted: true,
            unlocked: false,
          ),
        );
        return;
      }
      await _refresh();
      emit(
        state.copyWith(
          status: VaultStatus.ready,
          encrypted: _service.isEncrypted,
          unlocked: true,
        ),
      );
    } on VaultException catch (error) {
      emit(
        state.copyWith(
          status: VaultStatus.error,
          errorMessage: error.code,
          encrypted: _service.isEncrypted,
        ),
      );
    }
  }

  Future<void> unlock(String passphrase) async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _service.unlock(passphrase);
      await _refresh();
      emit(
        state.copyWith(
          status: VaultStatus.ready,
          busy: false,
          encrypted: true,
          unlocked: true,
        ),
      );
    } on VaultException catch (error) {
      emit(state.copyWith(busy: false, errorMessage: error.code));
    }
  }

  void lock() {
    _service.lock();
    emit(
      state.copyWith(
        status: VaultStatus.locked,
        entries: const [],
        clearSelected: true,
        encrypted: true,
        unlocked: false,
      ),
    );
  }

  Future<void> setQuery(String query) async {
    emit(state.copyWith(query: query));
    await _refreshEntries();
  }

  Future<void> setTypeFilter(VaultEntryType? type) async {
    emit(
      state.copyWith(
        typeFilter: type,
        clearTypeFilter: type == null,
      ),
    );
    await _refreshEntries();
  }

  Future<void> toggleTag(String tag) async {
    final tags = {...state.tagFilter};
    if (!tags.remove(tag)) tags.add(tag);
    emit(state.copyWith(tagFilter: tags));
    await _refreshEntries();
  }

  void select(String? id) {
    emit(
      id == null
          ? state.copyWith(clearSelected: true)
          : state.copyWith(selectedId: id),
    );
  }

  Future<void> save(VaultEntry entry) async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _service.upsert(entry);
      await _refresh();
      emit(state.copyWith(busy: false, selectedId: entry.id));
    } on VaultException catch (error) {
      emit(state.copyWith(busy: false, errorMessage: error.code));
    }
  }

  Future<void> remove(String id) async {
    await _service.delete(id);
    await _refresh();
    emit(state.copyWith(clearSelected: state.selectedId == id));
  }

  Future<void> enableEncryption(String passphrase) async {
    await _service.enableEncryptedBackend(passphrase);
    emit(
      state.copyWith(
        status: VaultStatus.ready,
        encrypted: true,
        unlocked: true,
      ),
    );
  }

  Future<void> disableEncryption() async {
    await _service.disableEncryptedBackend();
    emit(
      state.copyWith(
        status: VaultStatus.ready,
        encrypted: false,
        unlocked: true,
      ),
    );
  }

  Future<List<VaultReference>> referencesFor(String entryId) async {
    final profiles = await _sshProfiles.loadAll();
    final references = <VaultReference>[
      for (final profile in profiles)
        if (profile.vaultEntryId == entryId)
          VaultReference(
            kind: VaultReferenceKind.sshProfile,
            id: profile.id,
            label: profile.name,
          ),
    ];
    for (final cli in CliTool.values) {
      final providers = await _appProviders.loadProviders(cli);
      for (final provider in providers) {
        if (provider.credentialLink.trim() == 'vault:$entryId') {
          references.add(
            VaultReference(
              kind: VaultReferenceKind.appProvider,
              id: provider.id,
              label: provider.name,
            ),
          );
        }
      }
    }
    return references;
  }

  Future<void> _refresh() async {
    final all = await _service.list();
    emit(state.copyWith(tags: _collectTags(all)));
    await _refreshEntries();
  }

  Future<void> _refreshEntries() async {
    final entries = await _service.list(
      query: state.query,
      type: state.typeFilter,
      tags: state.tagFilter,
    );
    emit(state.copyWith(entries: entries));
  }

  List<String> _collectTags(List<VaultEntry> entries) {
    final tags = <String>{};
    for (final entry in entries) {
      tags.addAll(entry.tags);
    }
    final sorted = tags.toList()..sort();
    return List.unmodifiable(sorted);
  }
}
```

> `AppProviderRepository` 的读取方法是 `loadProviders(CliTool cli, {bool importCredentialsFromGlobal = false, bool reconcileCredentials = true})`（已确认）。测试里对每个 CLI 调用会产生空目录读取，不会失败。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/cubits/vault_cubit_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add client/lib/models/vault_reference.dart client/lib/cubits/vault_cubit.dart client/test/cubits/vault_cubit_test.dart
git commit -m "feat(vault): add vault cubit with reference lookup"
```

---

## Task 7: DI、路由、页面壳、状态卡与列表

**Files:**
- Modify: `client/lib/cubits/config_cubit.dart`
- Modify: `client/lib/router/app_router.dart`
- Modify: `client/lib/pages/config/config_workspace.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/main.dart`
- Create: `client/lib/pages/config/vault_config_section.dart`
- Create: `client/lib/pages/vault/vault_page.dart`
- Create: `client/lib/pages/vault/vault_status_section.dart`
- Create: `client/lib/pages/vault/vault_entry_list.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/vault/vault_page_test.dart`

**Interfaces:**
- Consumes: `VaultCubit`、`VaultState`、`VaultService`
- Produces: `VaultConfigSection({bool showHeading = true})`、`VaultPageBody`、`VaultStatusSection`、`VaultEntryList({ValueChanged<VaultEntry> onOpen})`

- [ ] **Step 1: 加 l10n 文案**

在 `client/lib/l10n/app_en.arb` 末尾（最后一个 key 之后）追加：

```json
  "vaultPageTitle": "Credential Vault",
  "vaultPageSubtitle": "SSH passwords, private keys and provider API keys",
  "vaultNewEntry": "New entry",
  "vaultSearchHint": "Search title, fields or tags",
  "vaultEmptyTitle": "No entries yet",
  "vaultEmptyHint": "Save SSH passwords, private keys or provider API keys here.",
  "vaultStatusKeychain": "System keychain · no unlock needed",
  "vaultStatusEncrypted": "Encrypted vault · locked",
  "vaultStatusUnlocked": "Encrypted vault · unlocked",
  "vaultUnlock": "Unlock",
  "vaultLock": "Lock now",
  "vaultEnableEncryption": "Enable encrypted vault",
  "vaultDisableEncryption": "Disable encrypted vault",
  "vaultUnlockTitle": "Unlock vault",
  "vaultPassphrase": "Master passphrase",
  "vaultPassphraseConfirm": "Confirm passphrase",
  "vaultPassphraseMismatch": "Passphrases do not match",
  "vaultPassphraseRequired": "Passphrase is required",
  "vaultUnlockFailed": "Could not unlock the vault",
  "vaultWrongPassphraseHint": "Wrong passphrase or damaged file. Data was not modified.",
  "vaultCopy": "Copy",
  "vaultReveal": "Reveal",
  "vaultHide": "Hide",
  "vaultCopied": "Copied",
  "vaultOnlyCopy": "Copy only",
  "vaultReferences": "Used by",
  "vaultNoReferences": "Not referenced yet",
  "vaultDeleteTitle": "Delete entry?",
  "vaultDeleteReferenced": "This entry is still used by:",
  "vaultDeleteConfirm": "Delete",
  "vaultCancel": "Cancel",
  "vaultSave": "Save",
  "vaultEntryTitle": "Title",
  "vaultEntryType": "Type",
  "vaultEntryTags": "Tags (comma separated)",
  "vaultEntryNotes": "Notes",
  "vaultEntryFavorite": "Favorite",
  "vaultTypeSshPassword": "SSH password",
  "vaultTypeSshPrivateKey": "SSH private key",
  "vaultTypeApiKey": "Provider API key",
  "vaultTypeLogin": "Login",
  "vaultTypeToken": "Token",
  "vaultTypeSecureNote": "Secure note",
  "vaultTypeCustom": "Custom"
```

在 `client/lib/l10n/app_zh.arb` 追加同名 key：

```json
  "vaultPageTitle": "保险库",
  "vaultPageSubtitle": "SSH 密码、私钥与供应商 API Key",
  "vaultNewEntry": "新建条目",
  "vaultSearchHint": "搜索标题、字段或标签",
  "vaultEmptyTitle": "还没有条目",
  "vaultEmptyHint": "在这里保存 SSH 密码、私钥或供应商 API Key。",
  "vaultStatusKeychain": "系统钥匙串 · 无需解锁",
  "vaultStatusEncrypted": "加密保险库 · 已锁定",
  "vaultStatusUnlocked": "加密保险库 · 已解锁",
  "vaultUnlock": "解锁",
  "vaultLock": "立即锁定",
  "vaultEnableEncryption": "启用加密保险库",
  "vaultDisableEncryption": "停用加密保险库",
  "vaultUnlockTitle": "解锁保险库",
  "vaultPassphrase": "主密码",
  "vaultPassphraseConfirm": "确认主密码",
  "vaultPassphraseMismatch": "两次输入的密码不一致",
  "vaultPassphraseRequired": "请输入主密码",
  "vaultUnlockFailed": "解锁失败",
  "vaultWrongPassphraseHint": "密码错误或文件损坏，数据未被修改。",
  "vaultCopy": "复制",
  "vaultReveal": "显示",
  "vaultHide": "隐藏",
  "vaultCopied": "已复制",
  "vaultOnlyCopy": "仅复制",
  "vaultReferences": "被引用",
  "vaultNoReferences": "尚未被引用",
  "vaultDeleteTitle": "删除条目？",
  "vaultDeleteReferenced": "该条目仍被以下位置使用：",
  "vaultDeleteConfirm": "删除",
  "vaultCancel": "取消",
  "vaultSave": "保存",
  "vaultEntryTitle": "标题",
  "vaultEntryType": "类型",
  "vaultEntryTags": "标签（逗号分隔）",
  "vaultEntryNotes": "备注",
  "vaultEntryFavorite": "收藏",
  "vaultTypeSshPassword": "SSH 密码",
  "vaultTypeSshPrivateKey": "SSH 私钥",
  "vaultTypeApiKey": "供应商 API Key",
  "vaultTypeLogin": "账号密码",
  "vaultTypeToken": "令牌",
  "vaultTypeSecureNote": "安全笔记",
  "vaultTypeCustom": "自定义"
```

Run: `cd client && flutter gen-l10n`
Expected: `app_localizations*.dart` 更新，无报错。

- [ ] **Step 2: 接路由与设置页**

`config_cubit.dart`：

```dart
enum ConfigSection {
  layout,
  session,
  cli,
  aiFeatures,
  sshProfiles,
  vault,
  connect,
  github,
  downloadSources,
  discovery,
  shortcuts,
  about,
  logs,
}
```

`title` 与 `breadcrumb` 各加一行：

```dart
    ConfigSection.vault => 'Credential Vault',
```

```dart
    ConfigSection.vault => 'Config / Credential Vault',
```

`routeSegment` 加：

```dart
    ConfigSection.vault => 'vault',
```

`app_router.dart`（`ssh-profiles` 路由之后）：

```dart
            GoRoute(
              path: '/config/vault',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ConfigWorkspace(section: ConfigSection.vault),
              ),
            ),
```

`app_keys.dart`：

```dart
  static const configVaultSectionButton = Key('config_vault_section_button');
```

`config_workspace.dart`：

1. 顶部 import 新 section：
```dart
import 'vault_config_section.dart';
```
2. `_configSectionDialogIndex` 整体改为（vault 插在 sshProfiles 之后，后续索引顺延）：
```dart
int _configSectionDialogIndex(ConfigSection section) {
  return switch (section) {
    ConfigSection.layout => 0,
    ConfigSection.session => 1,
    ConfigSection.cli => 2,
    ConfigSection.aiFeatures => 3,
    ConfigSection.sshProfiles => 4,
    ConfigSection.vault => 5,
    ConfigSection.connect => 6,
    ConfigSection.github => 7,
    ConfigSection.downloadSources => 8,
    ConfigSection.discovery => 9,
    ConfigSection.shortcuts => 10,
    ConfigSection.about => 11,
    ConfigSection.logs => 11,
  };
}
```
3. `SettingsDialogEntry` 列表（`SshProfilesConfigWorkspace` 之后）：
```dart
      SettingsDialogEntry(
        icon: Icons.lock_outline,
        navLabel: (l10n) => l10n.vaultPageTitle,
        title: (l10n) => l10n.vaultPageTitle,
        subtitle: (l10n) => l10n.vaultPageSubtitle,
        bodyBuilder: (_) => const VaultConfigSection(showHeading: false),
      ),
```
4. `body` switch：
```dart
        ConfigSection.vault => VaultConfigSection(showHeading: showHeading),
```
5. hub 入口列表（SSH 入口之后）：
```dart
        WorkspaceHubEntry(
          key: AppKeys.configVaultSectionButton,
          title: l10n.vaultPageTitle,
          icon: Icons.lock_outline,
          onTap: throttledTap('config_hub_vault', () {
            context.read<ConfigCubit>().selectSection(ConfigSection.vault);
            context.push('/config/${ConfigSection.vault.routeSegment}');
          }),
        ),
```
6. 侧栏导航列表（同位置重复一份）：
```dart
        WorkspaceHubEntry(
          key: AppKeys.configVaultSectionButton,
          title: l10n.vaultPageTitle,
          icon: Icons.lock_outline,
          selected: section == ConfigSection.vault,
          onTap: throttledTap(
            'config_nav_vault',
            () => onSelectSection(ConfigSection.vault),
          ),
        ),
```

- [ ] **Step 3: 写页面失败测试**

```dart
// client/test/pages/vault/vault_page_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/vault_cubit.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/pages/vault/vault_entry_list.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  testWidgets('lists entries and filters by query', (tester) async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final service = VaultService(
      keychainBackend: KeychainVaultBackend(_FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: const VaultCrypto(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      ),
    );
    final cubit = VaultCubit(
      service: service,
      sshProfiles: SshProfileRepository(storage: fakeHomeStorage()),
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
    );
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.save(
      const VaultEntry(id: 'a', type: VaultEntryType.login, title: 'GitHub'),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: VaultEntryList(onOpen: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
  });
}
```

- [ ] **Step 4: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/vault/vault_page_test.dart`
Expected: FAIL，找不到 `pages/vault/vault_entry_list.dart`。

- [ ] **Step 5: 实现页面壳、状态卡、列表**

```dart
// client/lib/pages/config/vault_config_section.dart
import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/settings/workspace_pane_header.dart';
import '../vault/vault_page.dart';

class VaultConfigSection extends StatelessWidget {
  const VaultConfigSection({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) WorkspacePaneHeader(title: context.l10n.vaultPageTitle),
        const Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: VaultPageBody(),
          ),
        ),
      ],
    );
  }
}
```

```dart
// client/lib/pages/vault/vault_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import 'vault_entry_detail.dart';
import 'vault_entry_editor.dart';
import 'vault_entry_list.dart';
import 'vault_status_section.dart';

class VaultPageBody extends StatelessWidget {
  const VaultPageBody({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<VaultCubit, VaultState>(
      builder: (context, state) {
        if (state.status == VaultStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const VaultStatusSection(),
            const SizedBox(height: 16),
            if (state.status == VaultStatus.locked)
              Text(l10n.vaultStatusEncrypted)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: l10n.vaultSearchHint,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: context.read<VaultCubit>().setQuery,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => showVaultEntryEditor(context),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.vaultNewEntry),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              VaultEntryList(
                onOpen: (entry) => showVaultEntryDetail(context, entry.id),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.vaultUnlockFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        );
      },
    );
  }
}
```

```dart
// client/lib/pages/vault/vault_status_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';

class VaultStatusSection extends StatelessWidget {
  const VaultStatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<VaultCubit, VaultState>(
      builder: (context, state) {
        final cubit = context.read<VaultCubit>();
        final locked = state.encrypted && !state.unlocked;
        final label = !state.encrypted
            ? l10n.vaultStatusKeychain
            : (locked ? l10n.vaultStatusEncrypted : l10n.vaultStatusUnlocked);
        return TpCard(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label),
              if (locked)
                FilledButton(
                  onPressed: () => showVaultUnlockDialog(context),
                  child: Text(l10n.vaultUnlock),
                )
              else if (state.encrypted) ...[
                OutlinedButton(
                  onPressed: cubit.lock,
                  child: Text(l10n.vaultLock),
                ),
                OutlinedButton(
                  onPressed: () => cubit.disableEncryption(),
                  child: Text(l10n.vaultDisableEncryption),
                ),
              ] else
                OutlinedButton(
                  onPressed: () => showVaultEnableEncryptionDialog(context),
                  child: Text(l10n.vaultEnableEncryption),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

> `TpCard` 支持 `padding` 与 `child`（已确认）。解锁/启用对话框与状态卡放在同一文件，避免跨任务引用未定义函数：

```dart
Future<void> showVaultUnlockDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<VaultCubit>();
  final controller = TextEditingController();
  final passphrase = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.vaultUnlockTitle),
      content: TpPasswordInput(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.vaultPassphrase),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.vaultCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(l10n.vaultUnlock),
        ),
      ],
    ),
  );
  controller.dispose();
  if (passphrase == null || passphrase.isEmpty) return;
  await cubit.unlock(passphrase);
}

Future<void> showVaultEnableEncryptionDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final cubit = context.read<VaultCubit>();
  final first = TextEditingController();
  final second = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.vaultEnableEncryption),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TpPasswordInput(
            controller: first,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.vaultPassphrase),
          ),
          const SizedBox(height: 12),
          TpPasswordInput(
            controller: second,
            decoration: InputDecoration(labelText: l10n.vaultPassphraseConfirm),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.vaultCancel),
        ),
        FilledButton(
          onPressed: () {
            if (first.text.isEmpty) return;
            if (first.text != second.text) return;
            Navigator.of(dialogContext).pop(true);
          },
          child: Text(l10n.vaultEnableEncryption),
        ),
      ],
    ),
  );
  final passphrase = first.text;
  first.dispose();
  second.dispose();
  if (confirmed != true || passphrase.isEmpty) return;
  await cubit.enableEncryption(passphrase);
}
```

需要 import `../../widgets/tp_password_input.dart`。

```dart
// client/lib/pages/vault/vault_entry_list.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/vault_entry.dart';

String vaultTypeLabel(AppLocalizations l10n, VaultEntryType type) =>
    switch (type) {
      VaultEntryType.sshPassword => l10n.vaultTypeSshPassword,
      VaultEntryType.sshPrivateKey => l10n.vaultTypeSshPrivateKey,
      VaultEntryType.apiKey => l10n.vaultTypeApiKey,
      VaultEntryType.login => l10n.vaultTypeLogin,
      VaultEntryType.token => l10n.vaultTypeToken,
      VaultEntryType.secureNote => l10n.vaultTypeSecureNote,
      VaultEntryType.custom => l10n.vaultTypeCustom,
    };

class VaultEntryList extends StatelessWidget {
  const VaultEntryList({required this.onOpen, super.key});

  final ValueChanged<VaultEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<VaultCubit, VaultState>(
      builder: (context, state) {
        if (state.entries.isEmpty) {
          return TpEmptyState(
            icon: Icons.lock_outline,
            title: l10n.vaultEmptyTitle,
            hint: l10n.vaultEmptyHint,
            centered: true,
          );
        }
        return Column(
          children: [
            for (final entry in state.entries)
              ListTile(
                key: Key('vault-entry-${entry.id}'),
                leading: Icon(
                  entry.favorite ? Icons.star : Icons.key_outlined,
                ),
                title: Text(entry.title),
                subtitle: Text(
                  '${vaultTypeLabel(l10n, entry.type)} · '
                  '${entry.fields['username'] ?? entry.fields['provider'] ?? ''}',
                ),
                onTap: () => onOpen(entry),
              ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 6: 接 DI**

`app_shell.dart`：在 `late final SshProfileCubit sshProfileCubit;` 附近声明

```dart
  late final VaultService vaultService;
  late final VaultCubit vaultCubit;
```

import：

```dart
import '../cubits/vault_cubit.dart';
import '../repositories/vault_repository.dart';
import '../services/vault/encrypted_vault_backend.dart';
import '../services/vault/keychain_vault_backend.dart';
import '../services/vault/vault_service.dart';
```

在 `sshCredentialStore` 定义之后（约 748 行）构造：

```dart
  vaultService = VaultService(
    keychainBackend: KeychainVaultBackend(const FlutterSecureKeyValueStore()),
    encryptedBackend: EncryptedVaultBackend(
      repository: deviceLocalVaultRepository(nativeAppDataPath),
    ),
  );
```

在 `sshProfileRepo`（789 行）之后构造 cubit（若此处 `homeStorage` 尚不可用，把下面这段移到 `homeStorage` 创建之后，约 1007 行；只要在 `AppShell(...)` 构造之前即可）：

```dart
  vaultCubit = VaultCubit(
    service: vaultService,
    sshProfiles: sshProfileRepo,
    appProviders: AppProviderRepository(storage: homeStorage),
  );
```

紧跟 `vaultService` 构造之后加一行，保证启动后 `readField` 立即可用（钥匙串模式读取一次；加密模式只做一次文件 stat 并进入锁定态）：

```dart
  await vaultService.initialize();
```

`main.dart` 的 provider 列表加：

```dart
                  RepositoryProvider<VaultService>.value(
                    value: shell.vaultService,
                  ),
                  BlocProvider.value(value: shell.vaultCubit),
```

并在 `main.dart` 顶部补 import：

```dart
import 'cubits/vault_cubit.dart';
import 'services/vault/vault_service.dart';
```

> `RepositoryProvider` 放进 `MultiRepositoryProvider.providers`，`BlocProvider.value` 放进
> `MultiBlocProvider.providers`（两者是不同列表，见 `main.dart` 现有结构）。

- [ ] **Step 7: 跑测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error（允许既有 info/warning）。

Run: `cd client && dart run tool/run_tests.dart test/pages/vault/vault_page_test.dart`
Expected: `All tests passed!`

- [ ] **Step 8: 提交**

```bash
git add client/lib client/test/pages/vault/vault_page_test.dart
git commit -m "feat(vault): add vault settings page, route and DI"
```

---

## Task 8: 条目详情、掩码揭示与剪贴板清理

**Files:**
- Create: `client/lib/pages/vault/vault_entry_detail.dart`
- Test: `client/test/pages/vault/vault_entry_detail_test.dart`

**Interfaces:**
- Consumes: `VaultCubit`、`VaultEntry`、`VaultReference`
- Produces:
  - `Future<void> showVaultEntryDetail(BuildContext context, String entryId)`
  - `VaultSecretField({required String label, required String value, required bool secret, bool revealable = true, Duration revealDuration = const Duration(seconds: 30)})`
  - `Future<void> copySecret(BuildContext context, String value, {Duration clearAfter = const Duration(seconds: 60)})`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/pages/vault/vault_entry_detail_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/vault/vault_entry_detail.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('secret field masks by default, reveals, then re-masks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const VaultSecretField(
          label: 'Password',
          value: 'hunter2',
          secret: true,
          revealDuration: Duration(seconds: 1),
        ),
      ),
    );

    expect(find.text('hunter2'), findsNothing);
    expect(find.textContaining('••'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.text('hunter2'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('hunter2'), findsNothing);
  });

  testWidgets('copy-only entries hide the reveal button', (tester) async {
    await tester.pumpWidget(
      _host(
        const VaultSecretField(
          label: 'Private key',
          value: 'PEM',
          secret: true,
          revealable: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/vault/vault_entry_detail_test.dart`
Expected: FAIL，找不到 `vault_entry_detail.dart`。

- [ ] **Step 3: 实现详情与安全字段**

```dart
// client/lib/pages/vault/vault_entry_detail.dart
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/vault_entry.dart';
import '../../models/vault_reference.dart';
import 'vault_entry_editor.dart';
import 'vault_entry_list.dart';

Future<void> showVaultEntryDetail(BuildContext context, String entryId) {
  return showDialog<void>(
    context: context,
    builder: (_) => VaultEntryDetailDialog(entryId: entryId),
  );
}

class VaultEntryDetailDialog extends StatefulWidget {
  const VaultEntryDetailDialog({required this.entryId, super.key});

  final String entryId;

  @override
  State<VaultEntryDetailDialog> createState() => _VaultEntryDetailDialogState();
}

class _VaultEntryDetailDialogState extends State<VaultEntryDetailDialog> {
  List<VaultReference> _references = const [];

  @override
  void initState() {
    super.initState();
    _loadReferences();
  }

  Future<void> _loadReferences() async {
    final references = await context.read<VaultCubit>().referencesFor(
      widget.entryId,
    );
    if (mounted) setState(() => _references = references);
  }

  Future<void> _delete(VaultEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.vaultDeleteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_references.isNotEmpty) ...[
              Text(l10n.vaultDeleteReferenced),
              for (final reference in _references)
                Text('• ${reference.label}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.vaultCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.vaultDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<VaultCubit>().remove(entry.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entry = context.select<VaultCubit, VaultEntry?>(
      (cubit) => cubit.state.entries
          .where((candidate) => candidate.id == widget.entryId)
          .firstOrNull,
    );
    if (entry == null) {
      return AlertDialog(
        content: Text(l10n.vaultEmptyTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.vaultCancel),
          ),
        ],
      );
    }

    final fields = entry.fields.entries
        .where((field) => field.value.isNotEmpty)
        .toList();

    return AlertDialog(
      title: Text(entry.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(vaultTypeLabel(l10n, entry.type)),
              const SizedBox(height: 12),
              for (final field in fields) ...[
                VaultSecretField(
                  label: field.key,
                  value: field.value,
                  secret: entry.isSecretField(field.key),
                  revealable: entry.revealAllowed,
                ),
                const SizedBox(height: 8),
              ],
              if (entry.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(l10n.vaultEntryNotes),
                Text(entry.notes),
              ],
              const SizedBox(height: 16),
              Text(
                l10n.vaultReferences,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_references.isEmpty)
                Text(l10n.vaultNoReferences)
              else
                for (final reference in _references)
                  Text('• ${reference.label}'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showVaultEntryEditor(context, existing: entry),
          child: Text(l10n.vaultSave),
        ),
        TextButton(
          onPressed: () => _delete(entry),
          child: Text(l10n.vaultDeleteConfirm),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.vaultCancel),
        ),
      ],
    );
  }
}

class VaultSecretField extends StatefulWidget {
  const VaultSecretField({
    required this.label,
    required this.value,
    required this.secret,
    this.revealable = true,
    this.revealDuration = const Duration(seconds: 30),
    super.key,
  });

  final String label;
  final String value;
  final bool secret;
  final bool revealable;
  final Duration revealDuration;

  @override
  State<VaultSecretField> createState() => _VaultSecretFieldState();
}

class _VaultSecretFieldState extends State<VaultSecretField> {
  Timer? _hideTimer;
  bool _revealed = false;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleReveal() {
    setState(() => _revealed = !_revealed);
    _hideTimer?.cancel();
    if (_revealed) {
      _hideTimer = Timer(widget.revealDuration, () {
        if (mounted) setState(() => _revealed = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = !widget.secret || _revealed;
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(labelText: widget.label),
            child: SelectableText(visible ? widget.value : '••••••••'),
          ),
        ),
        if (widget.secret && widget.revealable)
          IconButton(
            tooltip: _revealed ? l10n.vaultHide : l10n.vaultReveal,
            icon: Icon(
              _revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            ),
            onPressed: _toggleReveal,
          ),
        if (widget.secret)
          IconButton(
            tooltip: l10n.vaultCopy,
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => copySecret(context, widget.value),
          ),
      ],
    );
  }
}

Future<void> copySecret(
  BuildContext context,
  String value, {
  Duration clearAfter = const Duration(seconds: 60),
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  await Clipboard.setData(ClipboardData(text: value));
  messenger?.showSnackBar(
    SnackBar(
      content: Text(l10n.vaultCopied),
      duration: const Duration(seconds: 2),
    ),
  );
  Timer(clearAfter, () async {
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == value) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  });
}
```

- [ ] **Step 4: 跑测试**

Run: `cd client && dart run tool/run_tests.dart test/pages/vault/vault_entry_detail_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add client/lib/pages/vault/vault_entry_detail.dart client/test/pages/vault/vault_entry_detail_test.dart
git commit -m "feat(vault): add entry detail with masked reveal and clipboard clear"
```

---

## Task 9: 条目编辑对话框

**Files:**
- Create: `client/lib/pages/vault/vault_entry_editor.dart`
- Test: `client/test/pages/vault/vault_entry_editor_test.dart`

**Interfaces:**
- Consumes: `VaultCubit`、`VaultEntry`、`vaultTypeLabel`
- Produces: `Future<void> showVaultEntryEditor(BuildContext context, {VaultEntry? existing})`、`VaultEntryEditorDialog`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/pages/vault/vault_entry_editor_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/vault_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/vault/vault_entry_editor.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  testWidgets('saves a new entry with a title and secret field', (
    tester,
  ) async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final cubit = VaultCubit(
      service: VaultService(
        keychainBackend: KeychainVaultBackend(_FakeStore()),
        encryptedBackend: EncryptedVaultBackend(
          repository: VaultRepository(rootDir: '/root/vault', fs: fs),
          crypto: const VaultCrypto(
            memoryKiB: 256,
            iterations: 1,
            parallelism: 1,
          ),
        ),
      ),
      sshProfiles: SshProfileRepository(storage: fakeHomeStorage()),
      appProviders: AppProviderRepository(storage: fakeHomeStorage()),
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: VaultEntryEditorDialog()),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('vault-editor-title')),
      'OpenAI',
    );
    await tester.tap(find.byKey(const Key('vault-editor-save')));
    await tester.pumpAndSettle();

    expect(cubit.state.entries.single.title, 'OpenAI');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/vault/vault_entry_editor_test.dart`
Expected: FAIL，找不到 `vault_entry_editor.dart`。

- [ ] **Step 3: 实现编辑器**

```dart
// client/lib/pages/vault/vault_entry_editor.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/vault_cubit.dart';
import '../../l10n/app_localizations.dart';
import '../../models/vault_entry.dart';
import 'vault_entry_list.dart';

Future<void> showVaultEntryEditor(
  BuildContext context, {
  VaultEntry? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => VaultEntryEditorDialog(existing: existing),
  );
}

class VaultEntryEditorDialog extends StatefulWidget {
  const VaultEntryEditorDialog({this.existing, super.key});

  final VaultEntry? existing;

  @override
  State<VaultEntryEditorDialog> createState() => _VaultEntryEditorDialogState();
}

class _VaultEntryEditorDialogState extends State<VaultEntryEditorDialog> {
  static const _uuid = Uuid();

  late VaultEntryType _type;
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  final _fields = <String, TextEditingController>{};
  late bool _favorite;
  late bool _revealable;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? VaultEntryType.sshPassword;
    _title = TextEditingController(text: existing?.title ?? '');
    _tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _favorite = existing?.favorite ?? false;
    _revealable = existing?.revealable ?? true;
    _syncFields(existing?.fields ?? const {});
  }

  void _syncFields(Map<String, String> values) {
    final names = {..._type.defaultFields, ...values.keys};
    for (final name in names) {
      _fields.putIfAbsent(
        name,
        () => TextEditingController(text: values[name] ?? ''),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _notes.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final cubit = context.read<VaultCubit>();
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final existing = widget.existing;
    final entry = VaultEntry(
      id: existing?.id ?? _uuid.v4(),
      type: _type,
      title: title,
      fields: {
        for (final field in _fields.entries)
          if (field.value.text.isNotEmpty) field.key: field.value.text,
      },
      tags: _tags.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(),
      notes: _notes.text.trim(),
      favorite: _favorite,
      revealable: _revealable,
      createdAt: existing?.createdAt ?? 0,
      updatedAt: existing?.updatedAt ?? 0,
      extra: existing?.extra ?? const {},
    );
    await cubit.save(entry);
    if (mounted) await Navigator.of(context).maybePop();
    messenger?.showSnackBar(SnackBar(content: Text(l10n.vaultSave)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.existing == null ? l10n.vaultNewEntry : widget.existing!.title,
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpInput(
                key: const Key('vault-editor-title'),
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(labelText: l10n.vaultEntryTitle),
              ),
              const SizedBox(height: 12),
              TpSelect<VaultEntryType>(
                items: VaultEntryType.values,
                initialItem: _type,
                itemLabel: (type) => vaultTypeLabel(l10n, type),
                onChanged: (type) {
                  if (type == null) return;
                  setState(() {
                    _type = type;
                    _syncFields(
                      {for (final f in _fields.entries) f.key: f.value.text},
                    );
                  });
                },
                decoration: TpSelectDecorations.themed(context),
                overlayHeight: kTpSelectDefaultOverlayHeight,
              ),
              const SizedBox(height: 12),
              for (final field in _fields.entries) ...[
                TpPasswordInput(
                  key: Key('vault-editor-field-${field.key}'),
                  controller: field.value,
                  decoration: InputDecoration(labelText: field.key),
                ),
                const SizedBox(height: 8),
              ],
              TpInput(
                controller: _tags,
                decoration: InputDecoration(labelText: l10n.vaultEntryTags),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.vaultEntryNotes),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.vaultEntryFavorite),
                value: _favorite,
                onChanged: (value) => setState(() => _favorite = value),
              ),
              if (_type != VaultEntryType.sshPrivateKey)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.vaultOnlyCopy),
                  value: !_revealable,
                  onChanged: (value) => setState(() => _revealable = !value),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.vaultCancel),
        ),
        FilledButton(
          key: const Key('vault-editor-save'),
          onPressed: _save,
          child: Text(l10n.vaultSave),
        ),
      ],
    );
  }
}
```

> `TpInput` 是单行输入（内部固定 `maxLines: 1`），备注用 `TextField`；`kTpSelectDefaultOverlayHeight` 由 `shared_ui` 导出。

- [ ] **Step 4: 跑测试**

Run: `cd client && dart run tool/run_tests.dart test/pages/vault/vault_entry_editor_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: 提交**

```bash
git add client/lib/pages/vault/vault_entry_editor.dart client/test/pages/vault/vault_entry_editor_test.dart
git commit -m "feat(vault): add vault entry editor"
```

---

## Task 10: SSH 引用（模型 + 连接解析）

**Files:**
- Modify: `client/lib/models/ssh_profile.dart`
- Modify: `client/lib/services/ssh/ssh_client_factory.dart`
- Test: `client/test/models/ssh_profile_vault_test.dart`
- Test: `client/test/services/ssh/ssh_vault_credentials_test.dart`

**Interfaces:**
- Consumes: `VaultService.readField`
- Produces:
  - `SshProfile.vaultEntryId`（`String?`，`toJson` 为空不写）
  - `typedef VaultCredentialReader = Future<String?> Function(String entryId, String field);`
  - `SshClientFactory({..., VaultCredentialReader? vaultCredentials})`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/models/ssh_profile_vault_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';

void main() {
  test('vaultEntryId round-trips', () {
    const profile = SshProfile(
      id: 'p1',
      name: 'Server',
      host: 'example.com',
      username: 'u',
      vaultEntryId: 'v1',
    );
    expect(SshProfile.fromJson(profile.toJson()).vaultEntryId, 'v1');
  });

  test('missing vaultEntryId stays null and is not serialized', () {
    const profile = SshProfile(
      id: 'p1',
      name: 'Server',
      host: 'example.com',
      username: 'u',
    );
    final json = profile.toJson();
    expect(json.containsKey('vaultEntryId'), isFalse);
    expect(SshProfile.fromJson(json).vaultEntryId, isNull);
  });
}
```

```dart
// client/test/services/ssh/ssh_vault_credentials_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/ssh_credentials_resolver.dart';

void main() {
  const profile = SshProfile(
    id: 'p1',
    name: 'Server',
    host: 'example.com',
    username: 'u',
    vaultEntryId: 'v1',
  );

  test('vault entry wins over the legacy store', () async {
    final resolved = await resolveSshCredentials(
      profile,
      vault: (entryId, field) async =>
          entryId == 'v1' && field == 'password' ? 'from-vault' : null,
      legacyPassword: (_) async => 'from-keychain',
      legacyPrivateKey: (_) async => 'legacy-pem',
      legacyPassphrase: (_) async => 'legacy-pass',
    );
    expect(resolved.password, 'from-vault');
    expect(resolved.privateKey, isNull);
  });

  test('legacy store is used when no vault entry is linked', () async {
    const legacy = SshProfile(
      id: 'p2',
      name: 'Legacy',
      host: 'example.com',
      username: 'u',
    );
    final resolved = await resolveSshCredentials(
      legacy,
      vault: (_, __) async => 'from-vault',
      legacyPassword: (_) async => 'from-keychain',
      legacyPrivateKey: (_) async => 'legacy-pem',
      legacyPassphrase: (_) async => 'legacy-pass',
    );
    expect(resolved.password, 'from-keychain');
  });

  test('vault private key and passphrase resolve together', () async {
    const keyProfile = SshProfile(
      id: 'p3',
      name: 'Key',
      host: 'example.com',
      username: 'u',
      authType: SshAuthType.privateKey,
      vaultEntryId: 'v1',
    );
    final resolved = await resolveSshCredentials(
      keyProfile,
      vault: (entryId, field) async => switch (field) {
        'privateKey' => 'vault-pem',
        'passphrase' => 'vault-pass',
        _ => null,
      },
      legacyPassword: (_) async => null,
      legacyPrivateKey: (_) async => null,
      legacyPassphrase: (_) async => null,
    );
    expect(resolved.privateKey, 'vault-pem');
    expect(resolved.passphrase, 'vault-pass');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/ssh_profile_vault_test.dart test/services/ssh/ssh_vault_credentials_test.dart`
Expected: FAIL，`vaultEntryId` 未定义 / 找不到 `ssh_credentials_resolver.dart`。

- [ ] **Step 3: 扩 SshProfile**

在构造函数加 `this.vaultEntryId,`（`embeddedTarget` 之后），字段：

```dart
  /// 非空时从保险库条目读取密码/私钥，优先于钥匙串。
  final String? vaultEntryId;
```

`fromJson` 里加：

```dart
      vaultEntryId: json['vaultEntryId']?.toString(),
```

`toJson`（找到现有 map）加：

```dart
      if (vaultEntryId != null && vaultEntryId!.isNotEmpty)
        'vaultEntryId': vaultEntryId,
```

`copyWith` 参数加 `String? vaultEntryId`，构造里 `vaultEntryId: vaultEntryId ?? this.vaultEntryId,`。

- [ ] **Step 4: 实现解析器**

```dart
// client/lib/services/ssh/ssh_credentials_resolver.dart
import '../../models/ssh_profile.dart';

typedef VaultCredentialReader =
    Future<String?> Function(String entryId, String field);

class ResolvedSshCredentials {
  const ResolvedSshCredentials({this.password, this.privateKey, this.passphrase});

  final String? password;
  final String? privateKey;
  final String? passphrase;
}

/// 显式的凭据来源优先级：`vaultEntryId` > 钥匙串。
Future<ResolvedSshCredentials> resolveSshCredentials(
  SshProfile profile, {
  VaultCredentialReader? vault,
  required Future<String?> Function(String profileId) legacyPassword,
  required Future<String?> Function(String profileId) legacyPrivateKey,
  required Future<String?> Function(String profileId) legacyPassphrase,
}) async {
  final entryId = profile.vaultEntryId;
  final useVault = entryId != null && entryId.isNotEmpty && vault != null;

  switch (profile.authType) {
    case SshAuthType.password:
      final password = useVault
          ? await vault(entryId, 'password')
          : await legacyPassword(profile.id);
      return ResolvedSshCredentials(password: password);
    case SshAuthType.privateKey:
      final privateKey = useVault
          ? await vault(entryId, 'privateKey')
          : await legacyPrivateKey(profile.id);
      final passphrase = useVault
          ? await vault(entryId, 'passphrase')
          : await legacyPassphrase(profile.id);
      return ResolvedSshCredentials(
        privateKey: privateKey,
        passphrase: passphrase,
      );
  }
}
```

- [ ] **Step 5: 接入 SshClientFactory**

构造参数加：

```dart
    VaultCredentialReader? vaultCredentials,
```

并在构造初始化列表加 `_vaultCredentials = vaultCredentials,`；字段：

```dart
  final VaultCredentialReader? _vaultCredentials;
```

`_openClient` 里把两段读取替换为：

```dart
    final resolved = await resolveSshCredentials(
      profile,
      vault: _vaultCredentials,
      legacyPassword: _credentialStore.loadPassword,
      legacyPrivateKey: _credentialStore.loadPrivateKey,
      legacyPassphrase: _credentialStore.loadPrivateKeyPassphrase,
    );

    switch (profile.authType) {
      case SshAuthType.password:
        final password = resolved.password ?? '';
        return SSHClient(
          // ... 保持现有参数不变 ...
          onPasswordRequest: () => password,
        );
      case SshAuthType.privateKey:
        final privateKey = resolved.privateKey;
        if (privateKey == null || privateKey.isEmpty) {
          throw StateError('Private key not found for profile ${profile.id}');
        }
        final passphrase = resolved.passphrase;
        final identities = SSHKeyPair.fromPem(
          privateKey,
          passphrase == null || passphrase.isEmpty ? null : passphrase,
        );
        return SSHClient(
          // ... 保持现有参数不变 ...
          identities: identities,
        );
    }
```

`app_shell.dart` 构造 factory 时加：

```dart
    vaultCredentials: (entryId, field) => vaultService.readField(entryId, field),
```

> `vaultService` 必须在 factory 之前构造完成（Task 7 已放置在 `sshCredentialStore` 之后）。

- [ ] **Step 6: 跑测试**

Run: `cd client && dart run tool/run_tests.dart test/models/ssh_profile_vault_test.dart test/services/ssh/ssh_vault_credentials_test.dart`
Expected: `All tests passed!`

- [ ] **Step 7: 提交**

```bash
git add client/lib/models/ssh_profile.dart client/lib/services/ssh/ssh_credentials_resolver.dart client/lib/services/ssh/ssh_client_factory.dart client/lib/app/app_shell.dart client/test/models/ssh_profile_vault_test.dart client/test/services/ssh/ssh_vault_credentials_test.dart
git commit -m "feat(vault): resolve SSH credentials from linked vault entries"
```

---

## Task 11: SSH 表单、列表与单条迁移

**Files:**
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`
- Modify: `client/lib/pages/ssh_profile_setup_page.dart`
- Modify: `client/lib/pages/ssh_profiles/ssh_profiles_section.dart`
- Modify: `client/lib/cubits/ssh_profile_cubit.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/ssh_profiles/ssh_vault_link_test.dart`

**Interfaces:**
- Consumes: `VaultCubit`、`VaultService`、`SshCredentialStore`、`SshProfileRepository`
- Produces:
  - `SshProfileCubit.migrateToVault(String profileId)`（返回 `String?` 新条目 id）
  - 表单「凭据来源」字段与「保存到保险库」勾选

- [ ] **Step 1: 写失败测试（cubit 迁移）**

```dart
// client/test/pages/ssh_profiles/ssh_vault_link_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/keychain_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

class _FakeStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('migration copies the password and only then clears the keychain', () async {
    final sshStore = InMemorySshCredentialStore();
    final profileRepo = SshProfileRepository(storage: fakeHomeStorage());
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final vault = VaultService(
      keychainBackend: KeychainVaultBackend(_FakeStore()),
      encryptedBackend: EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: const VaultCrypto(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
      ),
    );
    await vault.initialize();

    const profile = SshProfile(
      id: 'p1',
      name: 'Server',
      host: 'example.com',
      username: 'u',
    );
    await profileRepo.save(profile);
    await sshStore.savePassword('p1', 'secret');

    final cubit = SshProfileCubit(
      profileRepository: profileRepo,
      credentialStore: sshStore,
      vaultService: vault,
    );
    addTearDown(cubit.close);
    await cubit.load();

    final entryId = await cubit.migrateToVault('p1');
    expect(entryId, isNotNull);
    expect(await vault.readField(entryId!, 'password'), 'secret');

    final migrated = (await profileRepo.loadAll()).single;
    expect(migrated.vaultEntryId, entryId);
    expect(await sshStore.loadPassword('p1'), isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_vault_link_test.dart`
Expected: FAIL，`SshProfileCubit` 没有 `vaultService` / `migrateToVault`。

- [ ] **Step 3: 给 cubit 加迁移**

构造参数加 `VaultService? vaultService`，字段 `final VaultService? _vaultService;`。

方法：

```dart
  /// 把钥匙串里的单条凭据复制进保险库，成功后才清除旧值。
  Future<String?> migrateToVault(String profileId) async {
    final vault = _vaultService;
    if (vault == null) return null;
    final profile = state.profiles.where((p) => p.id == profileId).firstOrNull;
    if (profile == null || (profile.vaultEntryId ?? '').isNotEmpty) {
      return profile?.vaultEntryId;
    }

    final fields = <String, String>{};
    if (profile.authType == SshAuthType.password) {
      final password = await _credentialStore.loadPassword(profileId);
      if (password == null || password.isEmpty) return null;
      fields['password'] = password;
    } else {
      final privateKey = await _credentialStore.loadPrivateKey(profileId);
      if (privateKey == null || privateKey.isEmpty) return null;
      fields['privateKey'] = privateKey;
      final passphrase = await _credentialStore.loadPrivateKeyPassphrase(
        profileId,
      );
      if (passphrase != null && passphrase.isNotEmpty) {
        fields['passphrase'] = passphrase;
      }
    }

    final entry = VaultEntry(
      id: const Uuid().v4(),
      type: profile.authType == SshAuthType.password
          ? VaultEntryType.sshPassword
          : VaultEntryType.sshPrivateKey,
      title: profile.name,
      fields: {
        'host': profile.host,
        'port': '${profile.port}',
        'username': profile.username,
        ...fields,
      },
      revealable: profile.authType == SshAuthType.password,
    );
    await vault.upsert(entry);

    final updated = profile.copyWith(vaultEntryId: entry.id);
    await _profileRepository.save(updated);
    await _credentialStore.deleteAll(profileId);
    await load();
    return entry.id;
  }
```

需要 import `package:uuid/uuid.dart`、`../models/vault_entry.dart`、`../services/vault/vault_service.dart`。

- [ ] **Step 4: 表单加「凭据来源」与「保存到保险库」**

先在 `app_en.arb` / `app_zh.arb` 追加文案（Task 7 的 key 之后）：

```json
  "sshCredentialSource": "Credentials",
  "sshCredentialSourceKeychain": "This device's keychain",
  "sshCredentialVaultDeleted": "Deleted vault entry",
  "sshSaveToVault": "Save to vault",
  "sshMigrateToVault": "Move to vault",
  "sshVaultBadge": "Vault"
```

```json
  "sshCredentialSource": "凭据来源",
  "sshCredentialSourceKeychain": "本机钥匙串",
  "sshCredentialVaultDeleted": "已删除的条目",
  "sshSaveToVault": "保存到保险库",
  "sshMigrateToVault": "迁移到保险库",
  "sshVaultBadge": "保险库"
```

Run: `cd client && flutter gen-l10n`

`ssh_profile_form_dialog.dart`：

1. `initState` 里异步加载 `List<VaultEntry> _vaultEntries = const [];`：

```dart
  Future<void> _loadVaultEntries() async {
    final type = _usesPasswordAuth
        ? VaultEntryType.sshPassword
        : VaultEntryType.sshPrivateKey;
    final entries = await context.read<VaultService>().list(type: type);
    if (mounted) setState(() => _vaultEntries = entries);
  }
```

并在 `initState` 末尾 `unawaited(_loadVaultEntries())`（`dart:async` 已可用或补 import）。

2. state 增加：

```dart
  String? _vaultEntryId;
  bool _saveToVault = false;
```

`initState` 里初始化 `_vaultEntryId = widget.existing?.vaultEntryId;`。

3. 在密码/私钥字段上方插入：

```dart
              TpSelect<String>(
                key: const Key('ssh-credential-source'),
                items: ['', ..._vaultEntries.map((entry) => entry.id)],
                initialItem: _vaultEntryId ?? '',
                itemLabel: (id) {
                  if (id.isEmpty) return context.l10n.sshCredentialSourceKeychain;
                  for (final entry in _vaultEntries) {
                    if (entry.id == id) return entry.title;
                  }
                  return context.l10n.sshCredentialVaultDeleted;
                },
                onChanged: (id) => setState(() {
                  _vaultEntryId = (id == null || id.isEmpty) ? null : id;
                  if (_vaultEntryId != null) _saveToVault = false;
                }),
                decoration: TpSelectDecorations.themed(context),
                overlayHeight: kTpSelectDefaultOverlayHeight,
              ),
              const SizedBox(height: 12),
```

并在「本机钥匙串」模式下、密码框下方显示勾选：

```dart
              if ((_vaultEntryId ?? '').isEmpty)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.sshSaveToVault),
                  value: _saveToVault,
                  onChanged: (value) =>
                      setState(() => _saveToVault = value ?? false),
                ),
```

4. `_buildProfile` 的 `SshProfile(...)` 加：

```dart
      vaultEntryId: _vaultEntryId,
```

5. `_persistCredentials` 开头加：

```dart
    // 已链接保险库条目的 profile 不再写钥匙串。
    if ((profile.vaultEntryId ?? '').isNotEmpty) return;
```

6. `_save` 在 `_persistCredentials` 成功之后加：

```dart
    if (credentialsSaved &&
        _saveToVault &&
        (profile.vaultEntryId ?? '').isEmpty) {
      await context.read<SshProfileCubit>().migrateToVault(profile.id);
    }
```

7. `_testConnection`：当选择了保险库条目时，从保险库取测试凭据：

```dart
      if ((_vaultEntryId ?? '').isNotEmpty) {
        final vault = context.read<VaultService>();
        if (_usesPasswordAuth) {
          password = await vault.readField(_vaultEntryId!, 'password');
        } else {
          privateKey = await vault.readField(_vaultEntryId!, 'privateKey');
          passphrase = await vault.readField(_vaultEntryId!, 'passphrase');
        }
      } else if (_usesPasswordAuth) { ... 原逻辑 ... }
```

Android 全页版 `ssh_profile_setup_page.dart` 按同一逻辑改（两处必须一致；可把上述字段抽成
`ssh_profile_vault_fields.dart` 小组件复用）。

- [ ] **Step 5: 列表显示与迁移按钮**

`ssh_profiles_section.dart` 的 profile 行加副标题/按钮：

```dart
            if ((profile.vaultEntryId ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 14),
                    const SizedBox(width: 4),
                    Text(context.l10n.sshVaultBadge),
                  ],
                ),
              )
            else if (profile.authType == SshAuthType.password)
              TextButton(
                onPressed: () => context
                    .read<SshProfileCubit>()
                    .migrateToVault(profile.id),
                child: Text(context.l10n.sshMigrateToVault),
              ),
```

补 import：两个 SSH 表单页加
`import '../../services/vault/vault_service.dart';` 与 `import '../../models/vault_entry.dart';`；
列表页确认已 import `l10n_extensions.dart`。

- [ ] **Step 6: 跑测试与 analyze**

Run: `cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_vault_link_test.dart`
Expected: `All tests passed!`

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error。

- [ ] **Step 7: 提交**

```bash
git add client/lib/cubits/ssh_profile_cubit.dart client/lib/pages/ssh_profile_setup_page.dart client/lib/pages/ssh_profiles client/lib/l10n client/test/pages/ssh_profiles/ssh_vault_link_test.dart
git commit -m "feat(vault): link SSH profiles to vault entries and migrate secrets"
```

---

## Task 12: 供应商 `vault:` 引用

**Files:**
- Create: `client/lib/services/vault/provider_credential_link.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/widgets/app_provider/app_provider_form_sheet.dart`
- Test: `client/test/app/provider_vault_link_test.dart`

**Interfaces:**
- Consumes: `VaultService.readField`、`AppProviderConfig.credentialLink`
- Produces: `credentialLink` 值 `vault:<entryId>`；`appProviderLinkedCredentialLookup` 支持前缀

- [ ] **Step 1: 写失败测试**

```dart
// client/test/app/provider_vault_link_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/vault/provider_credential_link.dart';

void main() {
  test('parses vault entry links', () {
    expect(vaultEntryIdFromCredentialLink('vault:a'), 'a');
    expect(vaultEntryIdFromCredentialLink('  vault:b  '), 'b');
  });

  test('rejects other links and empty ids', () {
    expect(vaultEntryIdFromCredentialLink('managed-1'), isNull);
    expect(vaultEntryIdFromCredentialLink('vault:'), isNull);
    expect(vaultEntryIdFromCredentialLink(''), isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/app/provider_vault_link_test.dart`
Expected: FAIL，找不到 `services/vault/provider_credential_link.dart`。

- [ ] **Step 3: 实现链接解析并接线 lookup**

```dart
// client/lib/services/vault/provider_credential_link.dart
const vaultCredentialLinkPrefix = 'vault:';

/// 从 `AppProviderConfig.credentialLink` 取出保险库条目 id。
///
/// 非保险库链接（托管供应商 id）返回 null。
String? vaultEntryIdFromCredentialLink(String link) {
  final trimmed = link.trim();
  if (!trimmed.startsWith(vaultCredentialLinkPrefix)) return null;
  final id = trimmed.substring(vaultCredentialLinkPrefix.length);
  return id.isEmpty ? null : id;
}
```

`app_shell.dart` 的 `appProviderLinkedCredentialLookup`：

```dart
  Future<String?> appProviderLinkedCredentialLookup(String link) async {
    final vaultEntryId = vaultEntryIdFromCredentialLink(link);
    if (vaultEntryId != null) {
      try {
        return await vaultService.readField(vaultEntryId, 'apiKey');
      } on Object {
        return null;
      }
    }
    final trimmed = link.trim();
    final entries = await resolvedManagedProviderRepository.load();
    final entry = entries.where((e) => e.id == trimmed).firstOrNull;
    if (entry == null) return null;
    final ref = entry.credentialRef?.trim();
    if (ref == null || ref.isEmpty) return null;
    final scope = await resolvedManagedProviderSecretStore.read(ref);
    final field = entry.endpointConfig.credentialField ?? 'apiKey';
    final value = scope.valueFor(field);
    return (value == null || value.isEmpty) ? null : value;
  }
```

两个文件补 import：

```dart
// app_shell.dart
import '../services/vault/provider_credential_link.dart';
// app_provider_form_sheet.dart
import '../../services/vault/provider_credential_link.dart';
```

- [ ] **Step 4: 表单选项与 label**

`app_provider_form_sheet.dart`：

1. 顶部 import：

```dart
import '../../models/vault_entry.dart';
import '../../services/vault/vault_service.dart';
```

2. state 加 `List<VaultEntry> _vaultEntries = const [];`，在 `initState` 末尾安全读取（测试里可能没有 provider）：

```dart
  VaultService? _vaultOf(BuildContext context) {
    try {
      return context.read<VaultService>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _loadVaultEntries() async {
    final vault = _vaultOf(context);
    if (vault == null) return;
    final entries = await vault.list(type: VaultEntryType.apiKey);
    if (mounted) setState(() => _vaultEntries = entries);
  }
```

`initState` 里调用 `unawaited(_loadVaultEntries())`（补 `import 'dart:async';`）。

3. `_credentialLinkOptions` 追加：

```dart
    for (final entry in _vaultEntries) {
      options.add((
        'vault:${entry.id}',
        '${l10n.vaultPageTitle} · ${entry.title}',
      ));
    }
```

4. `_linkedEntryName`：

```dart
  String _linkedEntryName(BuildContext context) {
    final link = _credentialLink.trim();
    final vaultEntryId = vaultEntryIdFromCredentialLink(link);
    if (vaultEntryId != null) {
      for (final entry in _vaultEntries) {
        if (entry.id == vaultEntryId) return entry.title;
      }
      return '';
    }
    // ... 现有托管条目逻辑 ...
  }
```

5. 选中 `vault:` 后 `_apiKeyCtl.clear()` 已由现有逻辑完成；`_hidesApiKeyFields` 保持不变。

- [ ] **Step 5: analyze 与相关测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error。

Run: `cd client && dart run tool/run_tests.dart test/repositories/app_provider_repository_credential_link_test.dart test/app/provider_vault_link_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: 提交**

```bash
git add client/lib/app/app_shell.dart client/lib/services/vault/provider_credential_link.dart client/lib/widgets/app_provider/app_provider_form_sheet.dart client/test/app/provider_vault_link_test.dart
git commit -m "feat(vault): link provider API keys to vault entries"
```

---

## Task 13: 文档与全量验证

**Files:**
- Modify: `docs/workspace-storage-layout.md`
- Modify: `docs/ARCHITECTURE.md`（若存在 CLI/credential 相关小节）

**Interfaces:**
- Consumes: 前 12 个任务的实现
- Produces: 文档更新 + 全量测试通过

- [ ] **Step 1: 更新存储布局文档**

在 `docs/workspace-storage-layout.md` 的 `<teampilotRoot>/` 树中加：

```
  vault/vault.json               # 可选：主密码加密的凭据保险库（设备本地）
  vault/vault.json.bak           # 停用加密保险库时保留的上一份副本
```

并在该节下方补一句：

```markdown
`vault/` 是**设备本地**数据（同 `ssh_profiles/`）：Android Connect 会把 home
重绑到远端，保险库不跟随。默认后端是系统钥匙串
（`teampilot.vault.v1.document`），启用加密后改为 `vault/vault.json`。
```

- [ ] **Step 2: 更新架构文档**

在 `docs/ARCHITECTURE.md` 的目录说明表末尾加一行：

```markdown
| `services/vault/` | 凭据保险库：`CredentialBackend`（钥匙串/加密文件）、`VaultService`。SSH 与供应商只通过 `readField(entryId, field)` 取值。 |
```

- [ ] **Step 3: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 0 error。

Run: `cd client && dart run tool/run_tests.dart`
Expected: `All tests passed!`（全量套件，在后台跑；完成前不要声明完成）。

- [ ] **Step 4: 手工冒烟**

1. 启动应用 → 设置 → 保险库 → 新建 `SSH 密码` 条目 → 列表出现 → 眼睛显示 30 秒后自动掩码 → 复制后剪贴板 60 秒清空。
2. SSH Servers → 新建 profile，凭据来源选该条目 → 连接成功 → 列表显示锁图标。
3. 老 profile 点「迁移到保险库」→ 连接成功 → 原钥匙串值被清除。
4. 供应商编辑页 → API Key 选择「保险库 · 条目」→ 保存后 `providers.json` 中该行 `apiKey` 为空、`credentialLink` 为 `vault:<id>` → 启动 CLI 能带上 key。
5. 启用加密保险库 → 重启应用 → 显示已锁定 → 解锁后条目可见；输入错误密码不丢数据。

- [ ] **Step 5: 提交**

```bash
git add docs/workspace-storage-layout.md docs/ARCHITECTURE.md
git commit -m "docs(vault): document vault storage and service boundary"
```

---

## Self-Review

**Spec coverage**

| Spec 章节 | 对应任务 |
|-----------|----------|
| §4.1 钥匙串后端 | Task 3 |
| §4.2 加密文件后端 | Task 4 |
| §4.3 后端切换 | Task 5 |
| §5 数据模型 | Task 1 |
| §6 后端抽象与服务 | Task 3/4/5/6 |
| §7 SSH 接入 | Task 10/11 |
| §8 供应商接入 | Task 12 |
| §9 UI（状态卡/列表/详情/编辑器/掩码/复制） | Task 7/8/9 |
| §10 安全与错误 | Task 2（secret-free 异常、GCM）、Task 5（不覆盖原文件）、Task 8（剪贴板） |
| §11 测试 | 每任务 |
| §12 实施顺序 | 任务顺序 |
| §13 非目标 | 未实现导入导出/同步/审计/自动锁 |

**实现提示（已核对 API）**

- `TpCard(padding:, child:)` 可用；`TpInput` 内部固定 `maxLines: 1`，多行备注用 `TextField`。
- `AppProviderRepository` 的读取方法是 `loadProviders(CliTool, {importCredentialsFromGlobal, reconcileCredentials})`。
- `InMemoryFilesystem` 已实现 `ensureDir` / `removeRecursive` / `rename` / `atomicWrite`（`client/test/support/in_memory_filesystem.dart`）。
- `EncryptedVaultBackend.save` 依赖内存中的主密码；这是有意的权衡（避免每次保存重新弹窗），`lock()` / `clear()` 时清空。
- 所有涉及 `firstOrNull` 的文件需 `import 'package:collection/collection.dart';`。
- `main.dart` / `app_shell.dart` 新增 import 时，注意 `Provider` 列表分属 `MultiRepositoryProvider` 与 `MultiBlocProvider`。
