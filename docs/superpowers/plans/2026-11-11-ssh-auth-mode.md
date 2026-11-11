# SSH 目标编辑：显式认证方式切换 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 SSH 目标编辑器加一个「密码 | 私钥」显式切换，按模式只渲染对应凭据字段，并在编辑态切换认证方式时先确认再保存。

**Architecture:** 编辑器新增 `_authType` 状态（初值来自 `profile.authType`，新建默认 `password`），用 shared_ui `TpSegmentedControl` 驱动；字段按模式条件渲染，删除“按内容推断模式”的 `_usesPasswordAuth`。保存走现有的三态凭据写入器，另加一次确认弹窗避免静默删除另一种凭据。

**Tech Stack:** Flutter、shared_ui（`TpSegmentedControl`、`TpFormFieldLayout`、`TpDialog`）、slang l10n、flutter_test。

## Global Constraints

- 绝不直接跑 `flutter test`；一律 `cd client && dart run tool/run_tests.dart <paths>`。
- l10n 改 `client/lib/i18n/sshProfile_en.i18n.json` / `sshProfile_zh.i18n.json`，然后 `cd client && dart run slang`。
- 工作区可能有其它会话的并发改动：每个任务只用 `git commit -- <本任务文件>` 提交，禁止 `git add -A` / `git commit -a`。
- `dart run slang` 会重写整个 `translations_*.g.dart`；提交前必须 `git diff` 确认 diff 只含本次 sshProfile 的键，若混入其它命名空间说明有并发改动，先停下核对。
- 不改 `SshProfile` / `SshAuthType` 模型、JSON 或保险库写入契约。
- 新建目标必须提供密码或私钥：任一模式凭据为空都提示 `formCredentialRequired` 并中止保存。

---

### Task 1: 显式认证方式切换 + 按模式条件渲染

**Files:**
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`
- Modify: `client/lib/i18n/sshProfile_en.i18n.json`
- Modify: `client/lib/i18n/sshProfile_zh.i18n.json`
- Generated: `client/lib/l10n/translations_en.g.dart`, `client/lib/l10n/translations_zh.g.dart`
- Test: `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart`

**Interfaces:**
- Produces: `late SshAuthType _authType`（`password` / `privateKey`）；`Widget _authTypeField()`；
  分段控件 key `const ValueKey('ssh-auth-type')`；l10n `sshProfile.formAuthType` / `sshProfile.formAuthPrivateKey`。
- Consumes: `SshAuthType`（`models/ssh_profile.dart` 已导出）、`TpSegmentedControl` / `TpFormFieldLayout`（`package:shared_ui/shared_ui.dart`，文件已 import）。

- [ ] **Step 1: 写失败测试（新增 4 个 + 改造现有 4 个）**

在 `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart` 的 `main()` 末尾、最后一个用例之后加入：

```dart
  testWidgets('defaults to password mode and hides the key fields', (
    tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsNothing);
    expect(find.text('Key passphrase'), findsNothing);
    expect(find.text('Login password'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsOneWidget);
    expect(find.text('Key passphrase'), findsOneWidget);
    expect(find.text('Login password'), findsNothing);
  });

  testWidgets('edit initializes the mode from the profile auth type', (
    tester,
  ) async {
    const keyed = SshProfile(
      id: 'p2',
      name: 'keyed',
      host: 'example.com',
      username: 'alice',
      authType: SshAuthType.privateKey,
    );
    await pumpEditor(tester, profile: keyed);

    expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsOneWidget);
    expect(find.text('Key passphrase'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Password'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Leave empty to keep saved password'), findsOneWidget);
    expect(find.text('-----BEGIN OPENSSH PRIVATE KEY-----'), findsNothing);
  });

  testWidgets('creating a password target requires a password', (tester) async {
    final h = await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).at(1), 'example.com');

    await tester.tap(find.text('Add target'));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, isEmpty);
  });

  testWidgets('creating a private-key target requires a key', (tester) async {
    final h = await pumpEditor(tester);
    await tester.enterText(find.byType(TextField).at(1), 'example.com');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add target'));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, isEmpty);
  });
