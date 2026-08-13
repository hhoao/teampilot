# PromptProvisionCapability 统一成员 prompt 注入 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 `PromptProvisionCapability`（registry 能力）统一五个 CLI 的成员 prompt 组合/写入/传输，装配点只调 `provision()`。

**Architecture:** 每 CLI 一个实现（`cli/{cli}/capabilities/prompt_provision.dart`）全权拥有内容组合 + 写入目标 + 传输 env 贡献；共享组合层 `MemberRoleProvision.composeRolePrompt` 扩展 `additionalDirectories`（非空追加 "## Workspace directories" 章节）；`ConfigProfileDelegate.resolveAppendSystemPromptPath` 删除（capability 写完直接返回路径）。cursor 的实现注入 `CursorHomeProvisioner` 保持写入时序。

**Tech Stack:** Dart / Flutter（flutter_bloc 仓库）、flutter_test、现有 `ConfigProfileService` 测试基建。

**Spec:** `docs/superpowers/specs/2026-08-13-prompt-provision-capability-design.md`

## Global Constraints

- 运行验证命令：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`（每任务至少跑受影响测试文件）
- 不做向下兼容；`resolveAppendSystemPromptPath` 最终必须删除（接口 + service + infrastructure + 测试 fake）
- 只有 opencode 的实现向 prompt 传 `additionalDirectories`；claude/flashskyai/codex/cursor 传 `const []`（`--add-dir`/trust 覆盖目录访问）
- `permission.external_directory` 合并留在 opencode config_profile（config ≠ prompt）
- 每任务结尾 commit；commit message 仿仓库风格（`feat:` / `refactor:`）
- 不写注释除非必要；l10n 不动（prompt 文案是英文，沿用现有措辞）
- 能力接口字段：`paths` / `scope` 可空（cursor 装配点拿不到），各实现对自己需要的字段做非空断言（`StateError`）

---

### Task 1: 接口 + 共享组合层（MemberRoleProvision dirs 章节）

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/prompt_provision_capability.dart`
- Modify: `client/lib/services/session/member_role_provision.dart`
- Modify: `client/lib/services/cli/cursor/provider/cursor_role_rule_writer.dart`
- Test: `client/test/services/session/member_role_provision_prompt_test.dart`（新建）

**Interfaces:**
- Produces:
  - `abstract interface class PromptProvisionCapability implements CliCapability { Future<PromptProvisionContribution> provision(PromptProvisionContext ctx); }`
  - `class PromptProvisionContext { final ConfigProfileDelegate? paths; final LaunchProfileScope? scope; final TeamMemberConfig? member; final bool forceTeamLeadDelegateMode; final bool mixed; final bool pushDelivery; final List<String> additionalDirectories; final String? memberHome; }`（const 构造，全部可选）
  - `class PromptProvisionContribution { final Map<String, String> environment; final bool written; }`（const 构造）
  - `MemberRoleProvision.composeWorkspaceDirectoriesPrompt(Iterable<String> directories) → String`（空输入返回 `''`）
  - `MemberRoleProvision.composeRolePrompt({required TeamMemberConfig member, bool forceTeamLeadDelegateMode = false, bool mixed = false, bool pushDelivery = false, List<String> additionalDirectories = const []}) → String`（`additionalDirectories` 非空时在末尾追加 `composeWorkspaceDirectoriesPrompt` 的输出，章节与 role body 之间用空行分隔）
  - `MemberRoleProvision.syncRolePromptFile({required Filesystem fs, required String memberToolDir, required TeamMemberConfig member, bool forceTeamLeadDelegateMode = false, bool mixed = false, List<String> additionalDirectories = const []}) → Future<String?>`（参数透传给 composeRolePrompt）

- [ ] **Step 1: 写接口文件**

`client/lib/services/cli/registry/capabilities/prompt_provision_capability.dart`:

```dart
import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../cli_capability.dart';
import '../config_profile/config_profile_context.dart';
import '../config_profile/config_profile_scope.dart';

/// 每 CLI 声明"成员 prompt 组合 + 写入目标 + 传输贡献"。
///
/// 装配点（config_profile / cursor home provisioner）只调 [provision] 并合并
/// [PromptProvisionContribution]；prompt 逻辑全部收敛到实现里。
/// 各实现只读自己需要的 ctx 字段，并对其做非空断言：
/// - claude / flashskyai / codex / opencode：需要 [PromptProvisionContext.paths]
///   与 [PromptProvisionContext.scope]（sessionToolDir 定位）；
/// - cursor：需要 [PromptProvisionContext.memberHome]。
abstract interface class PromptProvisionCapability implements CliCapability {
  Future<PromptProvisionContribution> provision(PromptProvisionContext ctx);
}

class PromptProvisionContext {
  const PromptProvisionContext({
    this.paths,
    this.scope,
    this.member,
    this.forceTeamLeadDelegateMode = false,
    this.mixed = false,
    this.pushDelivery = false,
    this.additionalDirectories = const [],
    this.memberHome,
  });

  final ConfigProfileDelegate? paths;
  final LaunchProfileScope? scope;
  final TeamMemberConfig? member;
  final bool forceTeamLeadDelegateMode;
  final bool mixed;
  final bool pushDelivery;

  /// 已 normalize 的工作面路径；只有 opencode 的实现把它拼进 prompt。
  final List<String> additionalDirectories;

  /// cursor 专用：fake HOME，由装配点解析后传入。
  final String? memberHome;
}

class PromptProvisionContribution {
  const PromptProvisionContribution({
    this.environment = const {},
    this.written = false,
  });

  /// 传输 env（claude/flashskyai 的 `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE`）。
  final Map<String, String> environment;

  /// 是否发生了写入（装配点借此并入 changed）。
  final bool written;
}
```

