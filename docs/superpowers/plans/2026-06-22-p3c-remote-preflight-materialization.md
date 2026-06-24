# P3c — 远程 preflight + CLI 定位泛化 + 物化到工作机 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让成员落在**异于 home 的远程机**也能端到端启动：远程 preflight checklist（连接→CLI 就位→app-data 物化→bus 可达）；CLI 定位泛化全 5 CLI + opt-in SSH 安装 + 手填兜底；ancestry/skills/plugins 物化到工作机 `<machineRoot>` 使继承 symlink 在该机根内闭合；凭证 per-target opt-in 物化到远程 `providers/`（默认关）；内容哈希/manifest 跳过未变子树。

**Architecture:** 全程 fs/runner 注入（`FakeSftpFilesystem` + `FakeSshCommandRunner`/`HostScriptRunner`），无真机可测。`WorkMachineMaterializer` 先把 ancestry 拷到工作机根，再用工作机 fs+root 跑现成 `_ensureInheritedChild` 继承逻辑（链在该机根内闭合）。`RemotePreflightService` 串成顺序 checklist，顶接 P3b 隧道。POSIX 优先、零兼容。

**Tech Stack:** Dart / Flutter，vendored `dartssh2`（SFTP/exec），`crypto`(内容哈希)，`package:flutter_test`/`package:test`。

**Branch:** 基于 `feat/p3-member-remote`（63aec9b）——切 `feat/p3c-remote-preflight`。

## Global Constraints

- **零兼容、最优终态**；POSIX 优先（**不**做 Windows/macos 物化分支、不做 `remoteOs` 探测——P3e）。
- **不含**：P3d 跨机产物、P4 弹性、远程 SFTP 目录浏览器 UX（成员目录来自工作区 target folders）。
- 凭证推远程**默认关**；仅 per-target 显式 opt-in + 首推确认弹窗后才铺 key。
- 设计权威：[docs/superpowers/specs/2026-06-22-p3c-remote-preflight-materialization-design.md](../specs/2026-06-22-p3c-remote-preflight-materialization-design.md)。
- 完成判据（每任务+总验收）：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 干净；`flutter test --exclude-tags integration` 全绿。
- 频繁提交：每任务 ≥1 commit。

## 文件结构

| 文件 | 职责 | 动作 |
|------|------|------|
| `lib/services/cli/registry/capabilities/remote_cli_locator_capability.dart` | per-CLI 远程探测命令能力位 | 新增 |
| `lib/services/cli/remote_cli_locator.dart` | 泛化 locator（取代 RemoteFlashskyaiCliLocator） | 新增/删旧 |
| `lib/services/remote/materialization_manifest.dart` | 内容哈希 manifest | 新增 |
| `lib/services/remote/work_machine_materializer.dart` | ancestry+skills/plugins 物化 + 调继承 | 新增 |
| `lib/services/remote/remote_credential_materializer.dart` | 凭证物化 + 链接 root 重算 + opt-in | 新增 |
| `lib/services/remote/remote_preflight_service.dart` | preflight 编排 | 新增 |
| `lib/services/storage/targets_repository.dart` | `credentialOptIn` + per-target 手填路径 | 改 |
| `lib/services/cli/registry/installer/installer_context.dart`(+ runner) | 安装走 target transport runner | 改 |
| `lib/cubits/chat/session_launch_service.dart`, `session_lifecycle_service.dart` | 远程成员 launch 前跑 preflight | 改 |
| 凭证 opt-in UI | per-target 开关 + 首推确认弹窗 | 改 |

---

### Task 1: 远程 CLI 定位能力位 + 泛化 locator（5 CLI）

**Files:** Create `remote_cli_locator_capability.dart`, `remote_cli_locator.dart`; 5 个 `*_cli_tool.dart` 注册能力; Delete `remote_flashskyai_cli_locator.dart`; Test `remote_cli_locator_test.dart`

