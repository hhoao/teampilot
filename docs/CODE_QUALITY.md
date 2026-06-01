# 代码质量规范

面向贡献者与 AI 助手：在 [AGENTS.md](../AGENTS.md) 架构约定之上，约定**文件体量、分层、测试与已知限制**，避免页面与 Cubit 无限膨胀、测试误报与集成缺口被忽略。

英文版：[CODE_QUALITY.en.md](CODE_QUALITY.en.md)。

## 质量门禁（必须）

合并前在 `client/` 下通过（与 [Client Build Verify](../.github/workflows/client-verify.yml) 一致）：

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```

声称完成前必须实际运行上述命令并确认通过，不得仅凭 IDE 或无输出推断。

## 分层与职责

| 层 | 目录 | 职责 |
|----|------|------|
| UI 单屏模块 | `pages/<route>/` | 该路由的**页面壳**（`*_page.dart` / `*_workspace.dart`）、section、对话框、路由 helper（参考 `pages/mcp/`） |
| UI 跨屏复用 | `widgets/` | 多页面/工作台共用的控件与布局（`dropdown/`、`settings/`、`split_layout.dart` 等） |
| 状态 | `cubits/` | 用户动作、加载态、错误态；调用 repository / service |
| 持久化 | `repositories/` | JSON / 文件读写；通过 `Filesystem` + `AppStorage` 路径 |
| 领域逻辑 | `services/` | 安装、探测、终端、CLI 配置、链接技能/插件等 |
| 模型 | `models/` | 不可变数据结构、`fromJson` / `toJson` |

**路径：** 一律 `AppStorage` / `RuntimeStorageContext`，禁止用 `Directory.current` 作为默认工程或应用数据根。

**依赖注入：** 涉及子进程、网络、文件系统的服务应支持构造函数注入（如 `runner`、`processRunner`、`Filesystem`），便于单测 mock。参考 `ExtensionAcquisitionEngine`、`ExtensionDetector`。

### `pages/` 与 `widgets/` 如何区分

| 问题 | 放在哪里 | 示例 |
|------|----------|------|
| 只服务一个路由/设置屏？ | `pages/<域>/` | `pages/skills/skill_discovery_section.dart`、`pages/team_config/team_config_member_section.dart` |
| 两个及以上无关页面都会 import？ | `widgets/` | `FlashskyDropdownField`、`WorkspaceHubPage`、`AppProviderListPanel` |
| 页面壳 + 枚举 + Hub？ | `pages/*_page.dart`（可 `export` 同域子目录中的路由类型） | `mcp_management_page.dart`、`skill_management_page.dart` |

**不要**把「仅技能管理页使用」的 section 放进 `widgets/` 下以页面命名的子目录。拆分超大页面时，优先 **`pages/<域>/`**，与 `client/lib/pages/mcp/` 对齐。

推荐布局（**壳与 section 同目录**，参考 `pages/mcp/`）：

```
pages/
  mcp/
    mcp_management_page.dart    # 壳 + McpSection 等
    mcp_installed_section.dart
    ...
  plugins/
    plugin_management_page.dart
    plugin_installed_section.dart
    ...
  skills/
    skill_management_page.dart
    ...
  team_config/
    team_config_page.dart
    ...
  llm_config/
    llm_config_workspace.dart
    ...
```

## 文件体量（软上限）

| 类型 | 软上限 |
|------|--------|
| `pages/*_page.dart`、workspace 壳 | ~400 行 |
| `pages/<域>/` 内单个 section 文件 | ~500 行（超出则再拆文件或抽 **共享** widget） |
| `cubits/` | ~500 行 |
| `services/` | ~600 行 |

**禁止：** 在未拆分的情况下向已超过 **~800 行** 的页面继续堆叠大块 UI 或业务逻辑。应顺带抽 section 文件并补测试。

**生成代码：** `l10n/app_localizations*.dart` 不计入上述上限；不要手改生成文件。

## UI 与状态

- 单屏专用的复杂表单、列表、对话框放在 **`pages/<域>/`**；跨屏组件放在 **`widgets/`**。页面通过 `BlocBuilder` / `context.read` 连接 Cubit。
- **状态管理固定为 `flutter_bloc`（Cubit）**；不要在业务代码中引入 `provider` / `ChangeNotifier` 作为并列方案。
- Cubit 状态类型使用 `Equatable`（或不可变 `copyWith`），区分 `loading` / `ready` / `error`；长操作使用 `busyIds` 等细粒度忙碌标记（见 `ExtensionCubit`）。
- 用户可见错误用 l10n 字符串，避免裸 `e.toString()` 作为最终文案（调试日志除外）。
- 路由使用既有 **`go_router`**（`app_router.dart`）；短生命周期界面（对话框、临时 sheet）可用 `Navigator`。

### Flutter UI 实践（拆分大页面时遵守）

触达 `team_config_page`、`llm_config_workspace`、`skill_management_page` 等超大文件时，优先按下列方式减负，而不是继续加长单文件：

| 做法 | 说明 |
|------|------|
| 独立 **Widget 类** | 将 `build()` 中的大块 UI 拆成 `class FooSection extends StatelessWidget`，放在 **`pages/<域>/`**（或同文件内的 private 类，若很短）。**避免**用「返回 `Widget` 的 private 方法」堆叠同文件逻辑。 |
| 组合优于继承 | 用小组件拼装；控制 `Row`/`Column` 嵌套深度。 |
| 长列表 | 技能/插件/扩展等列表使用 **`ListView.builder` / `SliverList`**，不要一次性 `children: [...]` 构建大量子项。 |
| `build()` 要轻 | **禁止**在 `build()` 内做磁盘/网络/子进程、大 JSON 解析或重计算；放到 Cubit/Service，由 `BlocBuilder` 展示结果。 |
| `const` | 子树不变时在 `build` 中使用 `const` 构造函数，减少桌面端无效重建。 |

同域多个 section 共用的卡片/空态（如 MCP 的 `mcp_shared_widgets.dart`）放在 **同一 `pages/<域>/` 目录**，仍不要挪到 `widgets/`，除非已有第二处路由引用。

## 函数与逻辑体量

- 单函数/单方法以 **单一职责** 为准；超过 **~30 行** 且含分支与 IO 时，考虑抽到 `services/` 或独立 widget。
- Cubit 的 `onXxx` / 事件处理方法若超过 **~40 行**，应将领域步骤下沉到 service，Cubit 只编排与 `emit`。

## 错误处理与日志

- 预期失败（安装失败、探测未找到）返回结果类型或 Cubit 错误态，**不要**吞异常或空 `catch`。
- 用户文案 → **l10n + Cubit state**；诊断信息 → **`AppLogger`**（`utils/logger.dart`）。**禁止** `print`；新增代码勿依赖 `debugPrint` 作为持久日志。
- 遵守 [DEBUGGING.md](DEBUGGING.md)：框架/引擎类错误先外部检索，再改业务代码。

## 模型与代码生成

- 持久化与 API 模型使用 **`json_serializable` + `json_annotation`**；修改后运行 `dart run build_runner build --delete-conflicting-outputs`（见 [DEVELOPMENT.md](DEVELOPMENT.md)）。
- 新模型与**同目录/同域已有模型**保持一致的 JSON 字段命名与 `@JsonSerializable` 选项；不要混用另一套 key 风格。
- 仅对 **`services/`、`repositories/` 及对外复用的 model** 写 `///` 文档；页面 section 以自解释命名为准。

## 桌面布局

- 设置页、团队配置等宽屏表单：优先 **`Expanded` / `Flexible` / `Wrap`** 处理 `Row` 溢出；固定大块内容用 `SingleChildScrollView`，长列表仍用 builder。
- 响应式：需要时用 `LayoutBuilder` / `MediaQuery`；Android 与桌面共用组件时注意最大宽度与触控目标尺寸。

## 无障碍（基础）

- 仅图标按钮、终端旁工具控件：提供 **`tooltip` 或 `Semantics(label: …)`**。
- 颜色对比与字号跟 **`ThemeData` / `textTheme`**，避免硬编码浅灰字 on 浅底。
- 支持系统字体缩放时，确认表单与侧栏在放大后仍可滚动、不裁切关键操作。

## 测试规范

### 默认（CI）

- 命令：`flutter test --exclude-tags integration`
- 新功能：**优先** 为 `services/`、`repositories/`、`cubits/` 写单测。
- 改大页面时：至少补 **Cubit**；从页面新抽到 **`pages/<域>/`** 的 section 应补 **widget 测**（可只覆盖交互与关键文案/空态）。
- 结构：单测遵循 **Arrange–Act–Assert**（或 Given–When–Then），一个 `test` 只验证一个行为。

### 集成测试

- 标签：`@Tags(['integration'])`（`package:test`）。
- 场景：真实 PTY、CLI 探测、跨进程行为；**不**纳入默认 CI（见 [DEVELOPMENT.md](DEVELOPMENT.md) Linux 步骤）。
- 新增 integration 测时：在 PR 说明中注明如何本地运行；目标逐步覆盖 **2～3 条黄金路径**（示例：创建团队会话 → 连接一个 member 终端）。

### 测试环境

凡测试代码路径会触发 `AppStorage` / `RuntimeStorageContext`：

- 在 `setUp` 调用 `setUpTestAppStorage()`，在 `tearDown` 调用 `tearDownTestAppStorage()`（`client/test/support/post_frame_test_harness.dart`）。
- **不要** 依赖未安装 storage 的 Cubit 构造后后台任务——会产生 `RuntimeStorageContext.install() must be called` 等噪音并掩盖真实失败。

`ChatCubit` 等使用 post-frame 调度时，使用 `PostFrameTestHarness` / `runScheduledCallback` 确定性刷队列。

### Mock 与 Fake

- **优先 fake/stub**（构造函数注入内存 `Filesystem`、假 `runner` 返回固定 `ProcessResult`），与 `ExtensionAcquisitionEngine` 等现有测法一致。
- 仅在难以 fake 的边界使用 mock；**不**为引入新栈而默认采用 `mockito` / `mocktail`。
- 需要 mock 时：子进程、SSH、真实网络、未初始化的 `AppStorage` 副作用。
- 不 mock：纯函数、与真实实现行为一致的 trivial 类型。
- 安装类逻辑：注入 `ExtensionInstallRunner` / `ProcessRunner`，不要在本机执行 `npm install -g`。
- 集成测继续使用 **`@Tags(['integration'])` + `package:test`**，不改为 `integration_test` 包，除非全库迁移方案已评审。

## Bootstrap / `app_shell.dart`

- 新 Cubit / Repository 在 `buildAppShell()`（或等价工厂）中**显式**构造并挂到 `AppShell` 字段，避免静态单例。
- 当 `app_shell.dart` 单次变更大于 **~80 行** 时，考虑按域抽取（例如 `extensionBootstrap(...)` 返回 `(ExtensionCubit, ExtensionRepository, ...)`）。
- 测试环境使用 `RuntimeStorageContext.installForTesting`，勿在单测中调用生产 `install()` 除非专门测试 bootstrap。

## Dart 习惯

- 异步：`async`/`await` 配 `try/catch` 时要在 Cubit/service 层转化为用户可理解的结果，勿把未处理异常抛到 UI `build`。
- 命名：`PascalCase` 类型、`camelCase` 成员、`snake_case` 文件名；避免无意义缩写。
- `pages/<域>/` 内引用共享 UI：`import '../../widgets/...'`；引用同域 section：`import 'foo_section.dart'`。

## 技术债与注释

- 避免新增 `TODO` / `FIXME`，除非同一 PR 内有 issue 链接或短期跟进计划。
- 禁止用 `// ignore` 掩盖 analyze 问题；确需 ignore 时注明原因与跟进 issue。
- 注释解释 **为什么**，不复述代码做什么；公共 service API 用 `///`，内部实现尽量自解释。

## 发布前人工检查（集成测未覆盖部分）

- Linux / Windows / macOS 至少一处：**团队配置 → 保存 → 开团队会话 → 成员终端连接**。
- 若改动 Extension / MCP / 技能链接：在团队配置页切换开关并启动会话，确认 `config-profiles` 侧效应。
- Android / SSH 模式：按变更范围手测存储路径与终端连接。

## 相关文档

| 文档 | 内容 |
|------|------|
| [AGENTS.md](../AGENTS.md) | 架构、关键路径、简要约定 |
| [DEVELOPMENT.md](DEVELOPMENT.md) | 环境、命令、集成测运行 |
| [DEBUGGING.md](DEBUGGING.md) | 排错流程 |
