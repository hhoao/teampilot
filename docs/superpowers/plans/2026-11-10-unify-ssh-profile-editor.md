# 统一 SSH Profile 编辑器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除 Android 专用的 `SshProfileSetupPage`，让全平台只用一个 `showSshProfileFormDialog`，并让移动端在编辑时能查看已保存密码、测试连接能读到平面行凭据、保存不误删凭据、私钥可直接粘贴。

**Architecture:** 保留「SSH 服务器」页绑定 home-plane 仓库、凭据只留本机 vault 的安全模型不动。把「按 owner 解析 vault 条目」收敛为 `ssh_profile_vault_writer.dart` 里的纯函数，编辑器 reveal 与测试连接各自复用它（reveal 仍需重新认证）。编辑器统一后，桌面与 Android 共用同一个 dialog、同一套 l10n、同一套测试。

**Tech Stack:** Flutter / Dart、`flutter_bloc`、slang l10n、`shared_ui`（`TpFormField` / `TpDialogPageShell` / `TpPasswordInput`）、`file_picker`、`VaultService` / `VaultCredentialCapture` / `VaultUnlockGate`、`SshProfileRepository`。

## Global Constraints

- 凭据与 `vaultEntryId` 只留本机 vault；`SshServerProfile`（home-plane 记录）**不得**含 `vaultEntryId` 或任何凭据字段。
- `PlaneSshProfileRepository` 的借用逻辑、`RemoteTargetSync`、两侧 `switchHomeOnConnect` 连接语义不改。
- `confirmDeleteSshProfile`、`showRemoteConfig` 行为、`ssh_profile_target_card.dart` 的「保险库」徽标逻辑不改。
- l10n 用 slang：改 `client/lib/i18n/sshProfile_en.i18n.json` 与 `sshProfile_zh.i18n.json`，然后 `cd client && dart run slang`；**不**用 build_runner。
- 测试：**禁止**直接 `flutter test`；一律 `cd client && dart run tool/run_tests.dart <path>`，可用 `--plain-name <name>` 缩小范围。内循环 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`。
- 用户可见错误用 l10n，诊断用 `AppLogger`；禁止 `print`。
- 每个任务结束都要 commit，只提交本任务涉及的文件。

---

## 文件结构

| 文件 | 职责 | 操作 |
|---|---|---|
| `client/lib/services/ssh/ssh_profile_vault_writer.dart` | 编辑器凭据映射、vault 写入、owner 字段读取 | 修改：新增 `resolveSshVaultFieldReader`、`sshEditorSecretInputs` 加 `isEditing`、保存跳过 keychain 回填、移除 `resolveSshEditorTestSecrets.vaultEntryId` |
| `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart` | 唯一 SSH Profile 编辑器 | 修改：私钥改为可粘贴文本框、`_testConnection` 用 reader、移除 `dart:io` |
| `client/lib/pages/ssh_profiles_page.dart` | 编辑器入口 + 删除确认 | 修改：`openSshProfileEditor` 去掉平台分支与多余 import |
| `client/lib/pages/ssh_profile_setup_page.dart` | Android 专用编辑器 | **删除** |
| `client/lib/i18n/sshProfile_en.i18n.json` / `sshProfile_zh.i18n.json` | 编辑器文案 | 修改文案、新增 2 个 key |
| `client/lib/l10n/translations_en.g.dart` / `translations_zh.g.dart` | slang 生成产物 | 由 `dart run slang` 生成，不手改 |
| `client/test/services/ssh/ssh_profile_vault_writer_test.dart` | 写入/映射/reader 单测 | 修改：新增 4 组测试、改 3 处调用 |
| `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart` | 编辑器 widget 测试 | 修改：抽 `pumpEditor` helper + 新增 2 个测试 |
| `client/test/pages/startup_gate_test.dart` | 启动门控测试 | 修改：补 `VaultService` provider、迁移 2 个测试 |
| `client/test/pages/onboarding/work_home_step_test.dart` | onboarding 测试 | 修改：补 `VaultService` provider、迁移 1 个测试 |

---

### Task 1: `resolveSshVaultFieldReader` 纯函数

**Files:**
- Modify: `client/lib/services/ssh/ssh_profile_vault_writer.dart`
- Test: `client/test/services/ssh/ssh_profile_vault_writer_test.dart`

**Interfaces:**
- Consumes: `VaultService.get(String)`、`findVaultOwnerEntry(VaultService, {ownerKind, ownerId})`、`vaultOwnerKindSshProfile`（均来自 `client/lib/services/vault/credential_capture.dart`）、`SshProfile.vaultEntryId` / `.id`
- Produces: `typedef SshVaultFieldReader = Future<String?> Function(String field);` 和 `SshVaultFieldReader resolveSshVaultFieldReader(VaultService vault, SshProfile profile)` —— Task 5 与 Task 6 依赖这两个名字

- [ ] **Step 1: 写失败测试**

在 `client/test/services/ssh/ssh_profile_vault_writer_test.dart` 的 `main()` 内、`group('editor test credentials', ...)` 之前插入：

```dart
  group('resolveSshVaultFieldReader', () {
    test('reads the field by linked entry id', () async {
      final vault = await _vault();
      final capture = VaultCredentialCapture(vault: vault);
      final result = await capture.captureSsh(profile, password: 'secret');
      final linked = profile.copyWith(vaultEntryId: result.entryId);

      expect(await resolveSshVaultFieldReader(vault, linked)('password'), 'secret');
    });

    test('falls back to the owner pair when the row has no vault link', () async {
      final vault = await _vault();
      await VaultCredentialCapture(vault: vault).captureSsh(
        profile,
        password: 'secret',
      );

      expect(await resolveSshVaultFieldReader(vault, profile)('password'), 'secret');
    });

    test('returns null with no entry and for an absent field', () async {
      final vault = await _vault();
      await VaultCredentialCapture(vault: vault).captureSsh(
        profile,
        password: 'secret',
      );
      final reader = resolveSshVaultFieldReader(vault, profile);

      expect(await reader('passphrase'), isNull);
      expect(await resolveSshVaultFieldReader(await _vault(), profile)('password'), isNull);
    });
  });
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_vault_writer_test.dart --plain-name "resolveSshVaultFieldReader"
```

Expected: 编译失败 `Undefined name 'resolveSshVaultFieldReader'`。

- [ ] **Step 3: 实现**

在 `client/lib/services/ssh/ssh_profile_vault_writer.dart` 顶部 import 区加入：

```dart
import '../vault/vault_service.dart';
```

（`credential_capture.dart` 已 import，`findVaultOwnerEntry` / `vaultOwnerKindSshProfile` 可直接用。）在文件末尾追加：

```dart
/// Reads a stored credential field for an SSH profile.
///
/// Home-plane rows carry no `vaultEntryId`; fall back to the owner pair the
/// vault itself keeps. This is a functional read — explicit reveals go through
/// `revealVault*` instead, which re-authenticates before showing a secret.
typedef SshVaultFieldReader = Future<String?> Function(String field);

