# Workspace Hub 布局统一：Section Shell 抽取

**状态：** 已批准（brainstorming，方案 B）  
**日期：** 2026-05-29  
**范围：** Settings、团队配置、Skills、Plugins、MCP 五个 master-detail workspace 页面；`client/lib/widgets/settings/` 新增共享 shell；各 page 迁移至统一 API。

## 目标

1. **减少重复：** 消除 5 个页面中重复的桌面端壳子代码（`Container` + `WorkspaceHubTitleBar` + `WorkspaceSplitShell`）及 Android/desktop 分支。
2. **统一交互：** section 切换路由（Android `push` / 桌面 `go`）、body 切换动画、`nav` 入场动画、sidebar 样式全部一致。
3. **通用 Section 协议：** 固定 enum section 与团队配置动态成员 nav 共用同一套 shell 体系；各 workspace enum 实现统一 descriptor 接口。

## 非目标

- `llm_config_workspace.dart` 内嵌 provider 编辑流的 Android/desktop 分支。
- MCP add/edit form 页（`mcp_form_nav_page.dart`）。
- SSH profiles 独立页。
- 修改 GoRouter 路由路径定义（路径保持不变，只统一导航调用方式）。
- Hub 入口页（Android landing）的进一步抽象（可选 follow-up，优先级低于 section 页）。

## 背景

`workspace_hub_shell.dart` 已提供底层 primitives：

| 组件 | 作用 |
|------|------|
| `WorkspaceHubTitleBar` | 顶部标题 + 副标题 |
| `WorkspaceHubNavList` / `WorkspaceHubEntry` | 左侧导航项 |
| `WorkspaceSplitShell` | 桌面左 nav + 右 body 分栏 |
| `WorkspaceHubPage` | Android 入口列表页 |
| `WorkspaceSectionPage` | Android 详情页容器 |

各 workspace 页面仍重复组装桌面壳子，且存在行为/样式不一致：

- Config nav 有 `animateEntries: true`，Skills/Plugins 无。
- MCP 单独实现 `McpWorkspaceShell`（与通用模式相同）。
- 团队配置使用私有 `_NavItem` / `_MemberNavSubItem`，与 `WorkspaceHubNavItem` 样式重复。
- section 导航 helper 仅 MCP 有（`navigateMcpSection`），其余页面各自写 `go`/`push` 分支。

## 已锁定决策

| 决策 | 说明 |
|------|------|
| **方案 B** | 壳子 + Section 协议 + Nav 构建器；不过度抽象为声明式 Workspace 框架 |
| **固定 + 动态 nav** | `WorkspaceEnumNavPanel` 覆盖 enum section；`WorkspaceCompositeNavPanel` 覆盖团队配置成员列表 |
| **Config 例外** | Settings sidebar entries ≠ hub entries 全集（sidebar 无 SSH profiles），继续手动维护 entries，不强制 `EnumNavPanel` |
| **nav 动画** | 全部 workspace sidebar 统一 `animateEntries: true` |
| **nav 密度** | 扩展 `WorkspaceHubNavItem` 支持 `standard` / `relaxed` / `subItem`，删除 team_config 私有 nav item |

## 架构

### 分层

```text
workspace_hub_shell.dart           # 保留现有 primitives
workspace_section_navigation.dart  # navigateWorkspaceRoute + WorkspaceSectionDescriptor
workspace_section_host.dart        # DesktopShell + AdaptiveSectionPage + EnumNavPanel + CompositeNavPanel
```

各 page 仅保留：**enum + descriptor 实现 + body widget + hub 入口**。

### 数据流

```text
WorkspaceXxxPage
  → body = switch(section) { ... }
  → WorkspaceAdaptiveSectionPage(
       nav: WorkspaceEnumNavPanel / WorkspaceCompositeNavPanel / manual NavList,
       body: body,
     )
  → useAndroidHubNavigation?
       true  → WorkspaceSectionPage
       false → WorkspaceHubDesktopShell (TitleBar + SplitShell)
```

### 新增 API

#### `navigateWorkspaceRoute`

```dart
void navigateWorkspaceRoute(BuildContext context, String path);
// Android → context.push(path)
// Desktop → context.go(path)
```

MCP 现有 `navigateMcpSection` / `navigateMcpAdd` / `navigateMcpEdit` 委托至此 helper（保留原函数名作为 thin wrapper 以避免大范围 import 改动）。

#### `WorkspaceSectionDescriptor`

```dart
abstract interface class WorkspaceSectionDescriptor {
  String get routeSegment;
  String routePath(String basePath);
  String title(AppLocalizations l10n);
  IconData get icon;
}
```

