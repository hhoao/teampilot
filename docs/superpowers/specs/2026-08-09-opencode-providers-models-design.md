# opencode 供应商 + 模型目录全量适配

**日期:** 2026-08-09
**状态:** 已确认设计（待实现）

## 背景

opencode 的"连接供应商"能力里，订阅类供应商与 teampilot 的适配存在缺口（已对照 `/home/hhoa/git/opensource/opencode` 源码 + 实时 models.dev 目录验证）：

| Provider | 是什么 | endpoint / npm | env | 模型数 |
|----------|--------|----------------|-----|--------|
| `opencode` (OpenCode Zen) | 按量付费 API key | `https://opencode.ai/zen/v1`，`@ai-sdk/openai-compatible` | `OPENCODE_API_KEY` | 87（实时） |
| `opencode-go` (OpenCode Go) | $5 首月 / $10 每月订阅 | `https://opencode.ai/zen/go/v1`，`@ai-sdk/openai-compatible` | `OPENCODE_API_KEY` | 24（实时） |

关键事实（源码确认）：

- opencode 登录对话框 `PROVIDER_PRIORITY`（`packages/opencode/src/cli/cmd/tui/component/dialog-provider.tsx`）排序 `opencode:0`、`opencode-go:1`、`openai:2`…；连完 provider 后跳到 `DialogModel` 选模型 —— 即"设置了 provider 后也需要配置 model"。
- 两者共用 `OPENCODE_API_KEY` env；opencode.json 里写 `provider.<id>.options.apiKey` 即可；模型用 `--model <id>/<model>`。
- opencode 的 provider 目录同步自 models.dev（`packages/opencode/src/cli/cmd/providers.ts` 调 `modelsDev.refresh(true)`）；`opencode-go` 在其中，`opencode providers login -p opencode-go` 可用。

teampilot 当前状态：

- **已适配 Zen**：`OpencodeProviderPresets` 有 `opencode` preset（`isOfficial`、`apiKeyUrl: opencode.ai/zen`、默认模型 `claude-sonnet-4-5`）；凭据能力层按 `isOfficial` 提供 login/import/revoke；launch 层 `mergeOpencodeProvider`（`opencode_config_profile_capability.dart`）写 `provider.opencode.options.apiKey`，opencode 侧 `custom` loader 正好读这里。
- **缺口**：无 `opencode-go` preset → UI 加不了、live-import 命中非 preset 分支被降级成 `custom`（凭据能力失效）、无默认模型；`OpencodeModelCatalog` 是手维护子集（zen 31 个 vs 实时 87 个），且没有 `opencode-go` 键。

## 目标

1. 在 teampilot 中体验 opencode 的**完整供应商 + 完整模型**：新增 `opencode-go` 订阅供应商，模型选择器显示各 provider 的**实时全量**模型。
2. 复用项目既有架构（`CursorAgentModelsService` 的 live-fetch + 磁盘缓存模式），不新增 UI 面；`provider_model_picker_field.dart` 已泛化支持 `RefreshableProviderModelCapability`，UI 零改动。
3. 离线时自动回退到静态清单，不劣于现状。
4. **遵循 CLI 架构规范**（`docs/cli-architecture.md`）：代码落在 per-CLI 目录 `services/cli/opencode/` 下；把仍留在共享 `registry/capabilities/provider_model_capability.dart` 的 `OpencodeCatalogSource` / `OpencodeProviderModelCapability` 迁到 `services/cli/opencode/provider/opencode_provider_model_capability.dart`（对齐 cursor/claude 的 per-CLI 先例），共享文件只留接口定义与 `ProviderRecordModelCapability`。

## 非目标

- 不把 models.dev 的 live-fetch 推广到其它 CLI（claude/codex/cursor 各有自己的目录来源）。
- 不改 opencode 的 launch/凭据链路（`mergeOpencodeProvider`、`OpencodeProviderCredentialsService` 均按 `provider.id` 泛化，补 preset 即通）。
- 不为 opencode 引入模型 tier（`supportsModelTiers` 保持 false）。
- 不在 spec 范围内新增"其它 provider" preset（如 github-copilot）；本次只补订阅类 `opencode-go`。

## 设计

### 1. `opencode-go` preset（`client/lib/services/cli/opencode/provider_presets.dart`）

