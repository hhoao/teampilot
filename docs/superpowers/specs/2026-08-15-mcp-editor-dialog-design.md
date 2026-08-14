# MCP 添加/编辑改为 Dialog 表单

- Date: 2026-08-15
- Status: 设计已批准，待实现

## 背景与问题

MCP 的「添加」和「编辑」目前通过 `/mcp/add`、`/mcp/edit/:serverId` 两个整页路由实现（`McpFormNavPage` + `McpFormPage`）。用户在桌面端点击添加后，跳转到整页编辑器：

- 桌面 settings chrome 无返回按钮，用户被困在整页编辑器（页面出不来 / 回不去）；
- 页面内导航面板的「当前项」是 installed 项，看起来不像在添加页。

hook 在 `36f061102`（2026-08-14）遇到过完全相同的结构问题，并已将 `HookEditorNavPage` + `/hooks/new|:id` 路由改为模态 dialog（`showHookEditorDialog` + `HookEditorDialog`）。

**目标：** MCP 添加 + 编辑统一改为 dialog 表单，完全对齐 hook 的 dialog 模式；删除整页路由。

## 设计

### 1. 新建 `client/lib/pages/mcp/mcp_editor_dialog.dart`

- `showMcpEditorDialog(BuildContext, {required McpCubit cubit, McpServer? existing})` → `Future<bool?>`（内部 `showTpDialog<bool>`）。
- `McpEditorDialog`（StatefulWidget）：
  - `TpDialog(maxWidth: 560, maxHeight: 680)` + `TpDialogPinnedLayout`；
  - Header：`TpDialogHeader(title: l10n.mcpAddTitle | l10n.mcpEdit)`；
  - Body：`TpForm` + `TpFormField` 标准样式（label 走 `TpFormFieldLayout`，TextField 只负责输入，不复用 `InputDecoration.labelText`）。字段保留现有结构：
    - `id` — 必填；编辑模式禁用（key `mcp-id`）；
    - `name` — 必填（key `mcp-name`）；
    - 可展开 metadata 区（description / tags / homepage / docs）— 保留 `_metadataExpanded` 折叠交互；
    - server JSON `TpTextarea`（mono 字体）+ 「格式化 JSON」按钮 + 内联 `errorText`（JSON 非法 / 非对象 / 必填缺失提示）。
  - Footer：`TpDialogActions` 取消（`pop(false)`）/ 保存（保存中禁用 + 转圈）。
  - 保存流程 `_save()`：`formKey.validate()` → 构建 `McpServer`（沿用现有字段映射：`parseMcpTags`、`enabled/createdAt/updatedAt/source/importedFrom` 保留逻辑）→ `cubit.upsert(record)` → 成功 `Navigator.pop(true)`；失败在 dialog 内保留，AppToast 显示 `cubit.state.errorMessage`。
  - 复用现有 l10n key（`mcpForm*`、`mcpAddTitle`、`mcpEdit`、`cancel`、`save`），不新增文案。

### 2. 删除文件

- `client/lib/pages/mcp/mcp_form_nav_page.dart`（`McpFormNavPage`）；
- `client/lib/pages/mcp/mcp_form_page.dart`（`McpFormPage`，逻辑并入 dialog）。

### 3. 路由与收尾

- `client/lib/router/app_router.dart`：删除 `/mcp/add`、`/mcp/edit/:serverId` 两个 GoRoute 及 `mcp_form_nav_page.dart` import；
- `client/lib/pages/mcp/mcp_routes.dart`：删除 `mcpAddRoute()` / `mcpEditRoute()` / `mcpPathIsForm()`，保留 `mcpInstalledRoute`；
- `client/lib/router/android_shell_chrome.dart`：移除 `mcpPathIsForm` 分支（line 31、140-142）及 `mcp_routes.dart` import；
- `client/lib/pages/mcp/mcp_management_page.dart`：
  - `navigateMcpAdd` / `navigateMcpEdit` 替换为 `_openAdd(context)` / `_openEdit(context, server)`，内部调用 `showMcpEditorDialog`；
  - `onAdd` / `onEdit` 回调改为打开 dialog；
  - `_addFromListing`：已存在 → 打开该 server 的编辑 dialog；upsert 失败 → 打开 draft 的编辑 dialog（原 `navigateMcpEdit` 两处）。

### 4. 测试

- 新建 `client/test/pages/mcp/mcp_editor_dialog_test.dart`（仿照 `client/test/pages/hooks/hook_editor_dialog_test.dart`）：
  - 必填校验（id/name 为空不保存）；
  - 保存成功 → `upsert` 被调用且 dialog pop(true)；
  - 保存失败（repository 抛错）→ dialog 不关闭、显示错误。
- 更新 `client/test/router/android_shell_chrome_test.dart`：移除 `/mcp/add`、`/mcp/edit/server-1` 断言（line 34-35），改为断言 `/mcp/installed`、`/mcp/discovery` 等仍为库路径。

## 不做什么

- 不改 workspace / team-config 里 MCP 区块的「Manage」跳转（仍去 `/mcp/installed` 全局管理页）；
- 不做结构化 JSON 表单重构（type/command/url 分字段）；
- 不动 MCP 数据层（`McpCubit.upsert` / `McpRepository` / `McpCatalogService`）。

## 验收标准

1. 安装列表点「添加」弹出 dialog，不再跳整页；
2. 列表/发现条目点「编辑」弹出同 dialog 且 id 字段禁用；
3. 取消 / 保存成功均关闭 dialog；保存失败留在 dialog 并提示；
4. `/mcp/add`、`/mcp/edit/:serverId` 不再存在于路由表，Android chrome 无对应分支；
5. `flutter analyze` 无新增告警；新增 + 更新测试全绿。
