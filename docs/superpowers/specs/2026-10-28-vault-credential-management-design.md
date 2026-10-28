# 保险库（Vault）凭据管理设计

日期：2026-10-28
状态：已评审，待实现

## 1. 背景与目标

TeamPilot 目前把凭据分散在多处：SSH 密码/私钥在
`client/lib/repositories/ssh_credential_store.dart`（`flutter_secure_storage`
或 `SharedPreferences`），供应商 apiKey 在 `providers.json` 与
`ManagedProviderSecretStore`。用户无法在一个地方查看、复用、审计这些密钥。

目标：提供一个类似 Tabby Vault 的**保险库**页面，集中保存 SSH 密码、SSH 私钥、
供应商 apiKey、通用账号密码、令牌和备注；支持查看、复制、搜索；并让
SSH profile 与供应商配置可以**显式引用**保险库条目，而不是各自复制一份。

## 2. 决策摘要

| 决策点 | 结论 |
|--------|------|
| 保险库定位 | 统一凭据源：条目 + 引用方，而非纯展示层 |
| 后端模型 | 照搬 Tabby 的「二选一」：系统钥匙串为默认后端；可选启用主密码加密文件。启用只迁移保险库文档本身，现有 SSH/供应商的钥匙串旧数据不强制迁移 |
| 条目模型 | 通用条目 + 类型预设 + 自定义字段 + 标签/搜索/收藏 |
| 引用方式 | 显式 `id` 引用（`SshProfile.vaultEntryId`、`AppProviderConfig.credentialLink = 'vault:<id>'`），不做 host/user 隐式匹配 |
| 明文策略 | 列表默认掩码；点眼睛显示并在 30 秒后自动掩码；复制后 60 秒清理剪贴板；支持条目级「仅复制」 |
| 加密 | Argon2id + AES-256-GCM，参数写入文件头 |
| v1 范围 | 不含导入/导出、同步、审计日志页、空闲自动锁、附件、密码生成器 |

已否决的方案：

- **隐式匹配（Tabby 原始做法：`user + host + port` 查条目）**：改动最小，但
  改 host/port 就失联，且无法回答「这条密码被谁用了」。
- **全量接管迁移**：把历史钥匙串/供应商密钥一次性搬入保险库。迁移风险高，
  且会让未启用保险库的用户被迫改流程。
- **纯展示层**：只做密码本，SSH/供应商继续各自存储。无法消除重复与不一致。
- **明文元数据索引 + 加密值**：可以在锁定态列出条目名，但泄漏元数据，且引入
  索引与密文两份数据的一致性问题。

## 3. 架构

```
client/lib/
  models/
    vault_entry.dart              # VaultEntry / VaultEntryType / 字段模板
    vault_document.dart           # VaultDocument（版本化序列化）
  services/vault/
    credential_backend.dart       # CredentialBackend 抽象 + VaultReference
    vault_errors.dart             # VaultLockedException / VaultFormatException 等
    keychain_vault_backend.dart   # 系统钥匙串后端（默认）
    encrypted_vault_backend.dart  # 加密文件后端（可选启用）
    vault_crypto.dart             # Argon2id + AES-256-GCM（纯函数）
    vault_service.dart            # 内存文档 + 锁定状态 + CRUD
  models/
    vault_reference.dart          # 引用反查结果（cubit 产出）
  repositories/
    vault_repository.dart         # <root>/vault/vault.json 读写
  cubits/
    vault_cubit.dart
  pages/vault/
    vault_page.dart               # 路由壳
    vault_status_section.dart     # 解锁 / 锁定 / 启用 / 停用
    vault_entry_list.dart         # 搜索 / 过滤 / 列表
    vault_entry_detail.dart       # 详情 / 揭示 / 复制 / 引用方
    vault_entry_editor.dart       # 新建 / 编辑
```

分层遵循 `docs/CODE_QUALITY.md`：文件放到 `pages/vault/`、`cubits/`、
`services/`、`repositories/`、`models/`；仅使用 `HomeStorage.paths` 与
`Filesystem`，不触碰 `Directory.current`。

## 4. 存储与加密

### 4.1 钥匙串后端（默认）

