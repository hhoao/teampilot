# 统一 SSH Profile 编辑器设计

- 日期：2026-11-10
- 状态：待审阅
- 来源：用户反馈「移动端远程 SSH 服务器编辑时查看密码看不到密码」，并要求与桌面端对齐
- 上游契约：[2026-11-06 移动端远程连接与 SSH 服务器拆分设计](2026-11-06-mobile-remote-connection-design.md)、[ARCHITECTURE.md](../../ARCHITECTURE.md)「Mobile remote connection contract」

## 背景与根因

「远程 SSH 服务器」页（`SshProfilesConfigWorkspace`）与桌面端是同一页面、同一入口，绑定 `PlaneSshProfileRepository`；平面记录 `SshServerProfile` 刻意不带凭据与 `vaultEntryId`，凭据只留在本机 vault，按 `vaultOwnerKindSshProfile` + `profile.id` 索引。桌面端能显示「保险库」徽标，是 `PlaneSshProfileRepository._deviceVaultRefs()` 从设备本地 `RemoteTarget` 借用 `vaultEntryId`，并非记录里存了引用。

当前存在**两套编辑器**：

- `openSshProfileEditor`（`client/lib/pages/ssh_profiles_page.dart:178-213`）以 `useFullPageEditor ?? Platform.isAndroid` 分流：Android 用 `Navigator.push` 打开 `SshProfileSetupPage`，桌面用 `showSshProfileFormDialog`。
- `52f0b06ad fix(ssh): reveal saved passwords when editing a server` 只修改了桌面 dialog：新增 `_revealPassword`，在 `vaultEntryId` 为空时回退 `revealVaultOwnerSecret`，并给 `TpPasswordInput` 接上 `onReveal`。**Android 的 `SshProfileSetupPage` 完全没有被改动。**

`SshProfileSetupPage`（`client/lib/pages/ssh_profile_setup_page.dart`）的密码框是普通 `TextFormField` + `TpPasswordVisibilityToggle`，只切换 `obscureText`；编辑时输入框为空（hint 为「留空则保留已保存密码」），没有 `onReveal`，也从未调用 `revealVaultSecret` / `revealVaultOwnerSecret`。而 `TpPasswordInput.onReveal` 的契约是「空框首次点显示时调用，把返回值写入 controller 并显示」（`client/lib/widgets/tp_password_input.dart:113-126`）。因此移动端点开密码框只能看到空内容，即用户所报现象。

同一条编辑路径上还有两个由「平面行借不到 `vaultEntryId`」引起的连带问题：

1. **测试连接**：`SshProfileSetupPage._testConnection`（`:175-218`）与桌面 dialog `_testConnection`（`ssh_profile_form_dialog.dart:246-292`）都只在 `linkedId` 非空时读 vault；借不到时 `readVaultField` 为 `null`，回退到可能已被清空的 legacy keychain。
2. **保存可能清空凭据**：`linked=false` 时 `sshEditorSecretInputs` 把空密码框当成 `''`（删除指令）而非 `null`（保留）（`client/lib/services/ssh/ssh_profile_vault_writer.dart:116-135`）；`saveSshProfileWithVault` 又用可能为空的 keychain 值回填（`:41-60`），最终 `captureSsh` 的 `_upsert` 会移除 vault 中已存的 `password` 字段。

此外 `SshProfileSetupPage` 的私钥输入是 `TpTextarea` 直接粘贴文本，而 dialog 是 `FilePicker` 选路径 + `dart:io File(path).readAsString()`（`ssh_profile_form_dialog.dart:136-157`）。Android 上 file picker 常返回 `content://` URI，`File()` 无法读取，直接统一会造成移动端功能回退。

## 目标

1. 全平台只保留一个 SSH Profile 编辑器 `showSshProfileFormDialog`。
2. 移动端编辑时能查看已保存的密码（owner 反查）。
3. 编辑页「测试连接」能取到平面行的已存凭据。
4. 编辑态保存不误删 vault 中已存的凭据。
5. 私钥输入在 Android 与桌面一致可用。

## 非目标

- 不改安全模型：`SshServerProfile` 仍不含 `vaultEntryId` 与任何凭据；凭据与引用只留本机 vault。
- 不改 `PlaneSshProfileRepository` 的借用逻辑、不改 `RemoteTargetSync`、不改两侧连接语义（`switchHomeOnConnect`）。
- 不改 `confirmDeleteSshProfile`（`ssh_profiles_page.dart:215-248`）；其中的硬编码中文另案处理。
- 不修列表「保险库」徽标只看 `profile.vaultEntryId` 的不一致（`ssh_profile_target_card.dart:320-332`），这是独立小问题。
- 不改 `showRemoteConfig` 的行为，也不订正 `ssh_profiles_section.dart:36-41` 的过时注释（与本次无关）。
- 不做凭据跨设备同步；沿用上游设计「新设备首次连接同一目标需输入一次登录凭据」。

## 方案

