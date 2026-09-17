# WorkspaceBaseInfoCapability 设计

- 日期：2026-09-17
- 状态：已批准
- 来源：工作区有远程项目时，agent 不知道它们存在，也不知道该走 Session SSH MCP；同机附属目录的 `--add-dir` / OpenCode 权限和这段说明应同属一个必选能力

## 目标

每个 CLI 必须注册 `WorkspaceBaseInfoCapability`。一份座位快照同时：

1. 编码同机工作区访问（原 `WorkspaceAccessArgProvider`：Claude/Cursor/Codex/FlashskyAI 的 `--add-dir` 等；OpenCode 无 argv，config 仍写 `permission.external_directory`）
2. 在条件 B 成立时注入一段英文 prompt：同机附属目录已授权；远程项目不在本机，用 `ssh` MCP（`list-servers` / `execute-command` / `upload` / `download`）

后续工作区自定义 prompt 走同一能力的 `customPromptSections` 槽。本期槽恒为空，不加工区字段或设置 UI。

## 非目标

- 不改 Session SSH MCP 工具契约、注入谓词、网关或 allow 列表。
- 不新增 catalog skill / catalog tool 来查询工作区。
- 不给 OpenCode 发明 `--add-dir`。
- 本期不读、不写 `Workspace.customPrompt`（或任何同类字段）。
- 不做工作区设置 UI。
- 不把这段写成第五套 `PromptCapability` writer；现有 CLI writer 只物化装配好的 document。
- WSL folder 不是 SSH MCP 目标；同机 extras 经现有路径规范化（含 WSL）进入 snapshot，远程只列 `ssh:*`。

## 架构

`WorkspaceBaseInfoCapability` 是必选 `CliCapability`，同时实现 `CliLaunchArgProvider` 与 `PromptContributionProvider`。共享基类实现 `provide()`；各 CLI 只实现 argv 编码。

```text
memberWork + workspace.folders + shouldInjectSessionSshMcp
        │
        ▼
WorkspaceSeatSnapshot
  cwd
  sameHostExtraDirs
  remoteFolders          ← profileId / name / user@host:port / folderPaths
  sshMcpInjected         ← 本座位 extra MCP 里是否有 ssh
  customPromptSections   ← 本期恒 []
        │
        ├─ buildLaunchArgs（原 WorkspaceAccessArgProvider）
        │    Claude: --add-dir…（无主目录旗标；cwd 仍是进程 cwd）
        │    Cursor: --workspace + --add-dir…
        │    Codex: --cd + --add-dir…
        │    FlashskyAI: --dir + --add-dir…
        │    OpenCode: 无 argv；sameHostExtraDirs 仍由 provider
        │              mergeOpencodeExternalDirectories 写入 config
        │
        └─ provide() prompt（条件 B）
             sameHostExtraDirs 非空 或 sshMcpInjected
```

`built_in_cli_tools` 增加 `_verifyRequired<WorkspaceBaseInfoCapability>`。五个 CLI 都要注册，含 OpenCode。

Headless 从 registry 取该能力再 `buildLaunchArgs`，禁止 `const XxxWorkspaceAccessLaunch()`。

`providerId` 固定 `workspace-base-info`。argv 贡献 `key` 保持现有（`claude-workspace-access` 等），避免 assembler 测试无谓改名。

## 注入条件

Prompt 与 argv 分开。

**Prompt（条件 B）**

输出非空当且仅当：

- `sameHostExtraDirs` 非空，或
- 本座位**实际**注入了 `ssh` MCP（与 `shouldInjectSessionSshMcp` / compose 后 `extra["ssh"]` 一致）

不是「工作区有 ssh 文件夹」。有 `ssh:*` 但开关关、或远程座位因没有 `remoteBinding` 而没写入 `extra["ssh"]` → `sshMcpInjected=false`，不写 Remote projects，也不提 MCP。

只有 cwd、没有 extras、也没注入 MCP → 不贡献这段 prompt。

**Argv / OpenCode config**

与今天相同：有规范化后的 cwd 和/或 extras 就编码。与 prompt B 无关。Claude 在 extras 为空时仍不发 `--add-dir`。