把整份 `VaultDocument` JSON 存在注入的 `SecureKeyValueStore` 单个 key 下：

保险库是设备本地数据（见 4.2），因此计划中通过
`deviceLocalVaultRepository(nativeAppDataPath)` 装配，而不是 `HomeStorage`。

```
teampilot.vault.v1.document
```

- 无文件、无主密码，打开即可用。
- 单 key 写入是原子的，不存在索引与密文不同步的问题。
- 容量预期远低于钥匙串单条上限（数百 KB 以内）。

### 4.2 加密文件后端（可选启用）

```
<nativeAppDataPath>/vault/vault.json
```

保险库是**设备本地**数据，必须和 `ssh_profiles/` 一样固定在本机
`nativeAppDataPath`（`deviceLocalVaultRepository`），不能跟随 AppStorage 的
home 平面。Android Connect 会把 home 重绑到远端主机，若放在 home 下会读空、
甚至把保险库写到远端。

```json
{
  "v": 1,
  "kdf": {
    "name": "argon2id",
    "salt": "base64",
    "memoryKiB": 65536,
    "iterations": 3,
    "parallelism": 1
  },
  "cipher": { "name": "aes-256-gcm", "nonce": "base64" },
  "payload": "base64(ciphertext || tag)"
}
```

- 整份文档加密，包括标题、标签、用户名、备注等元数据。
- 锁定状态下 UI 只显示「保险库已锁定」与解锁入口，不显示条目。
- 读写走 `Filesystem.atomicWrite`；先写临时文件再替换，避免半写。
- `v` 字段用于未来格式迁移；未知版本拒绝加载且不覆盖原文件。
- `pointycastle 4.0.0` 已提供 `Argon2BytesGenerator` 与 `GCMBlockCipher`，
  无需新增依赖。

### 4.3 后端切换

切换只迁移**保险库文档本身**；现有 SSH profile 的钥匙串凭据
（`flashskyai.ssh_creds.v1.*`）不受影响，仍由第 7 节的单条迁移处理。

- **启用保险库**：读取当前（钥匙串）文档 → 用新主密码加密写入
  `vault.json` → 校验可回读 → 删除钥匙串 key。
- **停用保险库**：要求已解锁 → 写入钥匙串 key → 校验 → 将 `vault.json`
  重命名为 `vault.json.bak`（覆盖旧备份）。
- 任一步失败：回滚到切换前状态，抛 secret-free 错误，原始数据必须仍可访问。

## 5. 数据模型

```dart
enum VaultEntryType {
  sshPassword,   // host, port, username, password
  sshPrivateKey, // privateKey, passphrase
  apiKey,        // provider, apiKey, baseUrl
  login,         // url, username, password
  token,         // token
  secureNote,    // note
  custom,
}

@immutable
class VaultEntry {
  final String id;                  // uuid v4
  final VaultEntryType type;
  final String title;
  final Map<String, String> fields;  // 字段名 -> 值
  final List<String> tags;
  final String notes;
  final bool favorite;
  final bool revealable;            // false = 仅复制；私钥/恢复码默认 false
  final int createdAt;
  final int updatedAt;
}
```

规则：

- 字段模板由 `VaultEntryType.defaultFields` 提供；新增类型只改模板，不改存储。
- `revealable` 默认值：`sshPrivateKey` 为 `false`；其余类型为 `true`。用户可在
  编辑页改为仅复制，但不能把 `sshPrivateKey` 改成可揭示（避免误操作）。
- `fromJson` 遇到未知 `type` 降级为 `custom`，未知字段原样保留，避免版本回退
  丢数据；`toJson` 写回时保留未知字段。
- `toString()` 输出 `<redacted>`，不得包含字段值。
- 引用关系不写进条目；由 `VaultCubit.referencesFor(entryId)` 实时扫描
  `SshProfileRepository` 与 `AppProviderRepository` 得出，避免双向同步。
  `VaultService` 只负责存储与取值，不依赖其它仓储。

## 6. 后端抽象与服务