**Interfaces:** Produces `abstract interface class RemoteCliLocatorCapability implements CliCapability { Future<String?> locate(SshCommandRunner run); }`; `class RemoteCliLocator { Future<String?> resolve({required CliTool cli, required SshCommandRunner run, String manualPathOverride=''}); }`. 复用现有 `SshCommandRunner`/`SshCommandResult` typedef（从 remote_flashskyai_cli_locator 迁出到共享位置）。

- [ ] **Step 1: 失败测试**

```dart
// FakeSshCommandRunner: Map<String,SshCommandResult> 按命令返回
test('locates each of 5 CLIs via its probe command', () async {
  for (final cli in CliTool.values) {
    final run = FakeSshCommandRunner({'<cli probe cmd>': SshCommandResult(exitCode:0, stdout:'/usr/bin/${cli.value}')});
    expect(await RemoteCliLocator().resolve(cli: cli, run: run.call), isNotNull);
  }
});
test('manual override wins without probing', () async { ... expect(...,'/custom'); });
test('returns null when all probes fail', () async { ... });
```

- [ ] **Step 2: 运行→失败**  `cd client && flutter test test/services/cli/remote_cli_locator_test.dart`

- [ ] **Step 3: 实现** — 能力位接口；各 CLI 在 def 注册探测命令（`command -v <bin> || which <bin>`，cursor=`cursor-agent` 等）；`RemoteCliLocator.resolve`：manualPathOverride 优先 → `registry.capability<RemoteCliLocatorCapability>(cli).locate(run)`。把 `SshCommandRunner`/`SshCommandResult` typedef 迁到 `remote_cli_locator.dart`（共享）；删 `RemoteFlashskyaiCliLocator`，其 claude/flashskyai 探测逻辑并入对应能力实现。更新引用点（app_shell 的 `RemoteFlashskyaiCliLocator` 装配 → 新 locator）。

- [ ] **Step 4: 运行→通过** + analyze。`flutter test test/services/cli/ && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/cli`

- [ ] **Step 5: Commit** `git commit -m "feat: generalize remote CLI locator capability across 5 CLIs"`

---

### Task 2: per-target 手填路径 + `credentialOptIn`（targets.json）

**Files:** Modify `targets_repository.dart`; Test `targets_repository_p3c_test.dart`

**Interfaces:** `TargetsRegistryFile` + `List<String> credentialOptIn` + `Map<String,String> cliPathOverrides`（targetId→{cli→path} 简化为 `Map<String,Map<String,String>>` 或扁平 `{"<targetId>|<cli>": path}`）。Produces repo helpers `setCredentialOptIn(targetId,bool)`, `isCredentialOptIn(targetId)`, `setCliPathOverride(targetId,cli,path)`, `cliPathOverride(targetId,cli)`.

- [ ] **Step 1: 失败测试** — opt-in 默认 false；set→true 往返；cli path override 往返。
- [ ] **Step 2: 运行→失败**
- [ ] **Step 3: 实现** — `TargetsRegistryFile` 加 `credentialOptIn`(默认空)、`cliPathOverrides`(默认空) + json + copyWith；repo helper。
- [ ] **Step 4: 运行→通过**  `flutter test test/services/storage/targets_repository_p3c_test.dart`
- [ ] **Step 5: Commit** `git commit -m "feat: per-target credentialOptIn + CLI path override in targets.json"`

---

### Task 3: 远程 CLI 安装（opt-in，走 target transport）

**Files:** Modify `installer_context.dart`(+ runner 注入); `remote_preflight_service.dart`(部分，安装步骤先放此或独立 service); Test `remote_cli_install_test.dart`

**Interfaces:** 安装经**绑定 target transport 的 `HostScriptRunner`**；`RemoteCliInstaller.ensure({cli, run/scriptRunner, optIn, onProgress})` → 已装返回路径；缺+opt-in+supportsInstaller → 装+进度+re-locate；否则报错（提示手填）。

- [ ] **Step 1: 失败测试**