## 组件

| 单元 | 职责 | 依赖 |
|------|------|------|
| `WorkspaceSeatSnapshot` | 座位只读快照 | cwd / extras / remoteFolders / sshMcpInjected / customPromptSections |
| `WorkspaceRemoteFolderInfo` | 远程展示字段（无密钥） | `SessionSshMcpTarget`（`sessionSshMcpTargetsFromFolders`） |
| `WorkspaceAccess` | cwd + extras 路径规范化，供 argv | `CliLaunchContext`（保留；不再作为 Provider 基类） |
| `composeWorkspaceBaseInfoPrompt` | 纯函数，一段英文正文 | snapshot |
| `WorkspaceBaseInfoCapability` | 必选接口：argv + prompt | `CliCapability` |
| 共享基类 | `provide()`；`buildLaunchArgs` 调 `WorkspaceAccess` 再交给子类编码 | snapshot / compose |
| `Claude/Cursor/Codex/FlashskyaiWorkspaceBaseInfo` | 各 CLI argv 编码（行为与现 `*WorkspaceAccessLaunch` 相同） | 基类 |
| `OpencodeWorkspaceBaseInfo` | argv 恒空 | 基类 |
| 装配点 | 把 `sshMcpInjected` + `remoteFolders` 传入 provision/prompt context | 已有 `additionalDirectories` 调用链 |

删除 `WorkspaceAccessArgProvider`。`MemberRoleProvision.composeWorkspaceDirectoriesPrompt` 删除；`composeRolePrompt` / `syncRolePromptFile` / `OpencodePromptCapability` / `CursorRoleRuleWriter.sync` 不再拼目录章节。Cursor `provide()` 已经传 `additionalDirectories: const []`，物化走装配 document，目录只来自 `workspace-base-info`。

成员角色贡献与 `workspace-base-info` 独立：角色正文为空但条件 B 成立时，装配 document 仍非空，Claude `role.md` / OpenCode `AGENTS.md` / Cursor `role.mdc` 仍会写入这段工作区说明。`syncRolePromptFile` 若仍被测试直接调用，不再因为「只有目录」而写文件。

OpenCode 的 `mergeOpencodeExternalDirectories` 留在 provider：写 config 不是 argv。目录集合必须与 snapshot `sameHostExtraDirs` 同源（今天的 `workDirs` / `additionalDirectories`）。

`PromptCapability` 只 `materialize` 装配结果。`ResourceProviderSet.fromRegistryAndInjected` 会收到该 provider，不必再塞进 catalog 的 `prompts:` 列表。

## 数据流

在已经知道 `memberWork`、工作区 `folders`、以及本座位是否写入 `extra["ssh"]` 的地方（`session_shell_connector` / session lifecycle → `config_profile_service`）构造 snapshot 输入，沿现有 `additionalDirectories` 调用链下传，**不新开 provision 阶段**：

- `CliLaunchContext`：仍只带 cwd / `additionalDirectories`（argv 够用）
- `CliResourceProvisionContext`、`PromptProviderContext`、`PromptHubService`、`PromptVirtualizeContext` / `PromptMaterializeContext`：增加 `sshMcpInjected` 与 `remoteFolders`（或等价 snapshot）。缺省：未注入、远程列表空

`remoteFolders` 用 `sessionSshMcpTargetsFromFolders`；解析不到的 profile 本来就不会进列表。展示用 `profileId`、`name`、`username@host:port`、`folderPaths`。不含密码、私钥、passphrase。

Prompt 装配与 argv 可以不同步发生，输入同源。不缓存旧快照。`list-servers` 仍是运行时权威；prompt 只声明远程存在且走 MCP。

`customPromptSections` 本期不读 Workspace。以后工作区设置写入后，同一 `composeWorkspaceBaseInfoPrompt` 拼在 Remote projects 之后。

## Prompt 正文

英文，给 agent 读。缺哪段省略哪段。`customPromptSections` 非空时原样接在后面（本期无）。

同机 extras：

```text
## Workspace directories
This session can also access the following directories on the same host.
They are already authorized. Use absolute paths.
- /abs/path
```