SshVaultFieldReader resolveSshVaultFieldReader(
  VaultService vault,
  SshProfile profile,
) {
  return (field) async {
    final linked = profile.vaultEntryId?.trim() ?? '';
    final entry = linked.isNotEmpty
        ? await vault.get(linked)
        : await findVaultOwnerEntry(
            vault,
            ownerKind: vaultOwnerKindSshProfile,
            ownerId: profile.id,
          );
    final value = entry?.fields[field];
    return (value == null || value.isEmpty) ? null : value;
  };
}
```

- [ ] **Step 4: 跑测试，确认通过**

```bash
cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_vault_writer_test.dart --plain-name "resolveSshVaultFieldReader"
```

Expected: `+3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ssh/ssh_profile_vault_writer.dart client/test/services/ssh/ssh_profile_vault_writer_test.dart
git commit -m "feat(ssh): resolve vault fields by owner for plane rows"
```

---

### Task 2: 编辑态保存不误删凭据

**Files:**
- Modify: `client/lib/services/ssh/ssh_profile_vault_writer.dart`
- Test: `client/test/services/ssh/ssh_profile_vault_writer_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `SshVaultFieldReader`（本任务不直接用）、`VaultCredentialCapture.findOwner(String, String)`
- Produces: `sshEditorSecretInputs(..., {bool isEditing = false})` —— Task 4 的 dialog 依赖这个签名

- [ ] **Step 1: 写失败测试**

在 `client/test/services/ssh/ssh_profile_vault_writer_test.dart` 的 `main()` 内追加：

```dart
  test('editing without retyping the password keeps the stored secret', () async {
    final vault = await _vault();
    final repository = SshProfileRepository(storage: fakeHomeStorage());
    final credentials = InMemorySshCredentialStore();
    final capture = VaultCredentialCapture(vault: vault);
    final gate = VaultUnlockGate(vault: vault, prompt: () async => true);

    final first = await saveSshProfileWithVault(
      profile: profile,
      password: 'secret',
      privateKey: null,
      passphrase: null,
      capture: capture,
      unlockGate: gate,
      repository: repository,
      credentialStore: credentials,
    );

    // A home-plane row has no vaultEntryId on reload (that is `profile`).
    await saveSshProfileWithVault(
      profile: profile,
      password: null,
      privateKey: null,
      passphrase: null,
      capture: capture,
      unlockGate: gate,
      repository: repository,
      credentialStore: credentials,
    );

    expect(await vault.readField(first.capture.entryId, 'password'), 'secret');
  });

  test('editor mapping preserves an empty password when editing an unlinked row', () {
    expect(
      sshEditorSecretInputs(
        authType: SshAuthType.password,
        linked: false,
        isEditing: true,
        passwordText: '',
        privateKeyPem: '',
        passphraseText: '',
      ).password,
      isNull,
    );
  });
```