在 `OpencodeProviderPresets.all` 增加一项：

```dart
AppProviderPreset(
  id: "opencode-go",
  label: "OpenCode Go (subscription)",
  template: AppProviderConfig(
    id: "opencode-go",
    cli: CliTool.opencode,
    name: "OpenCode Go",
    websiteUrl: "https://opencode.ai",
    apiKeyUrl: "https://opencode.ai/go",
    category: AppProviderCategory.official,
    baseUrl: "https://opencode.ai/zen/go/v1",
    defaultModel: "deepseek-v4-flash",
    config: {"npm": "@ai-sdk/openai-compatible"},
    isOfficial: true,
  ),
),
```

- `baseUrl` + `config.npm` 显式带上，使 preset **自包含**：即便某版本 opencode 目录里缺 `opencode-go`，launch 也能解析（`mergeOpencodeProvider` 写 `options.baseURL` + `entry.npm`）。
- 默认模型 `deepseek-v4-flash`（Go 目录内廉价可靠；picker 会展示全部 24 个，默认仅作预填）。

效果链：
- UI 供应商列表出现 "OpenCode Go (subscription)"；
- 凭据能力 `appliesTo`（要求 `cli == opencode && isOfficial`）命中 → login/import/revoke 全可用，`opencode providers login -p opencode-go` 走通；
- 全局 auth.json live-import（`OpencodeLiveImport`）命中 preset → `isOfficial: true`，不再降级成 `custom`。

### 2. `OpencodeModelsService`（新文件 `client/lib/services/cli/opencode/provider/opencode_models_service.dart`）

镜像 `CursorAgentModelsService`（`client/lib/services/cli/cursor/provider/cursor_agent_models_service.dart`）但面向**全局目录**：

- 运行时拉 `https://models.dev/api.json`（opencode 自己同步的目录；首拉几 MB，一个 TTL 只拉一次）。
- HTTP 客户端可注入（构造参数 `http.Client?`；测试用 `package:http/testing.dart` 的 `MockClient`）。
- 解析为 `providerId → List<String> modelIds`；`modelIdsFor({providerId})` 读对应切片，未知 provider 返回空。
- 单条全局磁盘缓存 `<teampilotRoot>/cache/opencode_models/opencode.json`（models.dev 目录非 per-account，不需要 cursor 那样按账号建 key）。
- TTL 6h（对齐 cursor 的 `cacheTtl`）；in-flight 去重；`catalogUpdates`（`Listenable`）供 picker 订阅。
- 失败路径：拉取失败且磁盘缓存存在且新鲜 → 用缓存；仅磁盘存在（过期）→ 兜底用；全空 → 返回空（由静态回退接手）。**不抛异常**。

models.dev 的 provider 顶层没有"默认模型"字段 → `defaultModelIdFor` 不需要，默认模型仍由 preset 的 `defaultModel` 决定。

### 3. Capability 迁移 + 升级 + 接线

**3a. 新建 per-CLI 能力文件** `client/lib/services/cli/opencode/provider/opencode_provider_model_capability.dart`：

把 `OpencodeCatalogSource` + `OpencodeProviderModelCapability` 从共享 `registry/capabilities/provider_model_capability.dart` **迁出**，并升级为 live-fetch 版：

```dart
final class OpencodeCatalogSource implements ModelCatalogSource {
  const OpencodeCatalogSource(this._modelsService);
  final OpencodeModelsService? _modelsService;
  @override
  List<String> modelsFor({required AppProviderConfig? provider, required String providerId}) {
    final id = provider?.id ?? providerId;
    final live = _modelsService?.modelIdsFor(providerId: id) ?? const [];
    if (live.isNotEmpty) return live;
    return OpencodeModelCatalog.knownModelsForProvider(id);
  }
}

final class OpencodeProviderModelCapability extends CatalogModelCapability
    implements RefreshableProviderModelCapability {
  OpencodeProviderModelCapability({OpencodeModelsService? modelsService})
      : _modelsService = modelsService;
  final OpencodeModelsService? _modelsService;
  @override
  bool get supportsModelTiers => false;
  @override
  List<ModelCatalogSource> get catalogSources => [OpencodeCatalogSource(_modelsService)];
  @override
  Listenable get catalogUpdates => _modelsService?.catalogUpdates ?? _emptyCatalogUpdates;
  @override
  Future<void> refreshModelCatalog({required String providerId, String? executable, bool forceRefresh = false})
      => _modelsService?.refresh(providerId: providerId, forceRefresh: forceRefresh) ?? Future.value();
  @override
  ProviderModelPickerMode pickerMode(AppProviderConfig provider) => ProviderModelPickerMode.catalogWithCustomEntry;
}
```