选定方案为「统一编辑器」：去掉 `openSshProfileEditor` 的平台分支，全平台走 `showSshProfileFormDialog`。以下 2.2–2.4 是统一后在同一条编辑路径上一并收口的既有缺陷，均已与用户逐节确认。

### 1. 架构与组件

唯一编辑器为 `showSshProfileFormDialog`（`client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`）。

- 删除 `client/lib/pages/ssh_profile_setup_page.dart` 整个文件。该文件是 Android 专用分支，且含大量硬编码中文（`'Profile 名称'`、`'必填'`、`'保存 Profile'` 等），删除后这些违反 l10n 规则的文案一并消失。
- `openSshProfileEditor` 简化为直接 `showSshProfileFormDialog(context, profile: profile)`：移除 `useFullPageEditor` 参数、`Platform.isAndroid` 判断、`Navigator.push(MaterialPageRoute)` 分支，以及 `SshProfileSetupPage` / `dart:io` / `SshCredentialStore` / `SshProfileConnectionTester` / `TerminalTransportFactory` / `VaultService` 等仅服务于该分支的 import。`home_storage.dart` 等 `SshServersPage` 仍在使用的 import 保留。
- `confirmDeleteSshProfile` 保留不动。
- `client/lib/widgets/workspace_terminal/workspace_terminal_new_session_menu.dart:102` 已在 Android 直接调用 `showSshProfileFormDialog`，保持不变；它同时证明移动端 dialog 链路可用。
- 所有调用方零改动：`SshProfilesSection` 的三处入口（新增 ×2、编辑 ×1）、onboarding 与启动门控（经 `SshProfilesSection` 间接调用）自动切到 dialog。
- 窄屏表现沿用项目既有模式：`showTpDialog(presentation: TpDialogPresentation.page, mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth)`，与 automations、expert_editor、workspace_search 等一致。

**provider 作用域**：dialog 在 `ssh_profile_form_dialog.dart:31-34` 从调用方 context 读取 `SshProfileRepository` 与 `SshProfileCubit` 并作为构造参数传入 dialog widget，因此即使 dialog route 挂在 root navigator 上，仍写到「SSH 服务器」页子树里的 home-plane 仓库，不会误写设备本地目录。该行为已由 `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart:86-182` 覆盖。

### 2. 行为与数据流

#### 2.1 查看密码（直接解决所报问题）

无需新增 UI：dialog 已有 `_revealPassword`（`:231-244`）——`vaultEntryId` 非空走 `revealVaultSecret`，否则走 `revealVaultOwnerSecret(ownerKind: vaultOwnerKindSshProfile, ownerId: profile.id, field: 'password')`；`TpPasswordInput.onReveal` 把返回值填入空框显示。统一后移动端自动获得该能力。

#### 2.2 测试连接与 owner 解析

在 `client/lib/services/ssh/ssh_profile_vault_writer.dart` 新增纯函数，供测试连接使用：

```dart
typedef SshVaultFieldReader = Future<String?> Function(String field);

SshVaultFieldReader resolveSshVaultFieldReader(
  VaultService vault,
  SshProfile profile,
);
```

行为：`profile.vaultEntryId` 非空时用 `vault.get(id)` 读字段；否则用已有的 `findVaultOwnerEntry(vault, ownerKind: vaultOwnerKindSshProfile, ownerId: profile.id)`（`client/lib/services/vault/credential_capture.dart:44-56`）取 owner 条目再读字段；读取失败或找不到条目返回 `null`。

dialog 的 `_testConnection` 改为总是读取 `VaultService`，把 `resolveSshVaultFieldReader(vault, profile)` 的结果作为 `readVaultField` 传给 `resolveSshEditorTestSecrets`，移除对 `linkedId` 的依赖，保留既有的「表单输入 → vault → legacy keychain」三级回退。

reveal 与 test 不合并为一个函数：reveal 走 `revealVault*`（需 `authorizeVaultReveal` 重新认证、读后重新上锁），test 走上述 reader（功能读取、不认证）。两者只共享「按 owner 解析条目」这一层。

#### 2.3 保存不误删凭据

- `sshEditorSecretInputs` 新增 `bool isEditing = false` 参数：空的凭据字段在 `isEditing || linked` 为真时返回 `null`（保留），否则返回 `''`（删除/必填校验）。dialog 保存处传入 `_isEditing`。注意 `saveSshProfileWithVault` 中的 `linked` 仍按 `profile.vaultEntryId` 判定，与此处 `isEditing` 是两个不同概念，不合并。
- `saveSshProfileWithVault`：当 `profile.id` 对应的 owner vault 条目已存在、且该字段输入为 `null`（保留）时，跳过 legacy keychain 回填，避免用空值覆盖已存密码；`captureSsh` 已有的 `null` 语义即「保留现有值」。
- 其余保存流程（`captureThenPersist`、`_persistedVaultEntryId` 防误删 keychain、平面 repository 丢弃 `vaultEntryId`）不变。

