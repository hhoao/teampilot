# FlexColorScheme 主题重构设计

**日期**: 2026-05-13
**状态**: 待审阅
**作者**: 与 Claude 协作

## 背景与动机

当前 Flutter 客户端的主题分散在两个 `ThemeExtension` 中：

- [client/lib/theme/app_theme.dart](../../../client/lib/theme/app_theme.dart)（414 行）：定义 `AppColors`，含 57 个语义化颜色字段，明暗两份手写 hex 表。`lerp` 与 `copyWith` 都返回 `this`，切主题无过渡动画。`_buildTheme` 内手写了 FilledButton（药丸形）、OutlinedButton、IconButton、Switch、SegmentedButton、PopupMenu、Menu、InputDecoration 等组件主题。Material 3 `ColorScheme` 几乎没参与，应用层全部走 `AppColors.of(context).xxx` 取色。
- [client/lib/theme/app_workspace_settings_theme.dart](../../../client/lib/theme/app_workspace_settings_theme.dart)（278 行）：定义 `AppWorkspaceSettingsTokens`，含 ~20 个排版/间距/控件尺寸字段及若干 TextStyle 辅助方法。`copyWith`、`lerp` 模板代码占据大部分行数。实际只在 7 处被读取，约 18 次字段访问，每个值基本只用 1-3 次。

两个扩展都是过度抽象：颜色没有走 M3 角色，被语义化字段稀释成 57 份；尺寸 token 抽象成 `ThemeExtension` 对一组静态常量是不必要的样板。

本次重构无需考虑向后兼容（项目无现有用户）。

## 目标