```

改造现有 4 个用例：

1. `saves through the repository and cubit of the calling page` —— 密码字段下标 6 → 4：

```dart
    await tester.enterText(find.byType(TextField).at(4), 'new-password');
```

2. `pastes a private key and saves it to the vault` —— 先切到私钥模式：

```dart
    await tester.enterText(find.byType(TextField).at(1), 'example.com');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(4), pem);
```

3. `reveals the saved password for a plane row with no vault link` —— 密码模式只有一个 reveal：

```dart
    final toggles = find.byKey(const ValueKey('password-visibility-toggle'));
    expect(toggles, findsOneWidget);
    await tester.ensureVisible(toggles);
    await tester.pumpAndSettle();
    await tester.tap(toggles);
    await tester.pumpAndSettle();
```

4. `private key field stays multiline under the app single-line input theme` —— 先切模式：

```dart
    await pumpEditor(tester, appInputTheme: true);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();
    final privateKey = find.byType(TextField).at(4);
    expect(tester.getSize(privateKey).height, greaterThan(48));
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```bash
cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

Expected: 多个用例 FAIL（找不到 `ssh-auth-type` key、找不到 `Login password`、下标错位）。

- [ ] **Step 3: 改 l10n（英/中）**

`client/lib/i18n/sshProfile_en.i18n.json`：

- 删除 `"formPasswordHelper": "Optional if a private key is provided.",`
- `"formPasswordHint"` 改为 `"Login password"`
- 按字母序加入：

```json
  "formAuthPrivateKey": "Private key",
  "formAuthType": "Authentication",
```

`client/lib/i18n/sshProfile_zh.i18n.json`：

- 删除 `"formPasswordHelper": "若已提供私钥则可不填。",`
- `"formPasswordHint"` 改为 `"登录密码"`
- 按字母序加入：

```json
  "formAuthPrivateKey": "私钥",
  "formAuthType": "认证方式",
```

Run:
```bash
cd client && dart run slang
```

Expected: `translations_en.g.dart` / `translations_zh.g.dart` 重新生成，新增两个 getter，`formPasswordHelper` getter 消失。

注意：此刻代码还在引用 `formPasswordHelper`，会短暂编译不过；Step 5 移除引用后恢复，Step 7 才重新跑测试。

- [ ] **Step 4: 改表单状态**

在 `_SshProfileFormDialogState` 的字段声明区（`late final TextEditingController _passwordController;` 之后）加入：

```dart
  late SshAuthType _authType;
```

在 `initState()` 末尾、`_passwordController = TextEditingController();` 之后加入：

```dart
    _authType =
        widget.initialProfile?.authType ?? SshAuthType.password;
```

删除整个 `_usesPasswordAuth` getter（原 130-134 行）。

`_buildProfile()` 中把：

```dart
      authType: _usesPasswordAuth
          ? SshAuthType.password
          : SshAuthType.privateKey,
```

替换为：

```dart
      authType: _authType,
```

`_save()` 与 `_testConnection()` 中把：

```dart
      final usesPassword = _usesPasswordAuth;
```

替换为：

```dart
      final usesPassword = _authType == SshAuthType.password;
```

`_save()` 的新建目标凭据守卫也引用了 `_usesPasswordAuth`，一并改为按模式判断：

```dart
    if (!_isEditing) {
      final missingCredential = _authType == SshAuthType.password
          ? _passwordController.text.isEmpty
          : _privateKeyController.text.trim().isEmpty;
      if (missingCredential) {
        AppToast.show(
          context,
          message: context.l10n.sshProfile.formCredentialRequired,
          variant: TpToastVariant.warning,
        );
        return null;
      }
    }
```

- [ ] **Step 5: 改 build 的凭据区**

把当前这段（`const SizedBox(height: 16),` 之后到密码 `_field(...)` 结束）：

```dart
        const SizedBox(height: 16),
        _privateKeyField(),
        const SizedBox(height: 12),
        _field(
          id: 'passphrase',
          controller: _passphraseController,
          label: l10n.sshProfile.formPassphrase,
          hint: l10n.sshProfile.formPassphraseHint,
          obscure: true,
        ),
        const SizedBox(height: 12),
        _field(
          id: 'password',
          controller: _passwordController,
          label: l10n.sshProfile.formPassword,
          hint: _isEditing
              ? l10n.sshProfile.formPasswordHintEdit
              : l10n.sshProfile.formPasswordHint,
          helper: l10n.sshProfile.formPasswordHelper,
          obscure: true,
          onChanged: () => setState(() {}),
          onReveal: _revealPassword,
        ),