（`executable` 参数忽略——HTTP 拉取不需要。`Listenable`/`RefreshableProviderModelCapability`/`ModelCatalogSource`/`CatalogModelCapability` 等接口与基类、`ProviderRecordModelCapability` 继续留在共享 `registry/capabilities/provider_model_capability.dart`。）

**3b. 更新 `opencode_tool.dart`**（`client/lib/services/cli/opencode/opencode_tool.dart`）：
- 构造参数 `this.providerModel = const OpencodeProviderModelCapability()` 改为 `OpencodeProviderModelCapability? providerModel` + `providerModel ?? OpencodeProviderModelCapability()`（mirror `CursorCliTool`）。
- import 从 `../registry/capabilities/provider_model_capability.dart` 改为 `provider/opencode_provider_model_capability.dart`（interface 若仍需要 `ProviderModelPickerMode` 等可保留对共享文件的 import）。

**3c. Bootstrap 注入**：
- `client/lib/services/cli/opencode/opencode_bootstrap_entry.dart`：新增 `final OpencodeModelsService? modelsService;`（mirror `CursorBootstrapEntry.agentModelsService`）。
- `client/lib/services/cli/registry/built_in_cli_tools.dart`：`OpencodeCliTool(providerModel: OpencodeProviderModelCapability(modelsService: opencodeEntry?.modelsService), …)`。
- `client/lib/app/app_shell.dart`：`CliBootstrap` map 里 `OpencodeBootstrapEntry(credentialsService: …, modelsService: OpencodeModelsService())`。

**收益**：`provider_model_picker_field.dart`（`lib/widgets/app_provider/provider_model_picker_field.dart`）已泛化——capability 实现 `RefreshableProviderModelCapability` 后，picker 打开即触发 refresh、显示加载指示条、`catalogUpdates` 后刷新候选。**UI 零改动**。

### 4. 静态回退清单（`client/lib/services/cli/opencode/provider/opencode_model_catalog.dart`）

- `_byProviderId` 增加 `'opencode-go'`：按实时 models.dev 目录的 24 个模型 id 列出（`deepseek-v4-flash/pro`、`glm-5/5.1/5.2`、`kimi-k2.5/k2.6/k2.7-code/k3`、`mimo-v2-*`、`minimax-m2.5/m2.7/m3`、`qwen3.5-plus/3.6-plus/3.7-max/3.7-plus/3.8-max`、`gpt-5.6-luna`、`grok-4.5`、`hy3`）。
- `zen` 清单刷新到实时 87 个（live-fetch 主用，静态仅离线兜底）。
- 其它 provider（openai/anthropic/google/deepseek/groq/xai）保持基线。

### 5. 测试

- **`client/test/services/provider/opencode/opencode_models_service_test.dart`**（新建，与现有 opencode 测试目录一致）：注入 `MockClient`（`package:http/testing.dart`）返回 api.json fixture；覆盖：解析切片、TTL 新鲜命中、磁盘缓存读写、in-flight 去重、拉取失败回退、离线兜底空返回。用 `setUpTestAppStorage()` / `tearDownTestAppStorage()`。
- **preset 测试**：断言 `OpencodeProviderPresets.byId('opencode-go')` 命中且 `isOfficial`；`OpencodeLiveImport` 在 auth.json 含 `opencode-go` 条目时产出 official provider。
- **能力迁移**：确认 `registry/capabilities/provider_model_capability.dart` 不再含 opencode 实现；`opencode_tool.dart` 的 `ProviderModelCapability` 来自 per-CLI 文件。
- 现有 opencode 凭据/catalog 测试保持绿；最后 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。

## 验证

1. 单测绿（上述新增 + 现有）。
2. 手动：`flutter run -d linux` → opencode provider 表单 → 添加 "OpenCode Go (subscription)" → 模型下拉出现 24 个实时模型；Zen 下拉出现全量（含刷新后新增）。
3. 断网场景：模型下拉回退到静态清单，不报错。