- 引入 [flex_color_scheme](https://pub.dev/packages/flex_color_scheme) 生成 `ThemeData` 主体（组件主题由 `FlexSubThemesData` 统一产出，不再手写）
- **彻底删除** `AppColors` `ThemeExtension`，所有颜色调用站点改为读取 `Theme.of(context).colorScheme.xxx`
- **彻底删除** `AppWorkspaceSettingsTokens` `ThemeExtension`，TextStyle 辅助改用 M3 `textTheme`，数值 token 就地内联为私有 `const`
- 保留"近黑侧栏 + 蓝/绿 accent"的现有观感（primary `#5B8DEF`、secondary `#38CFA2`、darkIsTrueBlack）

## 非目标

- 不引入 ThemeMode 切换 UI（应用一直跟随系统 `ThemeMode.system`）
- 不改聊天工作区中的 Markdown / 代码块高亮配色（如属独立模块）
- 不改 `AppWorkspaceSettingsTokens` 之外的尺寸/排版常量
- 不调整任何业务逻辑

## 架构

### 1. 依赖

`client/pubspec.yaml` 在 `dependencies:` 段新增：

```yaml
flex_color_scheme: ^8.x   # 选用 pub.dev 最新稳定版
```

### 2. 新 `client/lib/theme/app_theme.dart`（~60 行）

```dart
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

const _primary   = Color(0xFF5B8DEF);
const _secondary = Color(0xFF38CFA2);
const _error     = Color(0xFFFF7A7A);

/// Logo 渐变独立于 ThemeMode，作为顶层 const 暴露。
const logoGradientStart = _primary;
const logoGradientEnd   = _secondary;

const _subThemes = FlexSubThemesData(
  defaultRadius: 10,
  filledButtonRadius: 999,
  outlinedButtonRadius: 999,
  elevatedButtonRadius: 999,
  inputDecoratorRadius: 8,
  inputDecoratorIsFilled: true,
  popupMenuRadius: 10,
  popupMenuElevation: 14,
  menuRadius: 10,
  segmentedButtonRadius: 10,
  switchSchemeColor: SchemeColor.primary,
);

ThemeData buildLightTheme() => FlexThemeData.light(
  colors: const FlexSchemeColor(
    primary: _primary,
    secondary: _secondary,
    error: _error,
    primaryContainer: _primary,
    secondaryContainer: _secondary,
  ),
  surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
  blendLevel: 7,
  subThemesData: _subThemes,
  useMaterial3: true,
);

ThemeData buildDarkTheme() => FlexThemeData.dark(
  colors: const FlexSchemeColor(
    primary: _primary,
    secondary: _secondary,
    error: _error,
    primaryContainer: _primary,
    secondaryContainer: _secondary,
  ),
  surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
  blendLevel: 10,
  darkIsTrueBlack: true,
  subThemesData: _subThemes,
  useMaterial3: true,
);
```

`main.dart` 的 `theme:` 与 `darkTheme:` 不需要修改（仍调用 `buildLightTheme()` / `buildDarkTheme()`）。

### 3. 删除文件

- 整个 [client/lib/theme/app_workspace_settings_theme.dart](../../../client/lib/theme/app_workspace_settings_theme.dart) 删除

## `AppColors` 字段 → M3 `ColorScheme` 映射

调用站点改为：

```dart
final cs = Theme.of(context).colorScheme;
```

| 旧字段 | 新写法 |
|---|---|
| `background` / `workspaceBackground` / `railBackground` | `cs.surface` |
| `surface` / `cardBackground` / `topbarBackground` / `sidebarBackground` / `teamSelectorBackground` | `cs.surfaceContainer` |
| `surfaceVariant` / `inputFill` / `unselectedBackground` / `unselectedMemberBg` / `readOnlyFieldBg` / `statBoxBg` / `assistantBubbleBackground` | `cs.surfaceContainerHigh` |
| `rightPanelBackground` | `cs.surfaceContainerLow` |
| `codeBackground` | `cs.surfaceContainerLowest` |
| `systemBubbleBackground` | `cs.surfaceContainerHighest` |
| `border` / `inputBorder` / `unselectedBorder` / `teamSelectorBorder` / `readOnlyFieldBorder` / `statBoxBorder` | `cs.outlineVariant` |
| `subtleBorder` / `tabBarDivider` | `cs.outlineVariant.withValues(alpha: 0.5)` |
| `inputBorderFocused` / `accentBlue` / `linkText` / `userBubbleBackground` | `cs.primary` |
| `accentBlueLight` | `cs.primaryContainer` |
| `accentGreen` | `cs.secondary` |
| `accentGreenLight` | `cs.secondaryContainer` |
| `selectedBackground` / `selectedBorder` / `railButtonSelectedBg` | `cs.primaryContainer` |
| `railButtonSelectedFg` | `cs.onPrimaryContainer` |
| `railButtonUnselectedBg` | `cs.surfaceContainerHigh` |
| `railButtonUnselectedFg` | `cs.onSurfaceVariant` |
| `selectedMemberBg` | `cs.secondaryContainer` |
| `typeBadgeApiBg` / `typeBadgeApiBorder` | `cs.primaryContainer` |
| `typeBadgeApiText` | `cs.onPrimaryContainer` |
| `typeBadgeAccountBg` / `typeBadgeAccountBorder` | `cs.secondaryContainer` |
| `typeBadgeAccountText` | `cs.onSecondaryContainer` |
| `warningBackground` / `warningBorder` / `statBoxWarnBorder` | `cs.tertiaryContainer` |
| `warningText` | `cs.onTertiaryContainer` |
| `successBackground` / `successBorder` | `cs.secondaryContainer` |
| `successText` | `cs.onSecondaryContainer` |
| `emptyMessageText` / `readOnlyFieldText` | `cs.onSurfaceVariant` |
| `logoGradientStart` / `logoGradientEnd` | 顶层 const，从 `package:flashskyai_client/theme/app_theme.dart` 导入 |

> M3 把"警告"角色归为 tertiary。FlexColorScheme 会自动生成与 primary/secondary 协调的 tertiary 容器色，无需手动指定 tertiary 种子。

## `AppWorkspaceSettingsTokens` → `textTheme` + 内联 `const`

### TextStyle 辅助 → M3 textTheme

调用站点取：

```dart
final tt = Theme.of(context).textTheme;
final cs = Theme.of(context).colorScheme;
```

| 旧 helper | 新写法 |
|---|---|
| `rowTitleStyle(onSurface)` | `tt.titleSmall` |
| `rowSubtitleStyle(onSurface)` | `tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)` |
| `groupHeaderStyle(onSurface)` | `tt.labelSmall?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.2)` |
| `workspaceHeadingTitleStyle(onSurface)` | `tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)` |
| `workspaceHeadingSubtitleStyle(onSurface)` | `tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.25)` |

若某处用 textTheme 还原后视觉不可接受，就地写 `const TextStyle(...)`，不再回归全局抽象。

### 数值 token → 调用文件顶部私有 const

| 旧 token | 新位置 |
|---|---|
| `settingRowPadding` / `settingGroupHeaderPadding` / `settingCardBorderRadius` / `titleSubtitleGap` / `labelTrailingGap` | [workspace_settings_widgets.dart](../../../client/lib/widgets/settings/workspace_settings_widgets.dart) 顶部 |
| `dropdownMinWidth` / `dropdownHorizontalPadding` / `dropdownBorderRadius` / `dropdownIconOpacity` / `dropdownLabelFontSize` | [flashskyai_dropdown_decoration.dart](../../../client/lib/widgets/dropdown/flashskyai_dropdown_decoration.dart) 顶部 |
| `segmentedIconSize` | [workspace_settings_toggle_strip.dart](../../../client/lib/widgets/settings/workspace_settings_toggle_strip.dart) 顶部 |
| `workspaceHeadingTitleSubtitleGap` | [config_workspace.dart](../../../client/lib/pages/config_workspace.dart) 内联 |

## 受影响的文件清单

**主题层（重写或删除）**：
- `client/lib/theme/app_theme.dart`：从 414 行重写为 ~60 行
- `client/lib/theme/app_workspace_settings_theme.dart`：删除
- `client/pubspec.yaml`：新增 `flex_color_scheme` 依赖

**颜色调用站点（13 个文件）**——把 `AppColors.of(context).xxx` 替换为 `Theme.of(context).colorScheme.xxx`：
- `client/lib/pages/chat_workbench.dart`
- `client/lib/pages/workspace_shell.dart`
- `client/lib/pages/skill_management_page.dart`
- `client/lib/pages/team_config_page.dart`
- `client/lib/pages/llm_config_workspace.dart`
- `client/lib/pages/config_workspace.dart`
- `client/lib/widgets/context_sidebar.dart`
- `client/lib/widgets/right_tools_panel.dart`
- `client/lib/widgets/settings/workspace_settings_toggle_strip.dart`
- `client/lib/widgets/settings/workspace_settings_widgets.dart`
- `client/lib/widgets/dropdown/flashskyai_dropdown_decoration.dart`

**Token 调用站点（与颜色站点有重叠）**——移除 `tokens = ...` 行，替换字段读取：
- `client/lib/widgets/settings/workspace_settings_toggle_strip.dart`
- `client/lib/widgets/settings/workspace_settings_widgets.dart`
- `client/lib/widgets/dropdown/flashskyai_dropdown_decoration.dart`
- `client/lib/pages/config_workspace.dart`

合计去重后受影响 **11 个 Dart 文件（颜色与 token 调用站点完全重叠或并集）+ 主题模块 2 个文件 + 1 个 pubspec**。

## 验证

- `cd client && flutter pub get` 成功拉取 flex_color_scheme
- `cd client && flutter analyze` 零错误
- `cd client && flutter build linux --debug` 通过
- 启动应用目视检查：
  - 明暗主题随系统切换不崩
  - 侧栏（context_sidebar）背景仍偏黑
  - 配置工作区（config / team / llm / skill）的卡片、行、分组头排版合理
  - 聊天工作区（chat_workbench）用户气泡、助手气泡、代码块底色可读
  - 下拉菜单（custom_dropdown）弹层背景、边框、阴影正常
  - 按钮仍为药丸形

## 风险

- **M3 容器色与现有近黑底色对比度**：`darkIsTrueBlack: true` 会让 surface 接近 `#000000`，`surfaceContainerHigh` 与之差距足够；但 `surfaceContainer`、`surfaceContainerLow` 的层级在真黑模式下可能偏暗，需在目视检查阶段决定是否上调 `blendLevel`。
- **tertiary 容器色未必"暖黄"**：M3 默认 tertiary 由 primary 算术派生，不一定是现有的橙黄警告色。如发现 `warningText/Bg` 视觉上不再像"警告"，在 `FlexSchemeColor` 显式指定 `tertiary: const Color(0xFFFBBF24)`。
- **textTheme 字号不完全等同**：M3 `titleSmall` 默认 14px，原 `rowTitleFontSize` 是 13px。若视觉上差异明显，就在 widget 内 `copyWith(fontSize: 13)` 局部修正，而不是回头再造全局 token。

## 不做的事（重申）

- 不引入主题切换 UI
- 不修改 chat 模块的代码高亮配色
- 不改业务逻辑、不调整 layout、不重命名字段以外的内容
- 不改 `AppWorkspaceSettingsTokens` 之外的常量来源