各 workspace enum 通过 extension 实现。`TeamConfigSection.members` 的 `routePath` 接受可选 `memberId`（在 page 层 resolve，shell 不处理 fallback）。

#### `WorkspaceHubDesktopShell`

合并 TitleBar + SplitShell，替代 5 处重复 `Container` + `Column` 及 `McpWorkspaceShell`。

参数：`title`, `subtitle`, `nav`, `body`, `bodyAnimationKey`, 可选 `pageKey`。

#### `WorkspaceAdaptiveSectionPage`

自动 Android/desktop 分支：

- Android → `WorkspaceSectionPage(pageKey, child: body)`
- Desktop → `WorkspaceHubDesktopShell(...)`

#### `WorkspaceEnumNavPanel<S extends Enum>`

从 enum 列表生成 `WorkspaceHubNavList(sidebarStyle: true, animateEntries: true)`。用于 Skills、Plugins、MCP。

#### `WorkspaceCompositeNavPanel`

固定 primary entries + 可滚动 footer（团队配置成员列表）：

```text
Column
├── WorkspaceHubNavList (primary, non-scrollable)
└── Expanded → ListView (member sub-items + add tile)
```

### `WorkspaceHubNavItem` 密度扩展

| density | 高度 | icon | 用途 |
|---------|------|------|------|
| `standard` | 48 | 18 | 默认 sidebar（现有行为） |
| `relaxed` | 54 | 21 | 团队配置主 section |
| `subItem` | 44 | 19 | 成员子项，左缩进 14px |

## 统一行为规范

| 行为 | 统一后 |
|------|--------|
| 桌面 section 切换 | `navigateWorkspaceRoute` → `context.go` |
| Android section 切换 | `navigateWorkspaceRoute` → `context.push` |
| body 切换动画 | `bodyAnimationKey: ValueKey('…-body-${section…}')` |
| nav 入场动画 | 全部 `animateEntries: true` |
| nav 样式 | 全部 `WorkspaceHubNavItem`；删除 `_NavItem` / `_MemberNavSubItem` |
| 背景色 / padding | shell 统一管理 |

## 迁移范围

| 文件 | 改动 |
|------|------|
| `workspace_section_navigation.dart` | 新建 |
| `workspace_section_host.dart` | 新建 |
| `workspace_hub_shell.dart` | 扩展 `WorkspaceHubNavItem` density |
| `config_workspace.dart` | `WorkspaceAdaptiveSectionPage`；删 `_DesktopConfigWorkspace` 壳子；`_ConfigNavPanel` 保留手动 entries |
| `team_config_page.dart` | `WorkspaceCompositeNavPanel`；删 `_NavItem` / `_MemberNavSubItem` |
| `skill_management_page.dart` | `AdaptiveSectionPage` + `EnumNavPanel` |
| `plugin_management_page.dart` | 同上 |
| `mcp_management_page.dart` | 删 `McpWorkspaceShell`；navigation helper 委托 `navigateWorkspaceRoute` |

## 团队配置 Nav 迁移

1. 主 section（team/skills/plugins/mcp/members）→ `WorkspaceCompositeNavPanel` primary entries，density `relaxed`。
2. 成员列表 → footer `ListView`，density `subItem`。
3. `TeamConfigSection` extension 实现 `WorkspaceSectionDescriptor`；members 路由带 `memberId`，page 层沿用 `_memberRouteId` resolve 逻辑。
4. Android Hub 页动态成员 entries 保持现有行为（hub 展开成员列表）。

## 错误处理

- Shell 层无新错误路径；loading/error 仍由各 page body 负责。
- `navigateWorkspaceRoute` 不包 try/catch；GoRouter redirect 兜底。
- TeamConfig members section 无有效 memberId 时，page 层 resolve 至首个成员或 null，不在 shell 层处理。

## 测试

| 类型 | 内容 |
|------|------|
| Widget test | `WorkspaceAdaptiveSectionPage` 在 Android flag 下渲染 `WorkspaceSectionPage` vs `WorkspaceHubDesktopShell` |
| Widget test | `WorkspaceEnumNavPanel` 选中态与 onTap |
| 回归 | `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` |
| 手动 | 5 个 workspace 桌面 section 切换；Android hub→detail；团队配置成员增删选 |

## 预期收益

- 删除 ~150 行重复壳子（5 页 × ~30 行）+ `McpWorkspaceShell` + team_config 私有 nav item（~80 行）。
- 新增共享代码 ~120 行，净减少 ~110 行。
- 后续改 padding/动画/路由策略只改 1 处。

## 后续可选

- `WorkspaceEnumHubPage` helper 统一 Android hub 入口页生成。
- 将 Config section enum 与 hub/sidebar entries 差异文档化或收敛为显式 `visibleInSidebar` 标志。