```dart
test('opt-in off + missing CLI -> error suggesting manual path', () async { ... });
test('opt-in on + supportsInstaller -> runs install script, progress called, re-locates', () async {
  final scriptRunner = FakeHostScriptRunner();
  // 断言 install 脚本被执行、onProgress 被调、装后 locate 命中
});
test('no installer capability -> clear error', () async { ... });
```

- [ ] **Step 2: 运行→失败**
- [ ] **Step 3: 实现** — `CliInstallContext` 支持注入 target-bound `HostScriptRunner`；`RemoteCliInstaller` 编排 locate→(opt-in)install→re-locate；进度回调。
- [ ] **Step 4: 运行→通过**
- [ ] **Step 5: Commit** `git commit -m "feat: opt-in remote CLI install over target transport with progress"`

---

### Task 4: `MaterializationManifest`（内容哈希跳过）

**Files:** Create `materialization_manifest.dart`; Test `materialization_manifest_test.dart`

**Interfaces:** `class MaterializationManifest { MaterializationManifest({required Filesystem fs, required String machineRoot}); Future<Map<String,String>> load(); Future<void> save(Map<String,String> hashes); String hashOf(List<int> bytes); }`（`<machineRoot>/.materialized.json`）。

- [ ] **Step 1: 失败测试** — 空默认；save→load 往返；`hashOf` 稳定。
- [ ] **Step 2: 运行→失败**
- [ ] **Step 3: 实现** — JSON 文件读写（注入 fs）；`hashOf` 用 `crypto` sha256 hex。
- [ ] **Step 4: 运行→通过**
- [ ] **Step 5: Commit** `git commit -m "feat: MaterializationManifest (content-hash skip)"`

---

### Task 5: `WorkMachineMaterializer`（ancestry 物化 + 继承闭合 + 哈希跳过）

**Files:** Create `work_machine_materializer.dart`; Test `work_machine_materializer_test.dart`

**Interfaces:** `class WorkMachineMaterializer { WorkMachineMaterializer({required Filesystem homeFs, required String homeRoot, required Filesystem workFs, required String machineRoot, required MaterializationManifest manifest}); Future<void> reconcile({required Set<String> tools, required String workspaceId}); }` — 把 home 的 `cli-defaults/{tool}`+workspace config 拷到工作机根（哈希跳过），然后用工作机 fs+root 跑现成继承（`RuntimeLayout(work).provision...`）。

- [ ] **Step 1: 失败测试（§5.2 核心）**

```dart
test('materializes ancestry to machineRoot and closes inheritance within that root', () async {
  final homeFs = FakeSftpFilesystem()..seed('/home/cli-defaults/claude/agents/x', '...');
  final workFs = FakeSftpFilesystem();
  final m = WorkMachineMaterializer(homeFs: homeFs, homeRoot: '/home', workFs: workFs, machineRoot: '/remote', manifest: ...);
  await m.reconcile(tools: {'claude'}, workspaceId: 'w1');
  // ① cli-defaults/claude 出现在 /remote
  expect((await workFs.stat('/remote/cli-defaults/claude/agents/x')).exists, isTrue);
  // ② session runtime 继承 symlink 指向 /remote 内（不指向 /home）
  final link = await workFs.readSymlinkTarget('/remote/workspace/.../runtime/members/m1/claude/agents');
  expect(link, startsWith('/remote'));
});
test('second reconcile with unchanged content skips re-copy (manifest hit)', () async {
  // 计数 workFs 写调用 == 0 第二次
});
test('changing one file re-copies only that subtree', () async { ... });
```

- [ ] **Step 2: 运行→失败**
- [ ] **Step 3: 实现** — 遍历 home 的 `cli-defaults/{tool}`+workspace config，按文件哈希对比 manifest，未变跳过、变则 home 读→工作机写；写后更新 manifest；然后构造 `RuntimeLayout(teampilotRoot: machineRoot, fs: workFs)` 跑既有 provision/继承（`_ensureInheritedChild` 在 `/remote` 内闭合）。skills/plugins linker 注入 workFs 在该机内链接。
- [ ] **Step 4: 运行→通过**
- [ ] **Step 5: Commit** `git commit -m "feat: WorkMachineMaterializer (ancestry to machineRoot, inheritance closes in-root, hash skip)"`