保留现有 `'editor mapping keeps linked empties and clears the inactive auth'` 测试不动（`isEditing` 默认 `false`，行为不变）。

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_vault_writer_test.dart --plain-name "editing without retyping"
```

Expected: FAIL —— `isEditing` 具名参数不存在；且第二个测试因缺少跳过 keychain 回填而断言 `'secret'` 变成 `null`。

- [ ] **Step 3: 实现**

在 `ssh_profile_vault_writer.dart` 中把 `sshEditorSecretInputs` 改为：

```dart
SshEditorSecretInputs sshEditorSecretInputs({
  required SshAuthType authType,
  required bool linked,
  required String passwordText,
  required String privateKeyPem,
  required String passphraseText,
  bool isEditing = false,
}) {
  if (authType == SshAuthType.password) {
    return (
      password: passwordText.isEmpty
          ? ((isEditing || linked) ? null : '')
          : passwordText,
      privateKey: '',
      passphrase: '',
    );
  }
  return (
    password: '',
    privateKey: privateKeyPem.isEmpty ? null : privateKeyPem,
    passphrase: passphraseText.isEmpty ? null : passphraseText,
  );
}
```

把 `saveSshProfileWithVault` 中 `if (!linked) { ... }` 整段替换为：

```dart
  if (!linked) {
    // An owner entry already holds this device's secret. A null input means
    // "keep it"; adopting a (possibly empty) legacy keychain value here would
    // overwrite or delete that stored secret.
    final owned = await capture.findOwner(
      vaultOwnerKindSshProfile,
      profile.id,
    );
    final preserveStored = owned != null && effectivePassword == null;
    if (!preserveStored) {
      if (profile.authType == SshAuthType.password &&
          (effectivePassword == null || effectivePassword.isEmpty)) {
        effectivePassword = await credentialStore.loadPassword(profile.id);
      }
      if (profile.authType == SshAuthType.privateKey) {
        if (effectivePrivateKey == null || effectivePrivateKey.isEmpty) {
          effectivePrivateKey = await credentialStore.loadPrivateKey(
            profile.id,
          );
        }
        if (effectivePassphrase == null || effectivePassphrase.isEmpty) {
          effectivePassphrase = await credentialStore.loadPrivateKeyPassphrase(
            profile.id,
          );
        }
      }
    }
  }
```

- [ ] **Step 4: 跑整个文件，确认通过（含现有回归）**

```bash
cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_vault_writer_test.dart
```

Expected: `All tests passed!`（含 `'adopts legacy keychain secrets and deletes them after save'` 与 `'keeps the legacy keychain copy when the saved row drops the vault link'` —— 两者首次保存时 owner 条目不存在，仍走回填）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ssh/ssh_profile_vault_writer.dart client/test/services/ssh/ssh_profile_vault_writer_test.dart
git commit -m "fix(ssh): keep stored credentials when editing an unlinked row"
```

---

### Task 3: 统一编辑器（删除 Android 分支）

**Files:**
- Delete: `client/lib/pages/ssh_profile_setup_page.dart`
- Modify: `client/lib/pages/ssh_profiles_page.dart:1-21,178-213`
- Test: `client/test/pages/startup_gate_test.dart:229-243,363-452`
- Test: `client/test/pages/onboarding/work_home_step_test.dart:287-303,500-558`

**Interfaces:**
- Consumes: `showSshProfileFormDialog(BuildContext, {SshProfile? profile})`（现有签名不变）
- Produces: `Future<void> openSshProfileEditor(BuildContext context, {SshProfile? profile})` —— 不再有 `useFullPageEditor` 参数

- [ ] **Step 1: 先补测试 harness 的 `VaultService` provider（否则后续 dialog 会抛 ProviderNotFound）**

`client/test/pages/startup_gate_test.dart` 的 `_gateHost` providers 列表（第 229-243 行）末尾、`VaultUnlockGate` 之后插入一行：

```dart
      RepositoryProvider<VaultService>.value(value: vault),
```

`client/test/pages/onboarding/work_home_step_test.dart` 的 `_pumpWorkHomeStep` providers 列表（第 287-303 行）同样插入：

```dart
        RepositoryProvider<VaultService>.value(value: vault),
```

