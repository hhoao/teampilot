# 提示词管理：全局 / 工作区范围的系统提示词库与自动注入

## 背景

TeamPilot 的系统提示词已经有一条统一的装配链路：`PromptHubService` 把多个
`PromptContributionProvider` 的贡献装配成 `PromptDocument`，再由每个 CLI 的
`PromptCapability` 落盘到自己的原生位置（`AGENTS.md`、`rules/teampilot.md`、
`--append-system-prompt-file` 等）。

现有贡献来源全部是代码内固定的：

- 成员角色：`MemberRoleProvision`（各 CLI 的 `capabilities/prompt.dart`）
- 工作区基础信息 / 额外目录 / 远程目录：`WorkspaceBaseInfoCapability`
- TeamPilot catalog 说明：`CatalogPromptProvider`

用户无法添加自己的长期系统提示词。Skills / Plugins / MCP / Hooks 都有
「全局库 + 管理页 + 启动时自动装配」这一层，提示词缺这一层。

另注：l10n 中的 `workspaceAgentPrompt*` 与
`models/workspace_agent_prompt_presets.dart` 当前没有任何运行时代码引用
（dead code），本方案不基于它们实现。

## 目标

1. **全局提示词库**：在全局管理页增删改查、启用/停用。
2. **工作区提示词库**：按工作区独立增删改查、启用/停用。
3. **自动注入**：启动会话时把启用项拼进系统提示词，所有实现
   `PromptCapability` 的 CLI（claude / flashskyai / codex / opencode / gemini /
   cursor / qoder / codebuddy / antigravity）自动生效，不按 CLI 分支。
4. **工作区可单独关闭全局项**：不改动全局定义，只影响当前工作区。
5. **管理入口与 Hooks 一致**：全局侧边栏 + 工作区设置 section + 独立路由。

## 非目标

- 不做团队级 / 专家级 / 成员级提示词范围。
- 不做变量占位符（`{{workspace}}` 等）展开；正文按纯 Markdown 原样注入。
- 不做热更新：运行中的会话不重新装配，新会话或重启后生效
  （与 skills / MCP 一致）。
- 不做导入 / 导出 / 市场 / 版本历史。
- 不实现「提示词作为 CLI 原生 slash command」。
- 不改现有的成员角色 / 工作区基础信息贡献内容。

## 范围语义

- **全局提示词**：对所有工作区、所有会话、所有成员 seat 生效；
  某个工作区可以通过 `disabledPromptIds` 单独关闭。
- **工作区提示词**：只在该工作区启动的会话生效；不跨工作区。
- 不区分 Simple / Team；同一工作区内的每个 seat 都注入。
- 注入顺序固定：全局（`order` → `name`）→ 工作区（`order` → `name`）。

## 数据模型

新增 `client/lib/models/prompt_definition.dart`：

```dart
@immutable
class PromptDefinition {
  const PromptDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.content = '',
    this.enabled = true,
    this.order = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;          // Uuid().v4()
  final String name;        // 必填，展示用
  final String description; // 可选
  final String content;     // 必填，Markdown 原文
  final bool enabled;
  final int order;          // 升序；新建时 = max + 1
  final DateTime createdAt;
  final DateTime updatedAt;

  PromptDefinition copyWith({...});
  Map<String, Object?> toJson();
  factory PromptDefinition.fromJson(Map<String, Object?> json);
}
```

`order` 只是同层排序；不参与跨层比较。

## 存储

两份独立存储，**范围由所在存储决定**，模型不额外存 `scope`：

| 范围 | 路径 | 说明 |
|------|------|------|
| 全局 | `<teampilotRoot>/prompts/prompts.json` | 跟随 home plane |
| 工作区 | `<workspaceDir>/prompts.json` | 与 `project-config.json` 平级；删除工作区时随之删除 |

文件格式（单文档，`atomicWrite`）：

```json
{
  "version": 1,
  "prompts": [
    {
      "id": "0b6f...",
      "name": "代码审查口径",
      "description": "团队统一审查标准",
      "content": "## Review\n- ...",
      "enabled": true,
      "order": 0,
      "createdAt": "2026-11-08T10:00:00.000Z",
      "updatedAt": "2026-11-08T10:00:00.000Z"
    }
  ]
}
```

