# 已安装 Skill：查看 SKILL.md

- 日期：2026-09-21
- 状态：已批准
- 来源：已安装 skills 管理页需要在应用内阅读 skill 正文。现有「详情」只在有 GitHub 地址时打开浏览器；本地/导入 skill 没有入口，列表也只显示一行截断描述。

## 目标

已安装列表每一行提供「查看」。点击后，已安装栏换成只读详情页，渲染该 skill 的 `SKILL.md`。独立 `/skills` 路由和首页嵌入的 skills 管理页行为一致。

## 非目标

- 不新增 go_router 路径（skill id 常含 `/`；首页嵌入不走 `/skills/installed`）。
- 不编辑、不卸载、不在详情页切换源码/预览。
- 不解析 skill 目录内的相对图片；不把正文写入 `SkillState`。
- 不改发现页、注册源、团队配置 skills 行、catalog `read_skill` MCP 工具。
- 不替换或移除现有 GitHub「详情」按钮。

## 架构

选中哪个 skill 是已安装栏的页面状态。`SkillCubit` 只提供读文件的薄封装，不持有详情导航。

```text
SkillInstalledRow  查看
        │
        ▼
SkillInstalledSection._viewing = skill
        │
        ▼
SkillDetailView
        │
        ▼
SkillCubit.readSkillMarkdown(skill)
        │
        ▼
SkillRepository.readSkillMarkdown
  <skillsDir>/<skill.directory>/SKILL.md
        │
        ▼
compileMarkdown + MarkdownView（tp_markdown）
```

读路径与 catalog `read_skill` 相同：`SkillManifestService.resolveSkillsDir()` + `skill.directory` + `SKILL.md`。通过已注入的 `Filesystem`，不用 `Directory.current`。

## 组件

| 单元 | 职责 | 依赖 |
|------|------|------|
| `SkillRepository.readSkillMarkdown` | 读 `SKILL.md`；文件不存在返回 `null`；其它 IO 错误抛出 | `manifest` + `Filesystem` |
| `SkillCubit.readSkillMarkdown` | 转调 repository；不 `emit` 选中态或正文 | repository |
| `SkillInstalledSection` | Stateful：`_viewing == null` 显示列表，否则显示详情；切走 Installed 即销毁，回到列表 | cubit / 行 / 详情 |
| `SkillInstalledRow` | 查看图标按钮 | `onView` |
| `SkillDetailView` | 返回栏 + 加载/空/错/正文 | skill + 读 Future |

`SkillManagementPage` 和 `HomeGlobalSection` 不增加 skillId 状态。切到发现/注册源会卸掉已安装栏，详情自然关闭。

## UI

**列表行**

- 在 GitHub「详情」左侧加 `IconButton`：`Icons.visibility_outlined`，tooltip `skillsCardView`。
- 现有 GitHub「详情」、开关、更新、卸载不变。
- 窄屏（现有 `< 420`）仍折行；查看是图标，不新增文字按钮。

**详情页（替换已安装卡片，含头栏工具条）**

- 顶栏：返回（`l10n.back` + `Icons.arrow_back_rounded`）+ skill 名称（一行省略）。
- 加载：正文区居中进度。
- 成功：滚动渲染完整 `SKILL.md`（含 YAML frontmatter）。tokens 用 `buildAppMarkdownTokens`（`MarkdownProfile.document`）。
- `http(s)` 链接：系统浏览器（现有 `launchUrl`）。相对链接/图片：不解析，走 markdown 默认占位。
- 缺文件：空状态，可返回。
- 读失败：l10n 错误文案，可返回。

不在详情页放卸载、更新、GitHub、启用开关。

## 数据与生命周期

| 事件 | 行为 |
|------|------|
| 点查看 | `_viewing = skill`，详情页开始读文件 |
| 点返回 | `_viewing = null`，回到列表 |
| 切到发现/注册源 | 已安装栏 dispose，详情关闭 |
| 再回到已安装 | 显示列表，不恢复上次详情 |
| 查看期间该 skill 从 `state.installed` 消失 | `_viewing = null`，回到列表 |
| 打开详情 | 读一次；不监视文件变化 |

`readSkillMarkdown` 返回 `Future<String?>`：正文或 `null`（缺文件）。非 not-found 的 IO 错误向上抛，详情页捕成读失败状态。不把正文放进 `SkillState`。

## 错误

| 情况 | UI |
|------|----|
| 缺 `SKILL.md` | 空状态 `skillsDetailMissing` |
| 其它读失败 | `skillsDetailReadError`；`AppLogger.w` 记诊断 |
| skill 在查看时被卸载 | 回列表，不 toast |

不因打开详情而 `emit` 全局 `errorMessage`。

## l10n

只改 `app_en.arb` / `app_zh.arb`。返回用已有 `back`。

| 键 | en | zh |
|----|----|----|
| `skillsCardView` | View | 查看 |
| `skillsDetailMissing` | No SKILL.md found for this skill. | 未找到该 skill 的 SKILL.md。 |
| `skillsDetailReadError` | Could not read SKILL.md. | 无法读取 SKILL.md。 |

## 测试

**`skill_repository`（或新 `skill_repository_read_markdown_test.dart`）**

- 有 `SKILL.md` → 返回全文
- 目录在、文件不在 → `null`
- 通过注入 `Filesystem`，不碰真实 home

**Widget**

- 点查看：列表换成详情，标题为 skill 名
- 点返回：回到列表
- 缺文件：空状态文案
- 已安装行在 320px 宽仍不溢出（扩展现有 overflow 测，覆盖查看按钮）

Cubit 不测选中态（不在 `SkillState`）。`readSkillMarkdown` 若只是转调，不必单独 cubit 测。

## 验收

1. 已安装行有「查看」；点开后看到该 skill 的 `SKILL.md` 渲染正文。
2. 返回回到列表；切走 Installed 再回来也是列表。
3. 无 GitHub 地址的本地 skill 也能查看。
4. 有 GitHub 的 skill：列表上「详情」仍打开浏览器。
5. 缺 `SKILL.md` 时详情可返回，不崩溃。
6. 手机宽度列表行不溢出。