两个函数都已有 `final vault = await _unlockedVault();`，无需新增变量。`VaultService` 已 import。

- [ ] **Step 2: 迁移 `startup_gate_test.dart` 的两个测试**

把第 373-387 行的 `'full-page editor push/pop returns to list'` 整个测试替换为：

```dart
  testWidgets('editor dialog opens and closing it returns to the list', (
    tester,
  ) async {
    await pumpGatedEmptyList(tester);

    final ctx = tester.element(find.byType(RemoteConnectionsPage));
    // Do not await: the future completes only after the dialog pops.
    final editor = openSshProfileEditor(ctx);
    await tester.pumpAndSettle();
    expect(find.byType(TpDialogPageShell), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await editor;
    expect(find.byType(TpDialogPageShell), findsNothing);
    expect(find.text(l10n.sshProfile.sEmpty), findsOneWidget);
  });
```

把第 389-452 行的 `'save does not clear gate'` 测试**从 `final ctx = ...` 到结尾**替换为：

```dart
    final ctx = tester.element(find.byType(RemoteConnectionsPage));
    // ignore: unawaited_futures — completes when the dialog pops
    openSshProfileEditor(ctx);
    await tester.pumpAndSettle();

    // Dialog field order: label(0), host(1), username(2), port(3),
    // private key(4), passphrase(5), password(6).
    await tester.enterText(find.byType(TextField).at(0), 'My Box');
    await tester.enterText(find.byType(TextField).at(1), 'example.com');
    await tester.enterText(find.byType(TextField).at(2), 'alice');
    await tester.enterText(find.byType(TextField).at(6), 'password123');

    await tester.tap(find.text('Add target'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 40 && profileCubit.state.isLoading; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(find.text('APP_CHILD'), findsNothing);
    expect(profileCubit.state.hasProfiles, isTrue);
    expect(find.byType(RemoteConnectionsPage), findsOneWidget);
  });
```

（测试头部 `tester.view.physicalSize = ...` 到 `expect(find.text(l10n.sshProfile.sEmpty), findsOneWidget);` 保持不变。）

- [ ] **Step 3: 迁移 `work_home_step_test.dart` 的测试**

把第 528-558 行从 `final ctx = ...` 到结尾替换为：

```dart
    final ctx = tester.element(find.byType(RemoteConnectionsPage));
    // ignore: unawaited_futures — completes when the dialog pops
    openSshProfileEditor(ctx);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'My Box');
    await tester.enterText(find.byType(TextField).at(1), 'example.com');
    await tester.enterText(find.byType(TextField).at(2), 'alice');
    await tester.enterText(find.byType(TextField).at(6), 'password123');

    await tester.tap(find.text('Add target'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 40 && profileCubit.state.isLoading; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();

    expect(profileCubit.state.hasProfiles, isTrue);
    expect(boundCalls, 0);
  });
```

- [ ] **Step 4: 跑测试，确认失败**

```bash
cd client && dart run tool/run_tests.dart test/pages/startup_gate_test.dart --plain-name "editor dialog opens"
```

Expected: FAIL —— 当前 `openSshProfileEditor` 默认走 `useFullPageEditor: true` 时推的是 `SshProfileSetupPage`，找不到 `TpDialogPageShell`。

- [ ] **Step 5: 简化 `openSshProfileEditor` 并删除文件**

`client/lib/pages/ssh_profiles_page.dart`：删除 `import 'dart:io';`、`import 'ssh_profile_setup_page.dart';`，以及仅为 fullPage 分支服务的 import：`../repositories/ssh_credential_store.dart`、`../services/ssh/ssh_profile_connection_tester.dart`、`../services/terminal/terminal_transport_factory.dart`、`../services/vault/vault_service.dart`。（保留 `../services/storage/home_storage.dart` 等 `SshServersPage` 仍在用的 import。）

把第 178-213 行的 `openSshProfileEditor` 整体替换为：

```dart
Future<void> openSshProfileEditor(
  BuildContext context, {
  SshProfile? profile,
}) async {
  await showSshProfileFormDialog(context, profile: profile);
}
```

删除文件：

```bash
git rm client/lib/pages/ssh_profile_setup_page.dart
```

- [ ] **Step 6: 跑测试与静态分析**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart test/pages/startup_gate_test.dart test/pages/onboarding/work_home_step_test.dart
```

Expected: analyze 无残留 import 报错；两个测试文件全部通过。

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/ssh_profiles_page.dart client/lib/pages/ssh_profile_setup_page.dart client/test/pages/startup_gate_test.dart client/test/pages/onboarding/work_home_step_test.dart
git commit -m "refactor(ssh): use one SSH profile editor on every platform"
```