布局 helper：

- `AppPaths.promptsDirForTeampilotRoot(root)` → `<root>/prompts`
- `WorkspaceLayout.promptsFile(workspaceId)` → `<workspaceDir>/prompts.json`

同时更新 `docs/workspace-storage-layout.md`。

## 仓储

新增 `client/lib/services/prompt/prompt_repository.dart`：

```dart
class PromptRepository {
  PromptRepository({required Filesystem fs, required String directory});
  factory PromptRepository.global({required Filesystem fs, required String teampilotRoot});
  factory PromptRepository.workspace({required Filesystem fs, required String workspaceDir});

  Future<List<PromptDefinition>> loadAll();       // 损坏 → 空列表 + AppLogger 诊断
  Future<PromptDefinition?> load(String id);
  Future<void> save(PromptDefinition prompt);      // upsert
  Future<void> delete(String id);
}
```

- 读取时按 `order`、`name`、`id` 稳定排序。
- 写入前 trim `name` / `content`；`name` 或 `content` 为空时抛
  `PromptValidationException`（UI 会先校验，仓储兜底）。
- 同一文件写入使用 `Filesystem.atomicWrite`；不做跨进程锁（与其它 JSON 仓储一致）。

## 注入链路

### 1. 启动时加载

在 `ConfigProfileService` 的资源装配前（`_provisionStagedResources` 之前）
统一解析：

```dart
Future<List<PromptDefinition>> _enabledUserPrompts({
  required String workspaceId,
  required Set<String> disabledGlobalIds,
}) async {
  final global = await PromptRepository.global(
    fs: catalog.fs,
    teampilotRoot: catalog.basePath,
  ).loadAll();
  final workspace = await PromptRepository.workspace(
    fs: catalog.fs,
    workspaceDir: catalog.layout.workspace.workspaceDir(workspaceId),
  ).loadAll();
  return [
    ...global.where((p) => p.enabled && !disabledGlobalIds.contains(p.id)),
    ...workspace.where((p) => p.enabled),
  ];
}
```

说明：

- 使用 **catalog / home** delegate（`ConfigProfileService.catalog`）读取定义，
  因为工作区目录与全局目录都在 home plane。
- 工作区提示词定义不会被复制到工作机；只有最终装配出的提示词文档由
  `PromptCapability` 写到目标 config dir，沿用现有远端行为。
- `disabledGlobalIds` 来自 `runtimeBundle.disabledPromptIds`
  （见下文「工作区关闭全局项」）。
- 解析失败（文件损坏、权限）只记 warning，不阻塞启动。

### 2. 贡献提供者

新增
`client/lib/services/resource/providers/user_prompt_contribution_provider.dart`：

```dart
final class UserPromptContributionProvider implements PromptContributionProvider {
  UserPromptContributionProvider({
    required Iterable<PromptDefinition> globalPrompts,
    required Iterable<PromptDefinition> workspacePrompts,
  });

  @override
  String get providerId => 'user-prompts';

  @override
  FutureOr<Iterable<PromptContribution>> provide(PromptProviderContext context);
}
```

每个启用项产出一条贡献：

- `id`: `user-prompt:<prompt.id>`（稳定、唯一）
- `title`: `prompt.name`
- `content`: `prompt.content.trim()`
- `scope`: `PromptScope.global` / `PromptScope.workspace`
- `mergeRole`: `PromptMergeRole.append`（每项独立 section，避免 replace 冲突）
- `origin`: `ContributionOrigin(providerId: 'user-prompts',
  kind: ResourceOriginKind.managed | ResourceOriginKind.workspace,
  sourceId: prompt.id)`

空内容 / 未知项直接跳过；跳过原因以
`ResourceAssemblyDiagnosticSeverity.warning` 形式返回。

`order` 在同一范围内排序，跨范围固定全局在前。

### 3. 装配点

在 `ConfigProfileService` 的两处资源装配点把 provider 加入
`ResourceProviderSet(prompts: [...])`：

