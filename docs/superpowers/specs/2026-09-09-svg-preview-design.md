# SVG Preview Design

Date: 2026-09-09
Status: Approved (brainstorming)

## Problem

SVG 文件在工作台里只能以纯文本形式打开（`kEditorTextExtensions` 包含 `svg`），
没有渲染预览。用户查看 SVG 图标/图形时看到的是 XML 源码。

`flutter_svg: ^2.3.0` 已是依赖（图标系统在用），无需新增包。

## Goals

- 打开 SVG 文件默认显示**渲染预览**，带缩放/平移（对齐位图预览的交互）。
- 工具栏可切换到源码编辑（Edit|Preview），编辑能力（dirty、save、只读）完整保留。
- 本地 PTY 与 SSH/WSL 工作区都能预览（走工作区文件系统）。

## Non-Goals

- 不持久化视图偏好（会话内记忆，与 HTML Edit|Preview 一致）。
- 不改 compose 附件缩略图、markdown 内嵌 SVG 渲染（`markdown_network_image` 已有处理）。
- 不改位图预览行为。
- 不做实时渲染编辑缓冲区（预览读磁盘字节，保存后才刷新——已确认的需求）。

## Decisions

- **交互模式**：默认渲染预览 + Edit 切换（用户选定）。
- **预览数据源**：磁盘字节，未保存的编辑不反映到预览（用户选定）。
- **架构（方案 A，用户选定）**：SVG 走现有**文本管线**——`svg` 保留在
  `kEditorTextExtensions`，打开 tab 照旧加载文本、建 controller；预览面板是
  独立组件自行读磁盘字节（同 `HtmlPreviewPane` 自建 session 读 fs 的先例）。
  不选方案 B（`svg` 加入 `kEditorImageExtensions` + EditorCubit 懒加载文本 +
  字节缓存失效），因为那需要改 cubit 的加载/缓存/promote 逻辑，风险高收益低。

## Architecture

### 路由

- `client/lib/services/editor/file_editor_theme.dart`：
  - `svg` **保留**在 `kEditorTextExtensions`（`isImagePreviewPath` 对 svg 仍为
    false——compose 缩略图、markdown 链接路由等消费方零影响）。
  - 新增 `kSvgPreviewExtensions = {'svg'}` 与 `isSvgPreviewPath(path)`
    （扩展名大小写不敏感）。
- `client/lib/pages/workbench/file_editor_surface.dart`：在 HTML 分支旁新增
  svg 分支：`ListenableBuilder(svgViewModes)` → preview 模式渲染
  `SvgPreviewPane`，edit 模式渲染现有 `_CodeEditorPane`。
- 数据流：tab 打开走文本管线（2MiB 上限 `kEditorMaxFileBytes` 适用）；
  预览字节由 pane 通过 `EditorCubit.filesystemFor(workspaceId, path)` 读取，
  SSH/WSL 工作区自动走远程 fs。

### 模式存储与工具栏

- 新增 `client/lib/services/editor/svg_view_mode_store.dart`：
  `enum SvgViewMode { preview, edit }`，镜像 `HtmlViewModeStore`，**默认
  `preview`**，会话内记忆、不持久化。挂到 `WorkbenchEditorOpener.svgViewModes`，
  随 opener dispose。
- `HtmlViewModeToggle` 泛化为通用双段 Edit|Preview 切换组件（接受 mode 值 +
  回调，不再绑死 `HtmlViewMode`），HTML 处与 SVG 处共用。l10n 复用现有
  `htmlViewToggleEdit` / `htmlViewTogglePreview` 字符串（如需改名保持两处
  arb 同步）。
- preview 模式工具栏 = 位图预览同款（文件名 + 缩放 −/%/+ / fit）+ Edit|Preview
  切换；edit 模式工具栏追加同一切换组件。

### 渲染与缩放语义

- 新增 `client/lib/pages/workbench/svg_preview_pane.dart`：
  - 加载时用 `flutter_svg` 的 `SvgBytesLoader` + `vg.loadPicture` 解析出**自然
    尺寸**（声明 width/height，否则 viewBox，否则库默认），然后
    `PhotoView.customChild(child: SvgPicture.memory(bytes), childSize: 自然尺寸)`。
  - 缩放对齐位图预览：初始 contained 适配、打开/重置时钳制不超过 1:1（1:1 =
    自然尺寸的逻辑像素）、min 0.25 / max 8.0、滚轮缩放、工具栏百分比显示。
  - 缩放控制逻辑从 `FileEditorImagePreview` 提取成共享 mixin，两处复用。
  - 自然尺寸解析失败（畸形 SVG）→ 降级为无 childSize 的 fit 渲染（百分比退化为
    相对 fit 基准）。

### 刷新与错误处理

- **保存后刷新**：pane 监听 EditorCubit，`bucket.isDirty(path)` true→false
  （保存完成）时重读磁盘字节重渲染。
- 读失败（fs 错误）→ 居中错误文案（l10n，`couldNotRead` 语义）。
- SVG 解析失败 → `SvgPicture.errorBuilder` 显示错误文案，并调
  `reportImageDecodeFailed`（与位图解码失败同款 snackbar）。
- 加载中 → 与位图预览相同的 spinner。

## Testing

- `file_editor_theme_image_test`：新增 `isSvgPreviewPath` 用例；确认 svg 仍走
  文本、`isImagePreviewPath` 断言不变。
- `svg_view_mode_store_test`：默认 preview、setMode 会话内记忆。
- `SvgPreviewPane` widget 测试（fake Filesystem，遵循仓库测试 fake 约定）：
  正常渲染、非法 SVG 报错、保存（dirty→false）后重读、Edit 切换到代码编辑器。
- `FileEditorSurface` 测试：svg 路径默认显示预览，切换后显示编辑器。
- 收尾跑一次全量套件（`cd client && dart run tool/run_tests.dart`）。