---

### Task 4: l10n + dialog 私钥可粘贴 + 测试 harness 重构

**Files:**
- Modify: `client/lib/i18n/sshProfile_en.i18n.json`, `client/lib/i18n/sshProfile_zh.i18n.json`
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`
- Test: `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart`

**Interfaces:**
- Consumes: `sshEditorSecretInputs(..., isEditing: ...)`（Task 2）、`showSshProfileFormDialog`（现有）
- Produces: `pumpEditor(WidgetTester, {SshProfile? profile}) -> _EditorHarness` —— Task 5 / Task 6 依赖；新 l10n getter `context.l10n.sshProfile.formIdentityFileImport` / `.formIdentityFileImportFailed`

- [ ] **Step 1: 改 l10n 文案（两个文件同步）**

`client/lib/i18n/sshProfile_en.i18n.json` 中替换以下条目（其余保持不变），并新增两个 key：

```json
  "formCredentialRequired": "Provide a private key or password.",
  "formIdentityFile": "Private key",
  "formIdentityFileBrowse": "Import…",
  "formIdentityFileHelper": "Paste the private key, or import it from a file.",
  "formIdentityFileHint": "-----BEGIN OPENSSH PRIVATE KEY-----",
  "formIdentityFileImport": "Import from file",
  "formIdentityFileImportFailed": "Could not read the selected file; paste the key instead",
  "formPasswordHelper": "Optional if a private key is provided.",
  "formPasswordHint": "Use when no private key is set",
```

保留 `"formIdentityFileMissing": "Identity file not found",` 不动 —— 本任务先不删除任何 key，否则 slang 生成后 dialog 在 Step 5 之前会引用到已消失的 getter。该 key 在 Step 5 后不再被引用，留待后续清理。

`client/lib/i18n/sshProfile_zh.i18n.json` 同步替换：

```json
  "formCredentialRequired": "请提供私钥或密码。",
  "formIdentityFile": "私钥内容",
  "formIdentityFileBrowse": "导入…",
  "formIdentityFileHelper": "可直接粘贴私钥，或从文件导入。",
  "formIdentityFileHint": "-----BEGIN OPENSSH PRIVATE KEY-----",
  "formIdentityFileImport": "从文件导入",
  "formIdentityFileImportFailed": "无法读取所选文件，请直接粘贴私钥",
  "formPasswordHelper": "若已提供私钥则可不填。",
  "formPasswordHint": "未填写私钥时使用",
```

同样保留 `"formIdentityFileMissing": "找不到身份文件",` 不动（理由同上）。

生成：

```bash
cd client && dart run slang
```

Expected: 生成成功，`translations_en.g.dart` / `translations_zh.g.dart` 中出现 `formIdentityFileImport` 与 `formIdentityFileImportFailed` getter。

- [ ] **Step 2: 重构 dialog 测试的 provider 搭建为可复用 helper**

把 `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart` 中 `void main() { ... }` 里的第一个测试整体替换为下面的 helper + 重写后的测试（其余 import 保持不变，另需 `import 'package:teampilot/services/vault/vault_service.dart';` 已存在）：

```dart
class _EditorHarness {
  const _EditorHarness({
    required this.deviceRepository,
    required this.planeRepository,
    required this.credentials,
    required this.deviceCubit,
    required this.planeCubit,
    required this.vault,
  });

  final _RecordingRepository deviceRepository;
  final _RecordingRepository planeRepository;
  final InMemorySshCredentialStore credentials;
  final SshProfileCubit deviceCubit;
  final SshProfileCubit planeCubit;
  final VaultService vault;
}