- [ ] **Step 2: 扩展 MemberRoleProvision**

在 `client/lib/services/session/member_role_provision.dart` 中（`composeMemberRoleBody` 之前）新增:

```dart
/// Composes the AGENTS.md section listing workspace additional directories.
/// Tells the agent the directories exist and that absolute paths are required
/// (they live outside the opencode project root).
static String composeWorkspaceDirectoriesPrompt(Iterable<String> directories) {
  final dirs = directories
      .map((d) => d.trim())
      .where((d) => d.isNotEmpty)
      .toList(growable: false);
  if (dirs.isEmpty) return '';
  final body = StringBuffer(
    '## Workspace directories\n'
    'This session can also access the following directories outside the '
    'project root. Read and edit them using absolute paths.\n',
  );
  for (final dir in dirs) {
    body.writeln('- $dir');
  }
  return body.toString();
}
```

修改 `composeRolePrompt`：签名加 `List<String> additionalDirectories = const []`，返回前追加：

```dart
    final dirsPrompt =
        composeWorkspaceDirectoriesPrompt(additionalDirectories);
    if (dirsPrompt.isNotEmpty) {
      body.writeln();
      body.write(dirsPrompt.trim());
    }
    return body.toString();
```

修改 `syncRolePromptFile`：签名加 `List<String> additionalDirectories = const []`，`composeRolePrompt(...)` 调用处透传 `additionalDirectories: additionalDirectories`。

修改 `client/lib/services/cli/cursor/provider/cursor_role_rule_writer.dart` 的 `CursorRoleRuleWriter.sync`：签名加 `List<String> additionalDirectories = const []`，`MemberRoleProvision.composeRolePrompt(...)` 调用处透传 `additionalDirectories: additionalDirectories`（cursor 本任务起传 `const []`，参数保留为扩展点）。

- [ ] **Step 3: 写组合层测试**

`client/test/services/session/member_role_provision_prompt_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/member_role_provision.dart';

void main() {
  test('composeWorkspaceDirectoriesPrompt lists absolute paths', () {
    final prompt = MemberRoleProvision.composeWorkspaceDirectoriesPrompt(
      <String>['/repo/a', '/repo/b'],
    );
    expect(prompt, contains('## Workspace directories'));
    expect(prompt, contains('- /repo/a'));
    expect(prompt, contains('- /repo/b'));
    expect(prompt, contains('absolute paths'));
  });

  test('composeWorkspaceDirectoriesPrompt is empty without dirs', () {
    expect(
      MemberRoleProvision.composeWorkspaceDirectoriesPrompt(const []),
      isEmpty,
    );
    expect(
      MemberRoleProvision.composeWorkspaceDirectoriesPrompt(const ['  ']),
      isEmpty,
    );
  });

  test('composeRolePrompt appends workspace directories section', () {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      responsibilities: 'You are the reviewer.',
    );
    final prompt = MemberRoleProvision.composeRolePrompt(
      member: member,
      additionalDirectories: const ['/repo/a'],
    );
    expect(prompt, contains('You are the reviewer.'));
    expect(prompt, contains('## Workspace directories'));
    expect(prompt, contains('- /repo/a'));
  });

  test('composeRolePrompt without dirs keeps body unchanged', () {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      responsibilities: 'You are the reviewer.',
    );
    final withDirs = MemberRoleProvision.composeRolePrompt(
      member: member,
      additionalDirectories: const [],
    );
    final without = MemberRoleProvision.composeRolePrompt(member: member);
    expect(withDirs, without);
  });
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `flutter test test/services/session/member_role_provision_prompt_test.dart`
Expected: 4 PASS。再跑 `flutter test test/services/cli/config_profile/opencode_external_directories_test.dart` 确认现有 opencode 行为不受影响（旧组合函数仍在本任务后删除）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/prompt_provision_capability.dart client/lib/services/session/member_role_provision.dart client/test/services/session/member_role_provision_prompt_test.dart
git commit -m "feat: add PromptProvisionCapability interface and shared prompt composition layer"
```

---

### Task 2: opencode 迁移（首个消费者）

**Files:**
- Create: `client/lib/services/cli/opencode/capabilities/prompt_provision.dart`
- Modify: `client/lib/services/cli/opencode/capabilities/config_profile.dart`
- Modify: `client/lib/services/cli/opencode/opencode_tool.dart`
- Modify: `client/test/services/cli/config_profile/opencode_external_directories_test.dart`

**Interfaces:**
- Consumes: Task 1 的接口 + `composeWorkspaceDirectoriesPrompt` / `composeRolePrompt(+additionalDirectories)`
- Produces: `OpencodePromptProvisionCapability implements PromptProvisionCapability`（const，`static const toolId = 'opencode'`，`static const agentsFileName = 'AGENTS.md'`）

- [ ] **Step 1: 写失败测试（capability 单测）**