远程且 `sshMcpInjected`：

```text
## Remote projects
This workspace also includes project directories on other hosts.
They are not on this machine — do not treat them as local paths.
Use the `ssh` MCP: call `list-servers` for the current snapshot, then
`execute-command`, `upload`, or `download` with `connectionName` set to a
`profileId` from that list.
- Home (`home-server`) at alice@192.168.1.8:22 — `/home/alice/proj`
```

多 folder 写在同一 bullet 的路径列表里。MCP 工具名用规范名（`list-servers` 等），不写 Claude `mcp__ssh__*` 或 Cursor `Mcp(ssh:…)` 别名。

## 错误处理

- extras / 远程 / MCP 都空 → 不贡献 prompt；不抛。
- 有 ssh 文件夹但 `sshMcpInjected=false` → 不写 Remote projects、不提 `ssh` MCP。
- 路径规范化失败或空白 → 跳过该目录（现有 `WorkspaceAccess` 规则）。
- 缺 snapshot 字段按空处理。
- 重复 `providerId` 仍由 `ResourceProviderSet` 在装配时 `StateError`。
- 纯函数 `composeWorkspaceBaseInfoPrompt` 不抛、不 IO。

## 测试

`cd client && dart run tool/run_tests.dart`，不要直接 `flutter test`。构造注入，不打真 SSH。

**compose**

- 全空 → `''`
- 仅 extras → 有 Workspace directories，无 Remote projects
- 仅 `sshMcpInjected` + remoteFolders → 只有 Remote projects，含 profileId 与路径，无密钥
- extras + MCP → 两段都有
- 有 remoteFolders 但 `sshMcpInjected=false` → `''`（若也无 extras）
- `customPromptSections` 非空时接在后面（锁定槽位；本期生产路径传 `[]`）

**argv**

- 现有 `workspace_access_arg_provider_test` 改挂新基类
- Claude / Cursor / Codex / FlashskyAI 编码与现测一致（含 WSL、空白过滤）
- OpenCode `buildLaunchArgs` 为空；`mergeOpencodeExternalDirectories` 测保持

**装配 / 角色 prompt**

- `composeRolePrompt` 不再含 `## Workspace directories`
- OpenCode member-role 贡献不再带目录章节；装配 document 里目录只来自 `workspace-base-info`
- dirs-only：`syncRolePromptFile` 无角色正文则不写；装配路径在条件 B 下仍写出仅含 `workspace-base-info` 的 document

**契约**

- 五个 CLI 都能 `capability<WorkspaceBaseInfoCapability>`
- Headless 走 registry，不直接 `new` 旧 Launch 类

不做 UI 测。不测 MCP 工具本身。

## 文件落点

- `client/lib/services/cli/registry/capabilities/workspace_base_info_capability.dart` — 接口、共享基类、snapshot、remote 展示类型、compose
- `client/lib/services/cli/registry/launch/workspace_access.dart` — 保留 `WorkspaceAccess` + 路径规范化；删除 `WorkspaceAccessArgProvider`
- 删除 `workspace_access_arg_provider.dart`
- 各 CLI `capabilities/workspace_access_launch.dart` → `workspace_base_info.dart`，类名 `*WorkspaceBaseInfo`
- OpenCode `*_tool.dart` 注册该能力
- `built_in_cli_tools.dart` — `_verifyRequired<WorkspaceBaseInfoCapability>`
- `prompt_contribution_provider.dart`、`cli_resource_provisioner.dart`、`prompt_hub_service.dart`、prompt capability 上下文 — 下传 `sshMcpInjected` / `remoteFolders`
- `config_profile_service.dart` 与 session/launch 调用链 — 从 compose extra MCP 与 folders 填这两项
- `member_role_provision.dart` — 删除目录章节
- `opencode/capabilities/prompt.dart` — 不再 `composeWorkspaceDirectoriesPrompt`
- headless 各 CLI — registry 取能力
- 对应单测（含 `member_role_provision_prompt_test`、`opencode_external_directories_test` 里 prompt 断言）

文档：实现时在 `docs/cli-architecture.md` 把该能力列为必选，并说明它同时贡献 argv 与 prompt。