Future<_EditorHarness> pumpEditor(
  WidgetTester tester, {
  SshProfile? profile,
}) async {
  final deviceRepository = _RecordingRepository();
  final planeRepository = _RecordingRepository();
  final credentials = InMemorySshCredentialStore();
  final deviceCubit = SshProfileCubit(
    profileRepository: deviceRepository,
    credentialStore: credentials,
  );
  final planeCubit = SshProfileCubit(
    profileRepository: planeRepository,
    credentialStore: credentials,
  );
  final vault = await _vault();
  addTearDown(deviceCubit.close);
  addTearDown(planeCubit.close);

  final theme = ThemeData(useMaterial3: true);
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SshProfileRepository>.value(
          value: deviceRepository,
        ),
        RepositoryProvider<SshCredentialStore>.value(value: credentials),
        RepositoryProvider<VaultService>.value(value: vault),
        RepositoryProvider<VaultCredentialCapture>.value(
          value: VaultCredentialCapture(vault: vault),
        ),
        RepositoryProvider<VaultUnlockGate>.value(
          value: VaultUnlockGate(vault: vault, prompt: () async => true),
        ),
      ],
      child: BlocProvider<SshProfileCubit>.value(
        value: deviceCubit,
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: appLocalizationsSupportedLocales,
          locale: const Locale('en'),
          theme: theme,
          home: TpTheme(
            data: TpThemeData.fromColorScheme(
              theme.colorScheme,
              scale: 1.0,
              controlScale: AppTypographyScale.standard.multiplier,
            ),
            child: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<SshProfileRepository>.value(
                  value: planeRepository,
                ),
              ],
              child: BlocProvider<SshProfileCubit>.value(
                value: planeCubit,
                child: Scaffold(
                  body: Builder(
                    builder: (ctx) => TextButton(
                      onPressed: () =>
                          showSshProfileFormDialog(ctx, profile: profile),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return _EditorHarness(
    deviceRepository: deviceRepository,
    planeRepository: planeRepository,
    credentials: credentials,
    deviceCubit: deviceCubit,
    planeCubit: planeCubit,
    vault: vault,
  );
}

void main() {
  testWidgets('the dialog saves through the repository and cubit of the '
      'calling page', (tester) async {
    final h = await pumpEditor(tester, profile: _target);

    // Fields in build order: label, host, username, port, private key,
    // passphrase, password.
    await tester.enterText(find.byType(TextField).at(6), 'new-password');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, hasLength(1));
    expect(h.planeRepository.saves.single.id, _target.id);
    expect(h.planeRepository.saves.single.vaultEntryId, isNotEmpty);
    expect(h.deviceRepository.saves, isEmpty);
    expect(h.planeCubit.state.profiles.single.id, _target.id);
    expect(h.deviceCubit.state.profiles, isEmpty);
    expect(
      await h.vault.readField(
        h.planeRepository.saves.single.vaultEntryId!,
        'password',
      ),
      'new-password',
    );
  });
}
```

注意：原文件里 `_RecordingRepository`、`_FakeStore`、`_vault`、`_target` 定义在 `main()` 之前，**保留它们**；只替换 `main()` 的函数体。

- [ ] **Step 3: 写失败测试（私钥可粘贴）**

在上面 `main()` 内追加：

```dart
  testWidgets('pastes a private key and saves it to the vault', (tester) async {
    final h = await pumpEditor(tester);
    const pem =
        '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n'
        '-----END OPENSSH PRIVATE KEY-----';

    await tester.enterText(find.byType(TextField).at(4), pem);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add target'));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, hasLength(1));
    final entryId = h.planeRepository.saves.single.vaultEntryId;
    expect(entryId, isNotNull);
    expect(await h.vault.readField(entryId!, 'privateKey'), pem);
  });
```

- [ ] **Step 4: 跑测试，确认失败**

```bash
cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart --plain-name "pastes a private key"
```

Expected: FAIL —— 当前 `TextField.at(4)` 是「身份文件路径」，保存时 `_readIdentityFile()` 用 `File(pem)` 读路径抛错，`planeRepository.saves` 为空。

- [ ] **Step 5: 改 dialog**

`client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`：

1. 删除 `import 'dart:io';`，新增 `import 'dart:convert';`（`utf8`）。
2. `_identityFileController` 全部改名为 `_privateKeyController`（声明、initState、dispose）。
3. 删除 `_browseIdentityFile()` 与 `_readIdentityFile()`，替换为：

```dart
  Future<void> _importPrivateKey() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      dialogTitle: context.l10n.sshProfile.formIdentityFileImport,
    );
    final picked = result?.files.firstOrNull;
    if (picked == null) return;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        AppToast.show(
          context,
          message: context.l10n.sshProfile.formIdentityFileImportFailed,
          variant: TpToastVariant.warning,
        );
      }
      return;
    }
    if (!mounted) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    setState(() => _privateKeyController.text = text);
    _formKey.currentState?.setFieldValue('privateKey', text);
  }