---

### Task 6: `RemoteCredentialMaterializer`（opt-in 物化 + 链接 root 重算）

**Files:** Create `remote_credential_materializer.dart`; Test `remote_credential_materializer_test.dart`

**Interfaces:** `class RemoteCredentialMaterializer { Future<void> materialize({required CliTool cli, required Filesystem workFs, required String machineRoot, required bool optIn, required CredentialSource localCreds}); }` — opt-in off → 不写；on → 写 `<machineRoot>/providers/{tool}/` + 链接 target 绝对路径按 `machineRoot` 重算。

- [ ] **Step 1: 失败测试**

```dart
test('opt-in off writes no credentials on work machine', () async { ... workFs providers empty });
test('opt-in on materializes creds and rewrites link target to machineRoot', () async {
  // workFs '/remote/providers/claude/...' 存在；其中链接路径前缀 == '/remote'（非本地 root）
});
test('rotation (changed cred bytes) re-pushes', () async { ... });
```

- [ ] **Step 2: 运行→失败**
- [ ] **Step 3: 实现** — opt-in 门控；本地凭证内容经 workFs 写到远程 `providers/{tool}/`；任何嵌入的绝对路径（链接 target）从本地 root 替换为 `machineRoot`；轮换经哈希对比触发重写。
- [ ] **Step 4: 运行→通过**
- [ ] **Step 5: Commit** `git commit -m "feat: RemoteCredentialMaterializer (per-target opt-in, link root rewrite)"`

---

### Task 7: `RemotePreflightService`（顺序编排）

**Files:** Create `remote_preflight_service.dart`; Test `remote_preflight_service_test.dart`

**Interfaces:** `class RemotePreflightService { Future<PreflightResult> prepare({required RuntimeTarget target, required CliTool cli, required String workspaceId, required String memberId, required bool optInCredentials, ProgressSink? onProgress}); }` 串：connect(forTarget)→locate/install→materialize(ancestry+skills/plugins+relay+(opt-in)creds)→bus-bind(P3b RemoteBusMount)。

- [ ] **Step 1: 失败测试**

```dart
test('runs steps in order: connect -> locate/install -> materialize -> bus-bind', () async {
  // fake 各步记录调用顺序，断言序列
});
test('connect failure short-circuits with clear "target unavailable" error', () async { ... });
test('locate+install failure surfaces manual-path error, no materialize attempted', () async { ... });
```

- [ ] **Step 2: 运行→失败**
- [ ] **Step 3: 实现** — 注入 Task 1/3/5/6 服务 + P3b `RemoteBusMount`；按序执行、任一步失败短路 + 清晰错误；进度上抛。
- [ ] **Step 4: 运行→通过**
- [ ] **Step 5: Commit** `git commit -m "feat: RemotePreflightService orchestration"`

---

### Task 8: 接入会话启动（远程成员 launch 前跑 preflight）

**Files:** Modify `session_launch_service.dart`, `session_lifecycle_service.dart`; Test `remote_member_launch_preflight_test.dart`

**Interfaces:** Consumes Task 7. 成员 target **为异于 home 的远程机** → launch 前 `RemotePreflightService.prepare`；home/home-ssh（P3b）走原路径。

- [ ] **Step 1: 失败测试** — 成员 target 远程 → preflight 被调且其产出（远程 CLI 路径 + workCtx + bus binding）喂给 launch；成员 home → 不调 preflight（零变更）。
- [ ] **Step 2: 运行→失败**
- [ ] **Step 3: 实现** — 在 `_scheduleMemberConnect`/launch 计划处判定成员 target 是否远程（≠home）；是则 `prepare` 并用其结果（路径/ctx/binding）；否则现状。opt-in 标志取 `targets.json.credentialOptIn`。
- [ ] **Step 4: 运行→通过** + 全量 analyze/test。
- [ ] **Step 5: Commit** `git commit -m "feat: run remote preflight before launching off-home members"`