```dart
abstract interface class CredentialBackend {
  String get kind;                       // 'keychain' | 'encrypted'
  bool get needsUnlock;
  /// 无文档返回 null；存在但锁定抛 [VaultLockedException]。
  Future<VaultDocument?> load();
  Future<void> save(VaultDocument doc);
  /// 删除（钥匙串）或归档（加密文件）本后端持有的文档。
  Future<void> clear();
}

class VaultService {
  Future<void> initialize();
  Future<void> unlock(String passphrase);
  void lock();
  bool get isEncrypted;
  bool get isLocked;
  Future<List<VaultEntry>> list({String query = '', VaultEntryType? type, Set<String> tags = const {}});
  Future<VaultEntry?> get(String id);
  Future<void> upsert(VaultEntry entry);
  Future<void> delete(String id);
  /// 条目或字段缺失返回 null；保险库锁定时抛 [VaultLockedException]。
  Future<String?> readField(String entryId, String field);
  Future<void> enableEncryptedBackend(String passphrase);
  Future<void> disableEncryptedBackend();
}
```

引用反查在 `VaultCubit` 中完成：

```dart
// models/vault_reference.dart
enum VaultReferenceKind { sshProfile, appProvider }

class VaultReference {
  const VaultReference({required this.kind, required this.id, required this.label});
  final VaultReferenceKind kind;
  final String id;
  final String label;
}
```

- `VaultService` 是唯一接触 `CredentialBackend` 的地方；SSH 与供应商只依赖
  `readField`。
- 所有写操作串行化（复用 `ManagedProviderSecretStore` 里 `_CredentialRefLock`
  的同类做法），避免并发写覆盖。
- 内存文档在 `lock()` 或进程退出时清空。

## 7. SSH 接入

- `SshProfile` 新增 `String? vaultEntryId`；`fromJson` 容忍缺失，
  `toJson` 为空时不写。
- 优先级：`vaultEntryId != null` → 保险库；否则维持现有
  `SshCredentialStore` 行为。不做双写。
- `SshClientFactory` 增加可选依赖
  `VaultCredentialReader`（`Future<String?> readField(entryId, field)`）；
  未注入时行为与当前完全一致。`_openClient` 内的凭据读取收敛为
  `_resolveSshCredentials(profile)`：
  - 密码认证：`password` 字段。
  - 私钥认证：`privateKey` + `passphrase` 字段；缺失时抛出与现有实现一致的
    `StateError`。
  - 保险库处于锁定态时，连接失败并提示「保险库已锁定」，不回退到空密码。
- 表单（`ssh_profile_form_dialog.dart` 与 Android 全页版
  `ssh_profile_setup_page.dart`）：
  - 认证区新增「凭据来源：本机钥匙串 / 保险库条目」。
  - 选择保险库时展示按类型过滤的条目选择器，并提供「新建条目」入口。
  - 选择本机时保留原密码框，并新增「保存到保险库」勾选框：保存时创建条目、
    回填 `vaultEntryId`。
- Profile 列表：保险库来源的行显示锁图标与条目名，并提供「迁移到保险库」动作。
- 迁移顺序：创建条目 → 保存保险库成功 → 写 `profile.vaultEntryId` → 删除
  钥匙串旧值。任一步失败保留旧数据，可重试。v1 仅支持单条迁移。

## 8. 供应商接入

复用现有 `credentialLink` 机制，不改供应商存储结构：

- 新增引用值前缀 `vault:<entryId>`；原有托管供应商 id 保持不变。
- `AppShell.appProviderLinkedCredentialLookup` 按前缀分流：
  `vault:` → `VaultService.readField(id, 'apiKey')`；失败返回 `null`，
  保持 secret-free 契约。
- `app_provider_form_sheet.dart`：
  - `_credentialLinkOptions` 追加保险库条目，label 为 `保险库 · <title>`。
  - `_linkedEntryName` 支持反查保险库条目。
  - 选中后继续清空 apiKey 输入框；落盘继续由 `_stripLinkedApiKey` 剥离明文。
- 条目缺少 `apiKey` 字段时按 `missing` 展示，不回退到其他字段。

## 9. UI

入口：`ConfigSection.vault` → `/config/vault`，设置侧栏「保险库 / Vault」，
与 SSH Servers 平级；Android 使用同一页面。