在 `client/test/services/cli/config_profile/opencode_external_directories_test.dart` 中替换 `composeOpencodeWorkspaceDirectoriesPrompt` 相关两个测试（组合测试已迁往 Task 1），新增：

```dart
  test(
    'OpencodePromptProvisionCapability writes role + dirs into AGENTS.md',
    () async {
      final base = await Directory.systemTemp.createTemp('opencode_prompt_');
      addTearDown(() async {
        if (await base.exists()) await base.delete(recursive: true);
      });
      final fs = LocalFilesystem();
      final service = ConfigProfileService(
        basePath: base.path,
        fs: fs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
      );
      const member = TeamMemberConfig(
        id: 'm1',
        name: 'Member',
        model: 'test',
        responsibilities: 'You are the reviewer.',
      );
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
        memberId: 'm1',
      );

      final contribution =
          await const OpencodePromptProvisionCapability().provision(
            PromptProvisionContext(
              paths: service,
              scope: scope,
              member: member,
              additionalDirectories: const ['/abs/missing/repo'],
            ),
          );

      expect(contribution.written, isTrue);
      expect(contribution.environment, isEmpty);
      final opencodeDir = service.sessionToolDir(
        scope.workspaceId,
        scope.sessionId,
        'opencode',
        memberId: scope.memberId,
      );
      final agents = await fs.readString(
        '$opencodeDir/${OpencodePromptProvisionCapability.agentsFileName}',
      );
      expect(agents, isNotNull);
      expect(agents, contains('You are the reviewer.'));
      expect(agents, contains('## Workspace directories'));
      expect(agents, contains('- /abs/missing/repo'));
    },
  );

  test('OpencodePromptProvisionCapability skips without scope', () async {
    final contribution =
        await const OpencodePromptProvisionCapability().provision(
          const PromptProvisionContext(),
        );
    expect(contribution.written, isFalse);
  });
```

运行确认失败：`flutter test test/services/cli/config_profile/opencode_external_directories_test.dart`（`OpencodePromptProvisionCapability` / `PromptProvisionContext` 未定义，编译失败即失败）。

- [ ] **Step 2: 实现 capability**

`client/lib/services/cli/opencode/capabilities/prompt_provision.dart`:

```dart
import '../../../../models/team_config.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../../../../services/session/member_role_provision.dart';

/// opencode 把成员 prompt（role + workspace dirs 章节）写入会话配置目录的
/// `AGENTS.md`；opencode 从 config dir 自动加载为全局指令，无 flag 传输。
final class OpencodePromptProvisionCapability
    implements PromptProvisionCapability {
  const OpencodePromptProvisionCapability();

  static const toolId = 'opencode';
  static const agentsFileName = 'AGENTS.md';

  @override
  Future<PromptProvisionContribution> provision(
    PromptProvisionContext ctx,
  ) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    if (paths == null || scope == null) {
      return const PromptProvisionContribution();
    }
    final member = ctx.member;
    final body = <String>[
      if (member != null && member.isValid)
        MemberRoleProvision.composeRolePrompt(
          member: member,
          forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
          mixed: ctx.mixed,
        ).trim(),
      MemberRoleProvision.composeWorkspaceDirectoriesPrompt(
        ctx.additionalDirectories,
      ).trim(),
    ].join('\n\n');
    if (body.isEmpty) return const PromptProvisionContribution();
    final opencodeDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    await paths.fs.atomicWrite(
      paths.joinWork(opencodeDir, agentsFileName),
      '$body\n',
    );
    return const PromptProvisionContribution(written: true);
  }
}
```

注意：目录章节在 role body **之外**独立拼接（与现有 `_writeMemberIdentity` 行为一致：member 无效时仍写 dirs-only 的 AGENTS.md）。

- [ ] **Step 3: 迁移 config_profile**

`client/lib/services/cli/opencode/capabilities/config_profile.dart`:

1. 删除 `composeOpencodeWorkspaceDirectoriesPrompt` 函数（Task 1 已在 MemberRoleProvision 提供共享版本）。
2. 删除 `_writeMemberIdentity` 方法。
3. 类加字段与构造参数：

```dart
  const OpencodeConfigProfileCapability({
    this.promptProvision = const OpencodePromptProvisionCapability(),
    ...
  });

  final PromptProvisionCapability promptProvision;
```

（已有 `mcpConfigWriter` 等字段的写法保持一致。）

4. `contributeLaunch` 中替换 `_writeMemberIdentity` 调用块（原 `if (await _writeMemberIdentity(...)) { changed = true; }`）为：

```dart
    final promptContribution = await promptProvision.provision(
      PromptProvisionContext(
        paths: paths,
        scope: ctx.scope,
        member: member,
        forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
        mixed: mixed,
        additionalDirectories: workDirs,
      ),
    );
    if (promptContribution.written) {
      changed = true;
    }
```

（`workDirs` 变量已在 Task 前置代码中定义——即当前 `final workDirs = <String>[...]` normalize 块，保持不变。）

5. 文件 import 更新：删除对 `member_role_provision.dart` 的引用（不再直接用 `MemberRoleProvision`）；加 `prompt_provision_capability.dart` 与 `prompt_provision.dart`。

- [ ] **Step 4: 注册到 tool definition**

`client/lib/services/cli/opencode/opencode_tool.dart`:

1. import `capabilities/prompt_provision.dart` 与 `../registry/capabilities/prompt_provision_capability.dart`
2. 构造参数：`this.promptProvision = const OpencodePromptProvisionCapability(),`
3. 字段：`final PromptProvisionCapability promptProvision;`（放在 `skillSyntax` 字段旁）
4. `capabilities` getter 列表加 `promptProvision,`（放在 `skillSyntax,` 旁）

- [ ] **Step 5: 更新/跑测试**

- `opencode_external_directories_test.dart`：删掉引用 `composeOpencodeWorkspaceDirectoriesPrompt` 的两个旧测试（Task 1 已覆盖组合层）；`contributeLaunch` 全链路测试断言不变（AGENTS.md 章节 + permission 写入仍成立）。
- Run: `flutter test test/services/cli/config_profile/opencode_external_directories_test.dart test/services/cli/config_profile/opencode_idle_plugin_test.dart`
  Expected: 全 PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/opencode/
git commit -m "feat: migrate opencode member prompt to PromptProvisionCapability"
```

---

### Task 3: claude 迁移（含 per-member 循环）

**Files:**
- Create: `client/lib/services/cli/claude/capabilities/prompt_provision.dart`
- Modify: `client/lib/services/cli/claude/capabilities/config_profile.dart`
- Modify: `client/lib/services/cli/claude/claude_tool.dart`
- Test: `client/test/services/cli/config_profile/claude_prompt_provision_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 接口；`MemberRoleProvision.syncRolePromptFile`（新增 `additionalDirectories` 参数）
- Produces: `ClaudePromptProvisionCapability`（const）；`_writeMemberProfiles` 返回类型改为 `Future<Map<String, String>>`（launched member 的 append env，空 map 表示无）

- [ ] **Step 1: 写失败测试**

`client/test/services/cli/config_profile/claude_prompt_provision_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/prompt_provision.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_provision_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/session/member_role_provision.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('ClaudePromptProvisionCapability writes role.md and returns env', () async {
    final base = await Directory.systemTemp.createTemp('claude_prompt_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'm1',
    );

    final contribution = await const ClaudePromptProvisionCapability().provision(
      PromptProvisionContext(paths: service, scope: scope, member: member),
    );

    expect(contribution.written, isTrue);
    expect(
      contribution.environment.keys,
      contains(MemberRoleProvision.appendSystemPromptFileEnvKey),
    );
    final path = contribution.environment[
        MemberRoleProvision.appendSystemPromptFileEnvKey]!;
    expect(await fs.stat(path), isNotNull);
    expect(await fs.readString(path), contains('You are the reviewer.'));
  });

  test('ClaudePromptProvisionCapability skips without scope', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final contribution = await const ClaudePromptProvisionCapability().provision(
      const PromptProvisionContext(member: member),
    );
    expect(contribution.written, isFalse);
    expect(contribution.environment, isEmpty);
  });
}
```

运行确认失败（编译错误即失败）。

- [ ] **Step 2: 实现 capability**

`client/lib/services/cli/claude/capabilities/prompt_provision.dart`:

```dart
import '../../../../models/team_config.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../../../../services/session/member_role_provision.dart';
import '../team_roster_service.dart';

/// claude 把成员 prompt 写入 `{toolDir}/prompts/{slug}/role.md`，通过
/// `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE` env 传给 LaunchCommandBuilder
/// 转为 `--append-system-prompt-file`。
final class ClaudePromptProvisionCapability
    implements PromptProvisionCapability {
  const ClaudePromptProvisionCapability();

  static const toolId = 'claude';

  @override
  Future<PromptProvisionContribution> provision(
    PromptProvisionContext ctx,
  ) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    final member = ctx.member;
    if (paths == null ||
        scope == null ||
        member == null ||
        !member.isValid) {
      return const PromptProvisionContribution();
    }
    final isLead = TeamMemberNaming.isTeamLead(member);
    final memberToolDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: ctx.mixed
          ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
          : null,
    );
    final rolePath = await MemberRoleProvision.syncRolePromptFile(
      fs: paths.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: isLead && ctx.forceTeamLeadDelegateMode,
      mixed: ctx.mixed,
      additionalDirectories: ctx.additionalDirectories,
    );
    if (rolePath == null) return const PromptProvisionContribution();
    return PromptProvisionContribution(
      written: true,
      environment: {
        MemberRoleProvision.appendSystemPromptFileEnvKey: rolePath,
      },
    );
  }
}
```

- [ ] **Step 3: 迁移 config_profile**

`client/lib/services/cli/claude/capabilities/config_profile.dart`:

1. 类加字段与构造参数：`this.promptProvision = const ClaudePromptProvisionCapability(),` + `final PromptProvisionCapability promptProvision;`
2. `_writeMemberProfile` 内删除 `MemberRoleProvision.syncRolePromptFile(...)` 调用（原 line ~735），改为：

```dart
    final promptContribution = await promptProvision.provision(
      PromptProvisionContext(
        paths: delegate,
        scope: scope,
        member: member,
        forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
        mixed: mixed,
        additionalDirectories: const [],
      ),
    );
    if (promptContribution.written && member.id == launchedMember?.id) {
      appendPromptEnv.addAll(promptContribution.environment);
    }
```