```

替换为：

```dart
        const SizedBox(height: 16),
        _authTypeField(),
        const SizedBox(height: 12),
        if (_authType == SshAuthType.password)
          _field(
            id: 'password',
            controller: _passwordController,
            label: l10n.sshProfile.formPassword,
            hint: _isEditing
                ? l10n.sshProfile.formPasswordHintEdit
                : l10n.sshProfile.formPasswordHint,
            obscure: true,
            onReveal: _revealPassword,
          )
        else ...[
          _privateKeyField(),
          const SizedBox(height: 12),
          _field(
            id: 'passphrase',
            controller: _passphraseController,
            label: l10n.sshProfile.formPassphrase,
            hint: l10n.sshProfile.formPassphraseHint,
            obscure: true,
          ),
        ],
```

- [ ] **Step 6: 新增 `_authTypeField()`**

在 `_privateKeyField()` 之前加入：

```dart
  Widget _authTypeField() {
    final l10n = context.l10n;
    return TpFormFieldLayout(
      label: Text(l10n.sshProfile.formAuthType),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TpSegmentedControl(
          key: const ValueKey('ssh-auth-type'),
          totalSwitches: 2,
          initialLabelIndex: _authType.index,
          labels: [
            l10n.sshProfile.formPassword,
            l10n.sshProfile.formAuthPrivateKey,
          ],
          onToggle: (index) {
            if (index == null || index < 0 || index > 1) return;
            setState(() => _authType = SshAuthType.values[index]);
          },
        ),
      ),
    );
  }
```

- [ ] **Step 7: 跑测试确认通过**

Run:
```bash
cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

Expected: 全部 PASS（含新增 2 个）。

- [ ] **Step 8: 静态分析**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/ssh_profiles/ssh_profile_form_dialog.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

Expected: `No issues found!`

- [ ] **Step 9: 提交**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add -- client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart \
  client/lib/i18n/sshProfile_en.i18n.json \
  client/lib/i18n/sshProfile_zh.i18n.json \
  client/lib/l10n/translations_en.g.dart \
  client/lib/l10n/translations_zh.g.dart \
  client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
git commit -m "feat(ssh): add an explicit auth-mode switch to the target editor" -- \
  client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart \
  client/lib/i18n/sshProfile_en.i18n.json \
  client/lib/i18n/sshProfile_zh.i18n.json \
  client/lib/l10n/translations_en.g.dart \
  client/lib/l10n/translations_zh.g.dart \
  client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

---

### Task 2: 编辑态切换认证方式前确认