1. `prepareSimpleSessionLaunch` 的资源阶段（约
   `config_profile_service.dart:1054`）
2. `prepareTeamLaunch` 的资源阶段（约
   `config_profile_service.dart:1525`）

顺序：`providers.prompts`（CLI 内置 + catalog）→ `userPromptProviders` →
`injectedResourceProviders.prompts`。用户提示词因此追加在 CLI 内置内容之后。

`CliResourceProvisioner.provision` 的 `_assemblePrompt` 已经会 await 异步
provider，无需改动装配器；`PromptCapability` 按现有逻辑写入
`AGENTS.md` / `rules/teampilot.md` / append 文件。

### 4. 生效时机

- 新会话：下次启动时装配。
- 已有会话：重新打开 / 重启该会话后装配。
- 运行中会话不热更新。

## 工作区关闭全局项

`ConfigBundle` 增加：

```dart
final List<String> disabledPromptIds;
```

- 序列化键：`disabledPromptIds`（省略空列表）。
- 放在 `ConfigBundle` 而不是 `WorkspaceProjectConfig` 顶层，是为了让
  `WorkspaceProjectConfigRepository` → `LayeredConfigBundle.merge` →
  `runtimeBundle.disabledPromptIds` 这条现有链路直接把值送到装配点；
  expert / team 层的 bundle 该字段为空。
- `copyWith` / `==` / `hashCode` / `LayeredConfigBundle.merge` 同步更新。
- 只影响“全局提示词是否注入本工作区”，不影响全局定义本身。
- 工作区设置里切换开关即写该列表。

## 管理界面

### 全局

- `HomeGlobalView` 增加 `prompts`。
- 侧边栏在 Hooks 附近增加「提示词」入口。
- 新路由 `/prompts`（与 `/hooks` 同构），并在 `HomeGlobalSection` 的
  `switch` 中挂载 `PromptManagementPage(embedded: true)`。
- `PromptManagementPage`（仿 `HookManagementPage`）：
  - 标题 + 计数 + 「新建提示词」
  - 列表行：名称、描述、启用开关、内容长度 / 更新时间、编辑、删除
  - 空态：`TpEmptyState` + 新建按钮
- `PromptEditorDialog`：
  - 字段：名称（必填）、描述、内容（多行，`TextField` `maxLines: null`）、启用
  - 保存调用 `PromptCubit.upsert`，失败 toast

### 工作区

- `WorkspaceConfigSection` 增加 `prompts`（route segment `prompts`，图标使用
  `Icons.article_outlined` 或 `Icons.sticky_note_2_outlined`）。
- `WorkspacePromptsSection`：
  - 上半部分：全局提示词列表 + 本工作区开关（写
    `disabledPromptIds`；全局已停用的项也显示但标记为全局停用）
  - 下半部分：本工作区提示词列表（CRUD，复用 `PromptEditorDialog`）
  - 顶部操作：`管理全局提示词`（跳 `/prompts`）
- 复用 `TeamConfigCard` / `WorkspaceLibraryCard` 等现有容器样式。

### 状态管理

- `PromptCubit`（全局库）：`load` / `upsert` / `remove` / `toggleEnabled`，
  在 `AppShell` 构造并 `..load()`，与 `HookCubit` 一致。
- 工作区列表用 `WorkspacePromptCubit`（或在 section 内 `FutureBuilder` +
  局部 state）；推荐独立 `WorkspacePromptCubit(repository, workspaceId)`，
  由 `WorkspacePromptsSection` 局部 `BlocProvider` 提供，避免污染全局状态。

## 错误处理与诊断

- 仓储层：文件缺失 → 空；JSON 损坏 → 空 + `AppLogger` warning；
  写入失败向上抛，UI toast。
- 装配层：单个提示词为空内容或 id 重复 → warning diagnostic，跳过，
  不阻塞会话启动。
- 未知 / 已删除 id 只可能出现在 `disabledPromptIds`，读取时忽略即可。
- 全量提示词内容没有长度上限；但若单次装配文档过大，沿用现有
  `prompt=${length}` 诊断日志（`_provisionStagedResources`）。

## 兼容性与风险