（`_writeMemberProfile` 需要新参数 `required TeamMemberConfig? launchedMember` 与 `required Map<String, String> appendPromptEnv`——后者传引用累计；或把 `_writeMemberProfile` 返回 `Map<String,String>` 由循环合并。选引用累计，改动最小：`_writeMemberProfiles` 内 `final appendPromptEnv = <String, String>{};` 传入循环，末尾 `return appendPromptEnv;`）

3. `_writeMemberProfiles` 签名：`Future<void>` → `Future<Map<String, String>>`；循环内传入 `launchedMember: selected`；返回累计 env。
4. `contributeLaunch` 中 `_writeMemberProfiles(...)` 调用处接收返回值；删除原 `resolveAppendSystemPromptPath` 块（`if (member != null && member.isValid) { final appendPath = await delegate.resolveAppendSystemPromptPath(...); ... }`，原 line ~357-370），改为：

```dart
    environment.addAll(appendPromptEnv);
```

5. import：删 `member_role_provision.dart`（若不再使用）、加 `prompt_provision_capability.dart`、`prompt_provision.dart`；`ConfigProfileDelegate.resolveAppendSystemPromptPath` 不再调用（Task 7 删接口）。

- [ ] **Step 4: 注册 tool definition**

`client/lib/services/cli/claude/claude_tool.dart`：仿 Task 2 Step 4（构造参数 + 字段 + `capabilities` 列表）。

- [ ] **Step 5: 跑测试**

Run: `flutter test test/services/cli/config_profile/claude_prompt_provision_test.dart test/services/cli/config_profile/`
Expected: 全 PASS（既有 claude config_profile 测试断言 role.md / env 行为不变）。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/claude/
git commit -m "feat: migrate claude member prompt to PromptProvisionCapability"
```

---

### Task 4: flashskyai 迁移

**Files:**
- Create: `client/lib/services/cli/flashskyai/capabilities/prompt_provision.dart`
- Modify: `client/lib/services/cli/flashskyai/capabilities/config_profile.dart`
- Modify: `client/lib/services/cli/flashskyai/flashskyai_tool.dart`
- Test: `client/test/services/cli/config_profile/flashskyai_prompt_provision_test.dart`（新建）

**Interfaces:**
- Produces: `FlashskyaiPromptProvisionCapability`（const，`toolId = 'flashskyai'`；与 claude 实现一致，仅 `sessionToolDir` 用 `memberId: scope.memberId`，无 slug 约定）

- [ ] **Step 1: 写失败测试**（仿 Task 3 Step 1，成员 `model: 'test'`，scope 用 `cliTeamName: 'session-1'`；断言 `written`、env 键、`{toolDir}/prompts/m1/role.md` 内容）

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/prompt_provision.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_provision_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/session/member_role_provision.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('FlashskyaiPromptProvisionCapability writes role.md and returns env',
      () async {
    final base = await Directory.systemTemp.createTemp('flashskyai_prompt_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'm1',
    );

    final contribution =
        await const FlashskyaiPromptProvisionCapability().provision(
          PromptProvisionContext(paths: service, scope: scope, member: member),
        );

    expect(contribution.written, isTrue);
    final path = contribution.environment[
        MemberRoleProvision.appendSystemPromptFileEnvKey]!;
    expect(await fs.stat(path), isNotNull);
    expect(await fs.readString(path), contains('You are the reviewer.'));
  });
}
```

- [ ] **Step 2: 实现 capability**（同 claude，差异点：`memberId: scope.memberId`；无 `isLead` 前缀——flashskyai 现有代码已做 `isLead && forceTeamLeadDelegateMode`，保留该语义）

```dart
import '../../../../models/team_config.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../../../../services/session/member_role_provision.dart';

final class FlashskyaiPromptProvisionCapability
    implements PromptProvisionCapability {
  const FlashskyaiPromptProvisionCapability();

  static const toolId = 'flashskyai';

  @override
  Future<PromptProvisionContribution> provision(
    PromptProvisionContext ctx,
  ) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    final member = ctx.member;
    if (paths == null ||
        scope == null ||
        member == null ||
        !member.isValid) {
      return const PromptProvisionContribution();
    }
    final isLead = TeamMemberNaming.isTeamLead(member);
    final memberToolDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    final rolePath = await MemberRoleProvision.syncRolePromptFile(
      fs: paths.fs,
      memberToolDir: memberToolDir,
      member: member,
      forceTeamLeadDelegateMode: isLead && ctx.forceTeamLeadDelegateMode,
      mixed: ctx.mixed,
      additionalDirectories: ctx.additionalDirectories,
    );
    if (rolePath == null) return const PromptProvisionContribution();
    return PromptProvisionContribution(
      written: true,
      environment: {
        MemberRoleProvision.appendSystemPromptFileEnvKey: rolePath,
      },
    );
  }
}
```

- [ ] **Step 3: 迁移 config_profile**

`client/lib/services/cli/flashskyai/capabilities/config_profile.dart`:

1. 类加 `this.promptProvision = const FlashskyaiPromptProvisionCapability(),` + `final PromptProvisionCapability promptProvision;`
2. `_writeMemberProfile` 内删除 `syncRolePromptFile` 调用（原 line ~285），替换为 capability 调用；`_writeMemberProfiles` 返回 launched member 的 env（仿 Task 3：`appendPromptEnv` 引用累计 + 返回值）
3. `contributeLaunch` 顶部 env 处理：删除 `resolveAppendSystemPromptPath` 块（原 line ~122-128），改用 `_writeMemberProfiles` 返回值 `environment.addAll(...)`
4. import 更新（加 prompt_provision 相关；`MemberRoleProvision` 若不再引用则删）

- [ ] **Step 4: 注册 tool definition**（`flashskyai_tool.dart`，仿 Task 2 Step 4）

- [ ] **Step 5: 跑测试**

Run: `flutter test test/services/cli/config_profile/flashskyai_prompt_provision_test.dart test/services/cli/config_profile/`
Expected: 全 PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/flashskyai/
git commit -m "feat: migrate flashskyai member prompt to PromptProvisionCapability"
```

---

### Task 5: codex 迁移

**Files:**
- Create: `client/lib/services/cli/codex/capabilities/prompt_provision.dart`
- Modify: `client/lib/services/cli/codex/capabilities/config_profile.dart`
- Modify: `client/lib/services/cli/codex/codex_tool.dart`
- Test: `client/test/services/cli/config_profile/codex_prompt_provision_test.dart`（新建）

**Interfaces:**
- Produces: `CodexPromptProvisionCapability`（const，`toolId = 'codex'`，`agentsFileName = 'AGENTS.md'`）

- [ ] **Step 1: 写失败测试**

`client/test/services/cli/config_profile/codex_prompt_provision_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/prompt_provision.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_provision_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('CodexPromptProvisionCapability writes AGENTS.md under CODEX_HOME',
      () async {
    final base = await Directory.systemTemp.createTemp('codex_prompt_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final scope = resolveLaunchProfileScope(
      workspaceId: 'workspace-1',
      teamId: 'team-a',
      appSessionId: 'session-1',
      cliTeamName: 'session-1',
      memberId: 'm1',
    );

    final contribution = await const CodexPromptProvisionCapability().provision(
      PromptProvisionContext(paths: service, scope: scope, member: member),
    );

    expect(contribution.written, isTrue);
    expect(contribution.environment, isEmpty);
    final codexHome = service.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'codex',
      memberId: scope.memberId,
    );
    final agents = await fs.readString(
      '$codexHome/${CodexPromptProvisionCapability.agentsFileName}',
    );
    expect(agents, isNotNull);
    expect(agents, contains('You are the reviewer.'));
  });

  test('CodexPromptProvisionCapability skips without scope', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );
    final contribution = await const CodexPromptProvisionCapability().provision(
      const PromptProvisionContext(member: member),
    );
    expect(contribution.written, isFalse);
  });
}
```

运行确认失败（编译错误即失败）。

- [ ] **Step 2: 实现 capability**

`client/lib/services/cli/codex/capabilities/prompt_provision.dart`:

```dart
import '../../../../models/team_config.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../../../../services/session/member_role_provision.dart';

/// codex 把成员 prompt 写入 `$CODEX_HOME/AGENTS.md`；codex 自动加载为全局指令。
final class CodexPromptProvisionCapability
    implements PromptProvisionCapability {
  const CodexPromptProvisionCapability();

  static const toolId = 'codex';
  static const agentsFileName = 'AGENTS.md';

  @override
  Future<PromptProvisionContribution> provision(
    PromptProvisionContext ctx,
  ) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    final member = ctx.member;
    if (paths == null ||
        scope == null ||
        member == null ||
        !member.isValid) {
      return const PromptProvisionContribution();
    }
    final prompt = MemberRoleProvision.composeRolePrompt(
      member: member,
      forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
      mixed: ctx.mixed,
      additionalDirectories: const [],
    ).trim();
    if (prompt.isEmpty) return const PromptProvisionContribution();
    final codexHome = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      toolId,
      memberId: scope.memberId,
    );
    await paths.fs.atomicWrite(
      paths.joinWork(codexHome, agentsFileName),
      '$prompt\n',
    );
    return const PromptProvisionContribution(written: true);
  }
}
```

- [ ] **Step 3: 迁移 config_profile**

`client/lib/services/cli/codex/capabilities/config_profile.dart`:

1. 类加 `this.promptProvision = const CodexPromptProvisionCapability(),` + `final PromptProvisionCapability promptProvision;`
2. 删除 `if (member != null && member.isValid) { final prompt = ...; atomicWrite AGENTS.md ... }` 块（原 line ~186-194），替换为：

```dart
    final promptContribution = await promptProvision.provision(
      PromptProvisionContext(
        paths: paths,
        scope: ctx.scope,
        member: member,
        forceTeamLeadDelegateMode: team?.forceTeamLeadDelegateMode ?? false,
        mixed: mixed,
      ),
    );
    if (promptContribution.written) {
      // AGENTS.md written; no transport env for codex.
    }
```

（若 `agentsFileName` 常量在 config_profile 中不再被引用则一并删除；`MemberRoleProvision` import 若不再使用则删）

- [ ] **Step 4: 注册 tool definition**（`codex_tool.dart`，仿 Task 2 Step 4）

- [ ] **Step 5: 跑测试**

Run: `flutter test test/services/cli/config_profile/codex_prompt_provision_test.dart test/services/cli/config_profile/`
Expected: 全 PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/codex/
git commit -m "feat: migrate codex member prompt to PromptProvisionCapability"
```