**Files:**
- Modify: `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`
- Modify: `client/lib/i18n/sshProfile_en.i18n.json`
- Modify: `client/lib/i18n/sshProfile_zh.i18n.json`
- Generated: `client/lib/l10n/translations_en.g.dart`, `client/lib/l10n/translations_zh.g.dart`
- Test: `client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `_authType`、`_isEditing`、`_save({required bool notify})`；`TpDialog` / `TpDialogHeader`（shared_ui）。
- Produces: `Future<bool> _confirmAuthTypeChange()`。

- [ ] **Step 1: 写失败测试**

在 `main()` 末尾加入：

```dart
  testWidgets('switching auth mode on edit requires confirmation', (
    tester,
  ) async {
    final h = await pumpEditor(tester, profile: _target);
    await VaultCredentialCapture(vault: h.vault).captureSsh(
      _target,
      password: 'old-pass',
    );
    const pem =
        '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n'
        '-----END OPENSSH PRIVATE KEY-----';

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('ssh-auth-type')),
        matching: find.text('Private key'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(4), pem);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Switch authentication?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ssh-auth-change-cancel')));
    await tester.pumpAndSettle();
    expect(h.planeRepository.saves, isEmpty);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ssh-auth-change-confirm')));
    await tester.pumpAndSettle();

    expect(h.planeRepository.saves, hasLength(1));
    expect(h.planeRepository.saves.single.authType, SshAuthType.privateKey);
    final entryId = h.planeRepository.saves.single.vaultEntryId!;
    expect(await h.vault.readField(entryId, 'privateKey'), pem);
    expect(await h.vault.readField(entryId, 'password'), isNull);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run:
```bash
cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart --plain-name "switching auth mode on edit requires confirmation"
```

Expected: FAIL — `find.text('Switch authentication?')` 找不到（保存直接完成，`saves` 已有 1 条）。

- [ ] **Step 3: 改 l10n（英/中）**

`client/lib/i18n/sshProfile_en.i18n.json` 按字母序加入：

```json
  "formAuthChangeBody": "Saving will remove the credential stored for the other authentication method.",
  "formAuthChangeConfirm": "Switch and save",
  "formAuthChangeTitle": "Switch authentication?",
```

`client/lib/i18n/sshProfile_zh.i18n.json` 按字母序加入：

```json
  "formAuthChangeBody": "保存后会清除该目标另一种认证方式已保存的凭据。",
  "formAuthChangeConfirm": "切换并保存",
  "formAuthChangeTitle": "切换认证方式？",
```

Run:
```bash
cd client && dart run slang
```

- [ ] **Step 4: 加确认方法**

在 `_save` 之前加入：

```dart
  Future<bool> _confirmAuthTypeChange() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.sshProfile.formAuthChangeTitle),
            const SizedBox(height: 12),
            Text(l10n.sshProfile.formAuthChangeBody),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('ssh-auth-change-cancel'),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('ssh-auth-change-confirm'),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.sshProfile.formAuthChangeConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return confirmed ?? false;
  }
```

- [ ] **Step 5: 在 `_save` 开头接入确认**

把：

```dart
  Future<SshProfile?> _save({required bool notify}) async {
    if (_formKey.currentState?.validate() != true) return null;
    final profile = _buildProfile();
```

改为：

```dart
  Future<SshProfile?> _save({required bool notify}) async {
    if (_formKey.currentState?.validate() != true) return null;
    if (_isEditing && _authType != widget.initialProfile!.authType) {
      final confirmed = await _confirmAuthTypeChange();
      if (!confirmed || !mounted) return null;
    }
    final profile = _buildProfile();
```

- [ ] **Step 6: 跑测试确认通过**

Run:
```bash
cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

Expected: 全部 PASS（含新增确认用例）。

- [ ] **Step 7: 静态分析**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/ssh_profiles/ssh_profile_form_dialog.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

Expected: `No issues found!`

- [ ] **Step 8: 提交**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add -- client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart \
  client/lib/i18n/sshProfile_en.i18n.json \
  client/lib/i18n/sshProfile_zh.i18n.json \
  client/lib/l10n/translations_en.g.dart \
  client/lib/l10n/translations_zh.g.dart \
  client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
git commit -m "feat(ssh): confirm auth-mode changes before dropping the other credential" -- \
  client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart \
  client/lib/i18n/sshProfile_en.i18n.json \
  client/lib/i18n/sshProfile_zh.i18n.json \
  client/lib/l10n/translations_en.g.dart \
  client/lib/l10n/translations_zh.g.dart \
  client/test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

---

### Task 3: 交付前全量验证

**Files:** 无（只跑命令）。

- [ ] **Step 1: 全量静态分析**

Run:
```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 退出码 0；本次改动文件无 issue（仓库其它位置可能存在既有 info/warning）。

- [ ] **Step 2: 跑目标测试文件（再次确认）**

Run:
```bash
cd client && dart run tool/run_tests.dart test/pages/ssh_profiles/ssh_profile_form_dialog_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 3: 跑全量测试（后台）**

Run:
```bash
cd client && dart run tool/run_tests.dart
```

Expected: 除工作区中其它会话正在改动的模块外，全部 PASS。若出现失败，先确认是否落在本次改动文件
（`ssh_profile_form_dialog.dart` / 其测试 / l10n 生成物）内；不在则记录为并发改动导致，不擅自修复。