| 风险 | 处理 |
|------|------|
| 旧会话路径 `PromptHubService.provisionForCli` 只使用 registry providers | `ConfigProfileService` 正常启动路径已统一在 stage 阶段物化并传 `promptAlreadyMaterialized: true`；不会走该回退路径。回退路径保持不变。 |
| 远端（SSH / Termux）读取 home 文件 | 使用 catalog/home `Filesystem` 读取定义；写入仍走现有 `PromptCapability` 目标路径。 |
| 提示词重复注入 | 每个 `PromptContribution` 使用 `user-prompt:<id>` + `append`，不会与内置 section 合并；同 id 由仓储 upsert 保证唯一。 |
| 工作区删除后残留 | 工作区文件随目录删除；全局库不保存工作区项。 |
| 全局项在某个工作区无法关闭 | `disabledPromptIds` 提供覆盖。 |

## 测试计划

新增/扩展：

1. `client/test/models/prompt_definition_test.dart`
   - JSON 往返、缺省字段、`copyWith`、相等性
2. `client/test/services/prompt/prompt_repository_test.dart`
   - 全局 / 工作区 CRUD、排序、损坏文件降级、空 name/content 校验
3. `client/test/services/resource/providers/user_prompt_contribution_provider_test.dart`
   - 全局 + 工作区顺序、`scope`、`mergeRole`、空内容跳过、空 id 跳过
4. `client/test/services/chat/launch/prompt_library_launch_test.dart`
   - `ConfigProfileService` 装配出包含用户提示词的 `PromptDocument`
     （用 fake `PromptCapability` / 伪 CLI，避免真实启动）
   - `disabledPromptIds` 生效
5. Widget 测试（轻量）
   - `PromptManagementPage` 列表 / 空态 / 保存调用
   - `WorkspacePromptsSection` 开关写 `disabledPromptIds`

验证命令（按仓库规则）：

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/models/prompt_definition_test.dart \
  test/services/prompt test/services/resource/providers \
  test/services/chat/launch
```

## 影响文件清单（预估）

**新增**

- `client/lib/models/prompt_definition.dart`
- `client/lib/services/prompt/prompt_repository.dart`
- `client/lib/services/prompt/prompt_validation.dart`（或内联异常）
- `client/lib/services/resource/providers/user_prompt_contribution_provider.dart`
- `client/lib/cubits/prompt_cubit.dart`
- `client/lib/cubits/workspace_prompt_cubit.dart`
- `client/lib/pages/prompts/prompt_management_page.dart`
- `client/lib/pages/prompts/prompt_editor_dialog.dart`
- `client/lib/pages/home_workspace/workspace/config/workspace_prompts_section.dart`
- 对应测试文件

**修改**

- `client/lib/services/storage/app_paths.dart`
- `client/lib/services/storage/workspace_layout.dart`
- `client/lib/models/workspace_project_config.dart`
- `client/lib/models/config_bundle.dart`
- `client/lib/services/chat/launch/staging/layered_config_bundle.dart`
- `client/lib/services/chat/launch/config_profile_service.dart`
- `client/lib/pages/home_workspace/home_workspace_global_section.dart`
- `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- `client/lib/pages/home_workspace/workspace/workspace_config_section.dart`
- `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart`
- `client/lib/router/app_router.dart`
- `client/lib/app/app_shell.dart`
- `client/lib/utils/ui/app_keys.dart`
- `client/lib/l10n/app_en.arb` / `app_zh.arb`（+ 生成的 localizations）
- `docs/workspace-storage-layout.md`

## 验收标准

1. 全局页可以新建、编辑、启停、删除全局提示词；重启 App 后仍在。
2. 工作区设置可以新建、编辑、启停、删除本工作区提示词；切换工作区后互不可见。
3. 新会话启动后，目标 CLI 的原生提示词文件中包含启用项，顺序为全局 → 工作区。
4. 工作区关闭某个全局提示词后，该工作区新会话不再包含它，其它工作区不受影响。
5. 空内容 / 损坏文件不会导致启动失败，只有 warning。
6. `flutter analyze` 与相关测试通过；全量测试在提交前跑一次。