页面由四部分组成：

1. **状态卡**：`系统钥匙串 · 无需解锁` 或 `加密保险库 · 已锁定`；操作为
   解锁 / 立即锁定 / 启用加密保险库 / 停用。
2. **工具栏**：搜索（标题、字段值、标签）、类型筛选、标签 chips、新建条目。
3. **列表**：类型图标、标题、副标题（`username@host` 或 provider）、标签、
   收藏星标。
4. **详情**：字段逐行展示；默认掩码；眼睛按钮揭示并在 30 秒后自动掩码；
   复制按钮在 60 秒后清理剪贴板（仅当剪贴板内容仍等于该值）；
   `revealable == false` 的条目不显示眼睛；底部显示引用方
   （如「被 2 个 SSH Profile、1 个供应商使用」，可跳转）；删除时若有引用，
   二次确认并列出引用方。

空态文案说明可保存 SSH 密码、私钥、供应商 API Key，并提供新建与从 SSH 迁移
两个入口。文本写入 `app_en.arb` / `app_zh.arb`。

定时器通过构造参数注入（默认 30s / 60s），便于测试。

## 10. 安全与错误处理

- 密钥值不写日志、不进异常消息；`VaultEntry.toString()` 已脱敏。
- Argon2id 在 `Isolate.run` 中执行，避免解锁阻塞 UI。
- 密码错误：保留数据、提示重试、两次尝试之间节流 500ms；不实现锁定计数。
- GCM 校验失败或 JSON 损坏：不覆盖原文件；提示备份原文件后重建，需显式确认。
- 后端切换失败：回滚并保留原数据；错误类型 secret-free。
- 剪贴板清理只在内容仍为所复制值时执行，避免清掉用户后来复制的内容。
- 已知限制：Android 截屏保护（`FLAG_SECURE`）不在 v1；导出/同步不在 v1。

## 11. 测试

| 文件 | 覆盖 |
|------|------|
| `vault_crypto_test.dart` | 加解密往返、错误密码、payload 篡改、文件头 KDF 参数生效、未知版本拒绝 |
| `vault_entry_test.dart` | 序列化往返、未知 type 降级、未知字段保留、`toString` 不泄露 |
| `vault_service_test.dart` | CRUD、引用反查、锁定/解锁、后端切换及失败回滚、并发写串行化 |
| `keychain_vault_backend_test.dart` | 单 key 读写、无文档返回 null |
| `ssh_vault_credentials_test.dart` | `vaultEntryId` 优先、legacy 路径不受影响、迁移失败保留旧值 |
| `app_provider_vault_link_test.dart` | `vault:` 前缀解析、缺字段按 missing、编辑时保留链接 |
| widget 测试 | 掩码/揭示/自动掩码、复制后清理、引用删除保护 |

流程要求：内层 `flutter analyze`；外层 `dart run tool/run_tests.dart`；
禁止直接运行 `flutter test`。

## 12. 实施顺序

1. 模型、加密、双后端、仓储（纯逻辑 + 单测）。
2. `VaultService`、cubit、页面 CRUD（先只支持钥匙串后端）。
3. SSH 接入与单条迁移。
4. 供应商接入。
5. 掩码/剪贴板/引用 UI、l10n、文档收尾。

## 13. 非目标（v1）

- `.tpvault` 导入/导出与跨设备同步（文件格式已预留 `v` 与 KDF 参数，v1.1 再加）
- 浏览器 CSV 导入
- 审计日志页面
- 空闲自动锁
- 附件/文件托管
- 密码生成器

## 14. 风险与后续

| 风险 | 缓解 |
|------|------|
| Argon2id 在低端 Android 上过慢 | 参数写入文件头；必要时下调至 32 MiB，不影响旧文件 |
| 用户忘记主密码导致数据不可恢复 | 启用时明确提示；后续提供导出备份（v1.1） |
| 引用关系扫描成本随条目增长 | 仅在详情页与删除前计算，列表不扫描 |
| `SshCredentialStore` 调用点较多 | 通过可选注入 `VaultCredentialReader`，不改现有接口签名 |