---

### Task 9: 凭证 opt-in UI（per-target 开关 + 首推确认弹窗）

**Files:** Modify target/profile 设置 UI; l10n; Test widget。

**Interfaces:** Consumes `targets_repository` opt-in helpers (Task 2)。

- [ ] **Step 1:** target 设置加"推送凭证到此机"开关（默认关）；开启触发**确认弹窗**（明示 key 落远程主机 <host> 的信任边界）；确认后 `setCredentialOptIn(targetId,true)`。l10n 文案 en/zh。
- [ ] **Step 2: widget 测试** — 默认关；开启弹确认；确认后写 opt-in；取消不写。
- [ ] **Step 3:** `flutter pub get`（l10n）+ `dart run tool/gen_warmup_glyphs.dart`。
- [ ] **Step 4:** `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` → CLEAN+PASS。
- [ ] **Step 5: Commit** `git commit -m "feat: per-target credential push opt-in toggle with trust-boundary confirm"`

---

### Task 10: 全量验收 + 边界守卫

- [ ] **Step 1: 全量** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` → CLEAN+PASS。
- [ ] **Step 2: 边界 grep** — `remoteOs` 仍占位（无探测）；无 Windows/macos 物化分支；无跨机产物 MCP；无远程 SFTP 目录浏览器；凭证默认关（无 opt-in 即不铺）。
- [ ] **Step 3: 手验金路径文档** — 成员落异于 home 的远程机：locate 命中/缺则 opt-in 装；物化后远程成员用 app 默认配置启动；opt-in 凭证后该 provider 可认证；远程机离线 → 仅该成员失败、控制面/项目列表可读（P2 保证）。
- [ ] **Step 4: Commit** `git commit -m "chore: P3c acceptance sweep + boundary guard"`

---

## Self-Review

**Spec coverage:**
- §3.1 locate 泛化 5 CLI → Task 1 ✅；§3.2 opt-in 安装 → Task 3 ✅
- §3.3 ancestry+skills/plugins 物化+继承闭合+哈希跳过 → Task 4(manifest)+Task 5 ✅
- §3.4 凭证 opt-in 物化+链接 root 重算 → Task 2(opt-in 存储)+Task 6+Task 9(UI) ✅
- §3.5 preflight 编排 → Task 7 + Task 8(接入) ✅
- §5 测试策略（fake 全链）→ 各任务 fake 测 + Task 10 ✅；§6 边界 → Global Constraints + Task 10 ✅

**Placeholder scan:** Task 1/5 的探测命令/继承细节给了具体断言与结构；CLI 探测命令逐 CLI 在 def 注册（Task 1 列举 command -v/which/cursor-agent）。物化哈希跳过、链接 root 重算均有具体断言。fake 栈复用 P3 已有 `FakeSftpFilesystem`/`FakeSshCommandRunner`（指明复用，非新造）。

**Type consistency:** `RemoteCliLocatorCapability.locate(SshCommandRunner)`、`RemoteCliLocator.resolve`、`MaterializationManifest{load,save,hashOf}`、`WorkMachineMaterializer.reconcile`、`RemoteCredentialMaterializer.materialize`、`RemotePreflightService.prepare`、`targets_repository` opt-in/override helpers 跨任务一致。复用 P3b `RemoteBusMount`、P2 `RuntimeContextRegistry.forTarget`/`readSymlinkTarget`。

**可测试性（团队重点）落实:** (a) 无真机 → 全注入 FakeSftpFilesystem+FakeSshCommandRunner/HostScriptRunner（Task 1/3/5/6/7）；(b) 继承在工作机 root 闭合 → Task 5 断言 readSymlinkTarget 指向 machineRoot + 哈希跳过计数；(c) 凭证 opt-in UI 明示 + 链接 root 重算 → Task 6/9。每任务结尾独立可运行验证命令。