---

### Task 6: cursor 迁移（home provisioner 注入）

**Files:**
- Create: `client/lib/services/cli/cursor/capabilities/prompt_provision.dart`
- Modify: `client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart`
- Modify: `client/lib/services/cli/cursor/cursor_tool.dart`
- Test: `client/test/services/cli/config_profile/cursor_prompt_provision_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 接口
- Produces: `CursorPromptProvisionCapability`（const，provision 时自 `ctx.paths` 构造 `CursorRoleRuleWriter`）；`CursorHomeProvisioner` 新增构造参数 `PromptProvisionCapability promptProvision = const CursorPromptProvisionCapability()`，删除 `_syncRoleRule`

- [ ] **Step 1: 写失败测试**

`client/test/services/cli/config_profile/cursor_prompt_provision_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/capabilities/prompt_provision.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_provision_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('CursorPromptProvisionCapability writes role.mdc with frontmatter',
      () async {
    final base = await Directory.systemTemp.createTemp('cursor_prompt_');
    addTearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final service = ConfigProfileService(
      basePath: base.path,
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: base.path, fs: fs),
    );
    final memberHome = Directory('${base.path}/fake-home')..createSync();
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
      responsibilities: 'You are the reviewer.',
    );

    final contribution = await const CursorPromptProvisionCapability().provision(
      PromptProvisionContext(
        paths: service,
        member: member,
        memberHome: memberHome.path,
        mixed: true,
        pushDelivery: true,
      ),
    );

    expect(contribution.written, isTrue);
    expect(contribution.environment, isEmpty);
    final rolePath =
        '$memberHome.path/.cursor/rules/role.mdc';
    expect(await fs.stat(rolePath), isNotNull);
    final content = await fs.readString(rolePath);
    expect(content, contains('alwaysApply: true'));
    expect(content, contains('You are the reviewer.'));
  });

  test('CursorPromptProvisionCapability skips without memberHome', () async {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      model: 'test',
    );
    final contribution = await const CursorPromptProvisionCapability().provision(
      const PromptProvisionContext(member: member),
    );
    expect(contribution.written, isFalse);
  });
}
```

- [ ] **Step 2: 实现 capability**

`client/lib/services/cli/cursor/capabilities/prompt_provision.dart`:

```dart
import '../../../../models/team_config.dart';
import '../../registry/capabilities/prompt_provision_capability.dart';
import '../provider/cursor_home_layout.dart';
import '../provider/cursor_role_rule_writer.dart';

/// cursor 把成员 prompt 写入 fake HOME 的 `~/.cursor/rules/role.mdc`。
/// 由 `CursorHomeProvisioner` 调用（装配点无 scope/paths delegate，只传
/// memberHome）；无 flag 传输，.mdc 自动加载。
final class CursorPromptProvisionCapability
    implements PromptProvisionCapability {
  const CursorPromptProvisionCapability();

  @override
  Future<PromptProvisionContribution> provision(
    PromptProvisionContext ctx,
  ) async {
    final paths = ctx.paths;
    final memberHome = ctx.memberHome;
    final member = ctx.member;
    if (paths == null ||
        memberHome == null ||
        memberHome.isEmpty ||
        member == null ||
        !member.isValid) {
      return const PromptProvisionContribution();
    }
    final rolePath = await CursorRoleRuleWriter(
      fs: paths.fs,
      layout: CursorHomeLayout(pathContext: paths.pathContext),
    ).sync(
      memberHome: memberHome,
      member: member,
      forceTeamLeadDelegateMode: ctx.forceTeamLeadDelegateMode,
      mixed: ctx.mixed,
      pushDelivery: ctx.pushDelivery,
      additionalDirectories: const [],
    );
    if (rolePath == null) return const PromptProvisionContribution();
    return const PromptProvisionContribution(written: true);
  }
}
```

注意：`CursorRoleRuleWriter.sync` 的 `additionalDirectories` 参数已在 Task 1 加入；本实现传 `const []`（cursor 的目录访问走 trust，prompt 不含章节）。

- [ ] **Step 3: 迁移 CursorHomeProvisioner**

`client/lib/services/cli/cursor/provider/cursor_home_provisioner.dart`:

1. import `capabilities/prompt_provision.dart`、`../../registry/capabilities/prompt_provision_capability.dart`
2. 构造器加参数与字段：

```dart
  CursorHomeProvisioner({
    required Filesystem fs,
    CursorHomeLayout? layout,
    CursorProviderCredentialsService? credentials,
    PromptProvisionCapability promptProvision =
        const CursorPromptProvisionCapability(),
  }) : _fs = fs,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext),
       _credentials = credentials,
       _promptProvision = promptProvision;

  final PromptProvisionCapability _promptProvision;
```

3. 删除 `_syncRoleRule` 方法；`provision()` 中替换调用（原 `await _syncRoleRule(memberHome: ..., mixed: false, pushDelivery: false)`）：

```dart
      await _promptProvision.provision(
        PromptProvisionContext(
          member: member,
          memberHome: memberHome,
          forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
          mixed: false,
          pushDelivery: false,
        ),
      );