#### 2.4 私钥输入统一（已确认采用方案 A）

dialog 的私钥字段从「文件路径」改为「可直接粘贴的文本框」，两平台一致：

- 用 `_privateKeyController`（保存 PEM 文本）替代 `_identityFileController`（保存路径）；`_usesPasswordAuth` 改为基于私钥文本框与密码框的内容判定，优先级不变。
- 保留「导入文件」按钮作为可选快捷方式：`FilePicker` 成功时把读到的内容写入 `_privateKeyController`；失败（含 Android `content://` URI）用 `AppToast` 提示，不阻断粘贴路径。
- 保存与测试连接直接取 `_privateKeyController.text`，移除 `dart:io` 的 `File.readAsString()`。
- l10n：把 `formIdentityFile*` 系列文案调整为「私钥内容 / 粘贴私钥」，新增导入按钮与导入失败提示文案；编辑 `client/lib/i18n/sshProfile_zh.i18n.json` 与 `sshProfile_en.i18n.json` 后执行 `cd client && dart run slang`。

#### 2.5 安全模型不变

`SshServerProfile` 仍无 `vaultEntryId`；`PlaneSshProfileRepository._toServer` 继续丢弃引用；`client/test/repositories/plane_ssh_profile_repository_test.dart:100-123` 的「save never writes the vault reference into the plane projection」回归断言保持。

### 3. 错误处理与测试

#### 3.1 测试迁移（`useFullPageEditor` 删除后）

| 文件 | 处理 |
|---|---|
| `client/test/pages/startup_gate_test.dart:373-387` | 「full-page editor push/pop returns to list」概念随分支消失，改写为「编辑器以 dialog 打开、关闭后回到列表」。 |
| `client/test/pages/startup_gate_test.dart:389-445` | 「save does not clear gate」的 `TextFormField` / `TpTextarea` / `ElevatedButton '保存 Profile'` 硬编码断言，换成 dialog 的 `TextField` / 按钮；文案一律用 `l10n.sshProfile.*` 引用，不写死中文。 |
| `client/test/pages/onboarding/work_home_step_test.dart:525-558` | 同上；`openSshProfileEditor(ctx)` 不再传 `useFullPageEditor`。 |

这些 harness 需补齐 dialog 依赖的 providers：`TerminalTransportFactory`、`VaultService`、`VaultCredentialCapture`、`VaultUnlockGate`、`SshProfileCubit`、`SshProfileRepository`。这是本次最主要的回归风险点。

#### 3.2 新增测试

- 编辑态且借不到 `vaultEntryId` 时，点「显示」→ `TpPasswordInput.onReveal` → owner 反查命中并把密码填入输入框（直接锁住所报问题）。
- `resolveSshVaultFieldReader` 单测：有 `entryId` / 无 `entryId` 但 owner 条目存在 / 两者皆无返回 `null`。
- 回归：编辑态不输入密码直接保存，vault 中已有 `password` 字段不被清空。
- 私钥可直接粘贴并保存（覆盖 2.4）。

#### 3.3 错误处理

| 场景 | 行为 |
|---|---|
| Vault 锁定或用户取消解锁 | reveal 返回 `null`、保持遮蔽，沿用 `authorizeVaultReveal`（`client/lib/pages/vault/vault_secret_reveal.dart:16-35`），不新增逻辑 |
| owner 读取失败 / 无 owner 条目 | reader 返回 `null`，test 回退既有三级回退 |
| 文件导入失败（Android `content://`） | 不阻断粘贴路径，沿用 `AppToast` 提示 |
| 编辑态空凭据字段 | 视为「保留现有」，不触发 keychain 回填覆盖 |

#### 3.4 验证

- 新增 l10n 后：`cd client && dart run slang`。
- 内循环：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`；单文件用 `cd client && dart run tool/run_tests.dart <path> --plain-name <name>` 缩小范围。
- 收尾一次全量：`cd client && dart run tool/run_tests.dart`（后台运行）。
- **不**直接调用 `flutter test`（会破坏共享构建缓存）。

## 风险

- **provider 缺失**：启动门控与 onboarding 路径早于完整 app shell 装配，dialog 依赖的 `TerminalTransportFactory` / `VaultService` 等可能未在 harness 与运行期提供。迁移测试时逐一确认，必要时在 gate host 补 provider。
- **窄屏 dialog 表现**：`showTpDialog(presentation: page)` 在 Android 上的滚动、键盘避让需实测；项目内已有多个同类用法，风险较低。
- **私钥文案改动**：涉及 slang 再生成，需确认 `sshProfile` 命名空间两个 locale 文件同步修改，避免生成产物漂移。
- **删除残留引用**：Grep 已确认 `SshProfileSetupPage` 仅被 `openSshProfileEditor` 引用，删除后用 `flutter analyze` 兜底检查残留 import。
- **凭据仍不跨设备**：沿用上游设计；本次不引入任何同步，避免把凭据写到用户可能不控制的远端 home。
