# 标题栏项目 Tab 个人/团队区分 — 设计

- 日期: 2026-06-07
- 状态: 已批准设计,待实现

## 问题

用户同时打开个人项目与团队项目的标题栏 tab 时,两者外观完全一致(`description` 图标 + 项目名),无法快速感知项目类型,影响切换时的认知负担。

**不在本版范围:** 多个团队间同名项目的区分(痛点 C);最近关闭菜单的视觉同步。

## 目标

- 标题栏 tab 在极简前提下,让用户**扫视即可区分**个人 vs 团队项目。
- 保持 tab 宽度与信息密度,不增加文字标签,不干扰专注。
- 非激活 tab 弱化色条,避免视觉噪音。

## 已确认的交互决策

| 维度 | 选择 |
|------|------|
| 主要痛点 | 个人 + 团队 tab 混在一起难以区分 |
| 区分信号 | 左侧 2px 色条 |
| 显示策略 | 始终显示色条;非激活 tab 降低色条透明度 |
| 辅助信息 | Tooltip 补充类型/团队名(方案 2) |
| 范围 | 仅标题栏 `_ProjectTab`;不动最近关闭菜单与首页卡片 |

## 方案(已选: 色条 + Tooltip)

在现有 `_ProjectTab` 左侧加入 2px 类型色条,保留 `Icons.description_outlined` 与项目名。色条编码项目类型;图标仍表示「项目 tab」。

### 色彩语义(与首页 sidebar 一致)

| 类型 | 判定 | 色条颜色 |
|------|------|----------|
| 个人 | `AppProject.teamId.isEmpty` | `colorScheme.primary` |
| 团队 | `teamId.isNotEmpty` | `colorScheme.tertiary` |

### 色条透明度

| Tab 状态 | 色条 alpha |
|----------|------------|
| 激活 (`active == true`) | 1.0 |
| 非激活 | 0.4 |
| 非激活 + hover | 0.7 |

Tab 背景、文字、图标逻辑保持现状;仅色条随状态变化。

### 布局

```
┌─┬──────────────────────┐
│█│ 📄  my-project    × │  激活:色条 100%,背景 surfaceContainerHigh
└─┴──────────────────────┘
 ┬ 2px

┌─┬──────────────────────┐
│░│ 📄  team-app       × │  非激活:色条 ~40% alpha
└─┴──────────────────────┘
```

- 色条在 tab 圆角(`8`)容器内侧左侧,高度与内容区对齐(上下可留 `4px` margin 以贴合圆角)。
- 不增加 tab 外显宽度:在现有 `padding` 内安置色条,必要时将 `left padding` 从 `12` 微调为 `10`。
- 色条与内容之间保留 `6–8px` 间距。

### Tooltip(方案 2)

在 `HomeWorkspaceShell._projectTabTooltip` 组装,团队名从 `TeamCubit` 按 `project.teamId` 解析。

| 类型 | 格式 | 示例 |
|------|------|------|
| 个人 | `{kindLabel} · {name}` + 可选第二行 `{path}` | `个人 · flashskyai-ui` |
| 团队 | `{teamName} · {name}` + 可选第二行 `{path}` | `My Team · flashskyai-ui` |

- `path` 规则与现有一致:空、或与 `name` 相同时不显示第二行。
- 团队 id 无法解析到名称时,回退为 `teamId` 或省略团队前缀(仅显示项目名 + path),不阻塞 tab 渲染。

### l10n

新增简短类型标签(不复用 `homeWorkspacePersonal`「个人工作区」,过长):

| Key | en | zh |
|-----|----|----|
| `homeWorkspaceProjectTabKindPersonal` | Personal | 个人 |

团队 tooltip 直接使用 `TeamConfig.name`,无需新 key。

## 数据流

### 模型

`HomeProjectTab` 新增:

```dart
enum HomeProjectTabKind { personal, team }

final HomeProjectTabKind kind;
```

### 构建

`HomeWorkspaceShell.build` 中:

```dart
kind: p.teamId.isEmpty
    ? HomeProjectTabKind.personal
    : HomeProjectTabKind.team,
```

`_ProjectTab` 新增 `kind` 参数,根据 `kind` + `active` + `_hovered` 计算 `barColor` 与 `barAlpha`。

### 文件改动

| 文件 | 改动 |
|------|------|
| `client/lib/pages/home_workspace/home_workspace_title_bar.dart` | `HomeProjectTabKind`、`HomeProjectTab.kind`、`_ProjectTab` 色条 UI |
| `client/lib/pages/home_workspace/home_workspace_shell.dart` | 传入 `kind`;扩展 `_projectTabTooltip` |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | `homeWorkspaceProjectTabKindPersonal` |
| `client/test/pages/home_workspace/home_workspace_title_bar_test.dart` | 新建或扩展 widget test |

## 不变

- Tab 开关、固定个人项目、跨团队 tab 列表、团队切换逻辑。
- 最近关闭溢出菜单项外观。
- 首页 `HomeWorkspaceProjectCard` 与 `ProjectIcon`。

## 被否决的备选

- **仅 Tooltip,无色条:** 需 hover 才可知类型,不满足扫视区分。
- **情境显示(仅混合打开时显示色条):** 用户选择始终显示 + 非激活降透明度,以形成稳定肌肉记忆。
- **文字标签(`个人` / 团队缩写):** 增加 tab 宽度与噪音。
- **替换 document 图标为 person/groups:** 与色条冗余;色条已足够且更省空间。
- **最近关闭菜单同步色条:** 首版范围外,收益低于标题栏 tab。

## 验证

- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- `cd client && flutter test --exclude-tags integration`
- Widget test:`personal` tab 使用 `primary` 色条;`team` tab 使用 `tertiary`;非激活色条 alpha 低于激活。
- 手动 golden-path:
  - 同时打开内置个人项目 + 至少一个团队项目 tab,扫视可区分;
  - 切换激活 tab,色条透明度随状态变化;
  - 暗色 / 亮色主题下色条对比度可读;
  - hover 非激活 tab,色条加深;tooltip 显示正确类型/团队名。