```

4. `provisionOverlayOnly()` 中替换（原 `mixed: true, pushDelivery: true`）：

```dart
    await _promptProvision.provision(
      PromptProvisionContext(
        member: member,
        memberHome: memberHome,
        forceTeamLeadDelegateMode: forceTeamLeadDelegateMode,
        mixed: true,
        pushDelivery: true,
      ),
    );
```

- [ ] **Step 4: 注册 tool definition**（`cursor_tool.dart`，仿 Task 2 Step 4；`promptProvision` 默认 `const CursorPromptProvisionCapability()`）

- [ ] **Step 5: 跑测试**

Run: `flutter test test/services/cli/config_profile/cursor_prompt_provision_test.dart test/services/cli/cursor/`
Expected: 全 PASS（cursor 既有测试用可选参数，编译不变）。

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/cursor/
git commit -m "feat: migrate cursor member prompt to PromptProvisionCapability"
```

---

### Task 7: 删除 resolveAppendSystemPromptPath

**Files:**
- Modify: `client/lib/services/cli/registry/config_profile/config_profile_context.dart`（接口）
- Modify: `client/lib/services/provider/config_profile_service.dart`（转发）
- Modify: `client/lib/services/provider/config_profile_infrastructure.dart`（实现，含 `MemberRoleProvision.rolePromptPath` 的读回逻辑）
- Modify: `client/test/support/cursor_lifecycle_test_paths.dart:109`
- Modify: `client/test/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_persist_test.dart:271`
- Modify: `client/test/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_initialize_test.dart:334`

- [ ] **Step 1: 删接口方法**

`config_profile_context.dart` 的 `ConfigProfileDelegate` 中删除：

```dart
  Future<String?> resolveAppendSystemPromptPath({
    required LaunchProfileScope scope,
    required String tool,
    required TeamMemberConfig member,
  });
```

- [ ] **Step 2: 删 service 转发**

`config_profile_service.dart` 中删除对应 override（约 line 1093-1099）。

- [ ] **Step 3: 删 infrastructure 实现**

`config_profile_infrastructure.dart` 中删除 `resolveAppendSystemPromptPath` override（约 line 305-330，含 `rolePromptPath` 读回逻辑；`MemberRoleProvision` import 若不再使用则删）。

- [ ] **Step 4: 更新 3 个测试 fake**

三个 fake（`cursor_lifecycle_test_paths.dart`、persist_test、initialize_test）删除各自的 `resolveAppendSystemPromptPath` override。

- [ ] **Step 5: 验证无残留引用 + 跑测试**

Run: `rg -n "resolveAppendSystemPromptPath" client/lib client/test` → 无输出。
Run: `flutter test test/services/cli/session_lifecycle/cursor/ test/services/cli/config_profile/`
Expected: 全 PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib client/test
git commit -m "refactor: remove resolveAppendSystemPromptPath after PromptProvisionCapability migration"
```

---

### Task 8: registry wiring 测试 + 全量验证

**Files:**
- Create: `client/test/services/cli/registry/all_cli_prompt_provision_capability_test.dart`

- [ ] **Step 1: 写 wiring 测试**

`client/test/services/cli/registry/all_cli_prompt_provision_capability_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_provision_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('registry wiring all launch CLIs expose PromptProvisionCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values.where((c) => c.isLaunchSupported)) {
      expect(
        registry.capability<PromptProvisionCapability>(cli),
        isNotNull,
        reason: '$cli must expose PromptProvisionCapability',
      );
    }
  });
}
```

注意：`CliTool` 枚举与 `isLaunchSupported` 的使用方式对齐 `test/services/cli/registry/all_cli_effort_capability_test.dart` 现有写法（若枚举有 `isLaunchSupported` getter 则直接使用，否则写死五个：claude / flashskyai / codex / opencode / cursor）。

Run: `flutter test test/services/cli/registry/all_cli_prompt_provision_capability_test.dart`
Expected: PASS。

- [ ] **Step 2: 全量验证**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings` → 无新增问题（本计划涉及文件零告警）。
Run: `flutter test --exclude-tags integration` → 全 PASS。

- [ ] **Step 3: Commit**

```bash
git add client/test/services/cli/registry/all_cli_prompt_provision_capability_test.dart
git commit -m "test: assert all launch CLIs expose PromptProvisionCapability"
```

---

## Self-Review 记录

- **Spec 覆盖**：接口（Task 1）、组合层 dirs 章节（Task 1）、五个实现（Task 2-6）、装配点收敛（Task 2-6）、`resolveAppendSystemPromptPath` 删除（Task 7）、tool definition 注册 + wiring 测试（Task 2-6 注册、Task 8 测试）、`permission.external_directory` 保留在 opencode config_profile（Task 2 不动该逻辑）。✓
- **占位符扫描**：无 TBD/TODO；每个测试都有完整代码（Task 5 已补全实际测试代码，无"仿 Task N"引用）。
- **类型一致性**：`PromptProvisionContext` / `PromptProvisionContribution` 字段在 Task 1 定义后所有任务一致引用；`composeWorkspaceDirectoriesPrompt`（Task 1 命名）与旧名 `composeOpencodeWorkspaceDirectoriesPrompt` 的对应关系已注明（Task 2 删除旧函数）；`additionalDirectories` 参数在 `composeRolePrompt` / `syncRolePromptFile` / `CursorRoleRuleWriter.sync` 三处命名与语义一致（Task 1 统一加入）。