```

4. `_usesPasswordAuth` 里 `if (_identityFileController.text.isNotEmpty)` → `if (_privateKeyController.text.isNotEmpty)`。
5. `_save()`：`privateKeyPem` 改为 `usesPassword ? '' : _privateKeyController.text`；`if (!_isEditing && !_usesPasswordAuth && _identityFileController.text.trim().isEmpty)` → `_privateKeyController.text.trim().isEmpty`。
6. `_save()` 里传给 `sshEditorSecretInputs` 增加 `isEditing: _isEditing`。
7. `_testConnection()`：`privateKeyPem: usesPassword ? '' : _privateKeyController.text`。
8. build 里原来常驻的 `_field(id: 'identityFile', ...)` 调用整段替换为 `_privateKeyField(),`（保持常驻，不条件渲染，以免 `find.byType(TextField)` 的索引在认证方式切换时变化）。新增方法：

```dart
  Widget _privateKeyField() {
    final l10n = context.l10n;
    return TpFormField<String>(
      id: 'privateKey',
      initialValue: _privateKeyController.text,
      label: Text(l10n.sshProfile.formIdentityFile),
      builder: (state) => TextField(
        controller: _privateKeyController,
        minLines: 4,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: l10n.sshProfile.formIdentityFileHint,
          helperText: l10n.sshProfile.formIdentityFileHelper,
          suffixIcon: IconButton(
            tooltip: l10n.sshProfile.formIdentityFileImport,
            onPressed: _importPrivateKey,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          errorText: state.hasError ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
        onChanged: state.didChange,
      ),
    );
  }
```

`TextField` 保持为 `TextField`，因此 `find.byType(TextField)` 的 7 个索引不变（Task 3 的测试依赖 `at(6)`）。

- [ ] **Step 6: 跑测试与静态分析**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

Expected: 两个 widget 测试全部通过；analyze 无报错。

- [ ] **Step 7: Commit**

```bash
git add client/lib/i18n/sshProfile_en.i18n.json client/lib/i18n/sshProfile_zh.i18n.json client/lib/l10n/translations_en.g.dart client/lib/l10n/translations_zh.g.dart client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
git commit -m "feat(ssh): paste private keys directly in the unified editor"
```

---

### Task 5: 测试连接改用 owner reader

**Files:**
- Modify: `client/lib/services/ssh/ssh_profile_vault_writer.dart`
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart:246-292`
- Test: `client/test/services/ssh/ssh_profile_vault_writer_test.dart`
- Test: `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `resolveSshVaultFieldReader`
- Produces: `resolveSshEditorTestSecrets` 不再有 `vaultEntryId` 参数

- [ ] **Step 1: 写失败测试**

在 `client/test/services/ssh/ssh_profile_vault_writer_test.dart` 的 `group('editor test credentials', ...)` 内追加：

```dart
    test('plane-row owner credentials feed an editor test connection', () async {
      final vault = await _vault();
      await VaultCredentialCapture(vault: vault).captureSsh(
        profile,
        password: 'secret',
      );
      final reader = resolveSshVaultFieldReader(vault, profile);

      final secrets = await resolveSshEditorTestSecrets(
        authType: SshAuthType.password,
        profileId: profile.id,
        passwordText: '',
        privateKeyPem: '',
        passphraseText: '',
        readVaultField: reader,
        credentialStore: credentials,
      );

      expect(secrets.password, 'secret');
    });
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_vault_writer_test.dart --plain-name "plane-row owner credentials"
```

Expected: 编译失败 —— `resolveSshEditorTestSecrets` 仍要求 `vaultEntryId` 具名参数，且内部 `(vaultEntryId ?? '').isNotEmpty` 门控会丢弃传入的 `readVaultField`。

- [ ] **Step 3: 移除 `vaultEntryId` 参数并改门控**

`ssh_profile_vault_writer.dart` 的 `resolveSshEditorTestSecrets`：从签名中删除 `required String? vaultEntryId,`，把第一行

```dart
  final readVault = (vaultEntryId ?? '').isNotEmpty ? readVaultField : null;
```

改为

```dart
  final readVault = readVaultField;
```

`client/test/services/ssh/ssh_profile_vault_writer_test.dart` 中 3 处 `resolveSshEditorTestSecrets(...)` 调用全部删除 `vaultEntryId: ...` 行；其中 `'empty password falls back to the vault, then the keychain'` 的局部 helper 改为：

```dart
      Future<SshEditorSecretInputs> resolve({required String? stored}) {
        return resolveSshEditorTestSecrets(
          authType: SshAuthType.password,
          profileId: 'p1',
          passwordText: '',
          privateKeyPem: '',
          passphraseText: '',
          readVaultField: stored == null ? null : (_) async => stored,
          credentialStore: credentials,
        );
      }
```

并把该测试的两处 `resolve(vaultEntryId: 'v1', stored: 'stored')` / `resolve(vaultEntryId: null, stored: null)` 改为 `resolve(stored: 'stored')` / `resolve(stored: null)`。`'private key falls back to the vault, then the keychain'` 的 helper 同样删除 `required String? vaultEntryId` 与 `vaultEntryId:` 参数，两个调用改为 `resolve(storedKey: 'vault-pem')` / `resolve(storedKey: null)`。

- [ ] **Step 4: 改 dialog 的 `_testConnection`**

`ssh_profile_form_dialog.dart` 的 `_testConnection` 里，把

```dart
      final linkedId = widget.initialProfile?.vaultEntryId ?? '';
      final vault = linkedId.isNotEmpty ? context.read<VaultService>() : null;
```

替换为

```dart
      final vault = context.read<VaultService>();
```

把传给 `resolveSshEditorTestSecrets` 的

```dart
        vaultEntryId: linkedId,
        readVaultField: vault == null
            ? null
            : (field) => vault.readField(linkedId, field),
```

替换为

```dart
        readVaultField: resolveSshVaultFieldReader(vault, profile),
```

（`profile` 即本方法里 `final profile = _buildProfile();`，已在作用域内。）

- [ ] **Step 5: 跑测试与静态分析**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart test/services/ssh/ssh_profile_vault_writer_test.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

Expected: 全部通过；analyze 无报错。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/ssh/ssh_profile_vault_writer.dart client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart client/test/services/ssh/ssh_profile_vault_writer_test.dart
git commit -m "fix(ssh): test connection reads owner credentials for plane rows"
```

---

### Task 6: 编辑态 reveal 回归测试与全量验证

**Files:**
- Test: `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart`

**Interfaces:**
- Consumes: `pumpEditor`（Task 4）、`vaultOwnerKindSshProfile`、`VaultCredentialCapture.captureSsh`

- [ ] **Step 1: 写失败/回归测试（锁住用户所报现象）**

在 `ssh_profile_form_dialog_test.dart` 的 `main()` 内追加：

```dart
  testWidgets('reveals the saved password for a plane row with no vault link', (
    tester,
  ) async {
    final h = await pumpEditor(tester, profile: _target);
    await VaultCredentialCapture(vault: h.vault).captureSsh(
      _target,
      password: 's3cret',
    );

    expect(find.byKey(const ValueKey('password-visibility-toggle')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('password-visibility-toggle')));
    await tester.pumpAndSettle();

    expect(find.text('s3cret'), findsOneWidget);
  });
```

注：`_target` 无 `vaultEntryId`，正是「SSH 服务器」页平面行的形态；`TpPasswordInput._suffixWithToggle` 的 key 为 `ValueKey('password-visibility-toggle')`。

- [ ] **Step 2: 确认回归测试通过**

该测试针对的是 `52f0b06ad` 已加到 dialog 的 `_revealPassword`；统一编辑器后移动端自动获得它。跑：

```bash
cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart --plain-name "reveals the saved password"
```

Expected: PASS。若 FAIL，检查 `VaultService` 是否在 `pumpEditor` 的 providers 中，以及 `authorizeVaultReveal` 对 keychain backend（`isEncrypted == false`）是否直接返回 true。

- [ ] **Step 3: 全量验证（只在收尾跑一次）**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart
```

Expected: analyze 无 error；测试套件全部通过。此命令耗时较长，放后台执行并等待结果。

- [ ] **Step 4: 确认 spec 的关键回归未被破坏**

```bash
cd client && dart run tool/run_tests.dart test/repositories/plane_ssh_profile_repository_test.dart --plain-name "save never writes the vault reference"
```

Expected: PASS —— 平面记录仍不含 `vaultEntryId`。

- [ ] **Step 5: Commit**

```bash
git add client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
git commit -m "test(ssh): cover password reveal on a plane-row editor"
```

---

## 自审记录

- **Spec coverage**：目标 1 → Task 3；目标 2 → Task 6（能力由 Task 3 统一编辑器获得）+ Task 1/5（owner 解析）；目标 3 → Task 5；目标 4 → Task 2；目标 5 → Task 4。非目标（安全模型、`confirmDeleteSshProfile`、徽标、`showRemoteConfig`、跨设备凭据同步）均无对应改动任务。
- **Placeholder scan**：无 TBD/TODO；每个 code step 均给出完整代码或完整替换片段；命令与期望结果明确。
- **Type consistency**：`resolveSshVaultFieldReader`（Task 1）在 Task 5 使用；`sshEditorSecretInputs(..., isEditing:)`（Task 2）在 Task 4 使用；`pumpEditor` → `_EditorHarness`（Task 4）在 Task 6 使用；`resolveSshEditorTestSecrets` 去掉 `vaultEntryId` 后，全部 4 个调用点（dialog + 3 处测试）在 Task 5 同步更新。
- **字段索引一致性**：dialog 的 7 个 `TextField` 顺序在 Task 4 后保持 label/host/username/port/privateKey/passphrase/password，Task 3 与 Task 4 的测试都依赖 `at(6)` = password、`at(4)` = private key。
- **l10n 顺序**：Task 4 Step 1 只新增/改文案、不删 key，保证 slang 生成后到 Step 5 改 dialog 之前的中间态仍可编译；`formIdentityFileMissing` 在 Step 5 后成为未引用 key，不在本计划清理。
