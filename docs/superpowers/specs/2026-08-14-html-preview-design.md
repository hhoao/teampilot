# 设计:HTML 文件预览(编辑器切换 + 浮动工作区内嵌)

日期:2026-08-14
状态:已评审待实现

## 背景与目标

用户在 teampilot 中编辑 `.html` 文件时只能看源代码,无法查看渲染结果。参考 orca(Electron)的 HTML 预览:编辑 tab 标题栏提供"Open Preview to the Side",在右侧分屏用浏览器引擎渲染 `file://` 地址。

### 需求决策(已与用户确认)

1. **形态**:`.html` 编辑 tab 内提供 **Edit | Preview 切换**(复用 `FileDiffSurfaceToggle` / `MarkdownViewModeToggle` 的 segment pill 模式);同时**浮动工作区**内嵌预览 tab 作为主入口。
2. **实时性**:预览渲染磁盘上的文件,**保存(Ctrl+S)后自动刷新**。
3. **SSH 支持**:本地(native/WSL)与 SSH 远程工作区**都支持**预览。webview 引擎无法访问 sftp 文件,必须通过本地 HTTP 代理服务器(`AppStorage.fs` 抽象)统一提供内容。

### 平台与引擎约束(已调研)

| 包 | Android | macOS | Windows | Linux | 说明 |
|---|---|---|---|---|---|
| `webview_flutter`(官方) | ✅ | ✅ | ❌ | ❌ | API 稳定,桌面两平台缺席 |
| `flutter_inappwebview` 6.x | ✅ | ✅ | ✅ | ❌ | 6.x 已移除 Linux 支持 |
| `desktop_webview_window`(mixin.dev) | ❌ | ✅ | ✅ | ✅ | **独立窗口**,无法内嵌 Flutter widget 树 |
| `webview_win_floating` | ❌ | ❌ | ✅ | ✅ | 实现官方 `webview_flutter` platform interface,内嵌 widget |

**结论**:
- **内嵌预览(核心)**:`webview_flutter` 官方 API,Android/macOS 用官方实现,Linux/Windows 由 `webview_win_floating` 补位。所有平台代码统一使用 `WebViewController` / `WebViewWidget`,平台差异被 platform interface 吸收。
- **独立窗口(补充)**:预览 tab 提供"在独立窗口打开"按钮,桌面三平台用 `desktop_webview_window`。
- Linux 桌面需要系统库 `libwebkit2gtk-4.1`;启动时检测引擎可用性,不可用时降级为"在系统浏览器打开"(`url_launcher` 已有)。

## Section 1:HtmlPreviewServer(内容服务层)

新建 `client/lib/services/preview/html_preview_server.dart`。

### 职责

- 用 `dart:io` `HttpServer` 绑定 `InternetAddress.loopbackIPv4` + 端口 0(随机端口),为预览提供文件内容。
- 通过 `AppStorage.fs`(LocalFilesystem / WslFilesystem / SftpFilesystem 抽象)读取文件 → **本地与 SSH 远程统一**。
- 挂载范围:**HTML 文件所在目录**(挂载根)。URL 路径为相对路径,相对资源(CSS/JS/图片)按 URL 解析;相对资源跳转 `<a href="other.html">` 也按相对路径解析。

### 接口

```
HtmlPreviewServer:
  Future<HtmlPreviewMount> mount({required Filesystem fs, required String htmlDirectory})
    → 返回 { port, baseUrl, mountId }
  Future<void> unmount(mountId)
  bool isServing(mountId)
```

### 路由与安全

| 路由 | 处理 |
|---|---|
| `GET /` | 重定向到 `/<html 文件名>`(预览入口) |
| `GET /<相对路径>` | 解析并挂载根内文件,按扩展名返回 MIME(text/html, text/css, text/javascript, image/*, ...);读取失败返回 404 |
| 其余 | 404 |

- **路径穿越防护**:规范化(用 `p.Context()` 的 normalize)后必须仍在挂载根内(`isWithin`),否则 404。**禁止越出挂载根读取**,防任意文件访问。
- 仅监听 loopback,不对外网暴露。
- 大文件流式读取(HTTP 响应流),不整文件载入内存。

### 生命周期

- 引用计数:同一个挂载目录可被多个预览 tab 共享(同 workspace 多个 html 文件同目录时复用同一挂载)。
- 无引用时关闭端口(防端口泄漏)。
- SSH 断开时读取失败 → 404 → UI 显示错误态。

### MIME 类型

内置小表映射(html/css/js/json/svg/png/jpg/gif/webp/ico/woff2/mp3/mp4 等),未知扩展名按 `application/octet-stream` 或禁止(默认禁止,仅白名单)。

## Section 2:内嵌 WebView widget(TpHtmlPreviewView)

新建 `client/lib/pages/preview/html_preview_pane.dart`(页面层)+ `client/lib/services/preview/`(逻辑层)。

### 结构

- 逻辑:`HtmlPreviewSession`(service)——持有 `HtmlPreviewServer` mount 引用 + `WebViewController`;提供 `reload()`、`loadUrl`、`dispose`;保存事件由编辑器层驱动 reload。
- Widget:`HtmlPreviewPane`——包裹 `WebViewWidget(controller)`,渲染 webview 平台实现(Android/macOS 官方、Linux/Windows 由 `webview_win_floating` 提供)。加载失败/引擎不可用时显示错误态(错误图标 + 文案 + "在系统浏览器打开"按钮)。

### 依赖接入

- `client/pubspec.yaml` 新增:
  - `webview_flutter: ^4.x`(官方 API)
  - `webview_win_floating: ^3.x`(仅 Linux/Windows 生效,实现官方 platform interface;声明为直接依赖,与 webview_flutter 并行)
  - `desktop_webview_window: ^0.3.x`(独立窗口补充)
- 检查 `docs/flutter-patches.md` / `docs/DEVELOPMENT.md`:如有 Linux runner 系统库打包/文档需要,同步更新。

### 平台注意

- Linux 运行时依赖 `libwebkit2gtk-4.1-0`;启动时(或首次预览时)探测引擎可用性,失败走降级路径。
- Windows 依赖 WebView2 Runtime(Windows 11 自带,Win10 需分发运行时)——文档记录即可,v1 以 Linux 为主要验证平台。

## Section 3:编辑器集成(Edit | Preview 切换)

### 模式存储

新建 `client/lib/services/editor/html_view_mode_store.dart`:

- `enum HtmlViewMode { edit, preview }`
- `HtmlViewModeStore`(ChangeNotifier):per-path 模式,`modeFor(path)` / `setMode(path, mode)`;**默认 `edit`**(打开 html 先看源码,用户主动切预览,与 markdown 默认 preview 相反);仿 `MarkdownViewModeStore`(markdown_view_mode_store.dart)的结构与接入方式(in-session,不持久化磁盘)。

### 切换 UI

新建 `client/lib/widgets/workbench/html_view_mode_toggle.dart`:

- `HtmlViewModeToggle`(Edit | Preview segment pill,样式完全复用 `FileDiffSurfaceToggle` 的 `_Segment` 模式:Icons.code / Icons.visibility_outlined)。
- l10n:`app_en.arb` / `app_zh.arb` 新增 `htmlViewToggleEdit` / `htmlViewTogglePreview`。

### FileEditorSurface 改造

`client/lib/pages/workbench/file_editor_surface.dart`:

- `_FileEditorToolbar`:当 `isHtmlPreviewPath(path)` 时,在 diff toggle 之前渲染 `HtmlViewModeToggle`(读 `opener.htmlViewModes` 或 `context.read<HtmlViewModeStore>`)。
- `_FileEditorBody`:模式为 preview 时渲染 `HtmlPreviewPane`(需为 `StatefulWidget`,持有 webview controller 生命周期),否则走原代码编辑器。
- 新增 `isHtmlPreviewPath(String path)` 检测(扩展名 `.html`/`.htm`,放入 `file_editor_theme.dart` 与 `isImagePreviewPath` 并列)。

### 保存后自动刷新

- `HtmlPreviewPane` 内部用 `BlocListener<EditorCubit>` 监听该 path 的 `isDirty` 从 true → false(保存完成),触发 `controller.reload()`(与 markdown 预览一致:渲染磁盘内容,保存后刷新)。
- 保存失败时 `isDirty` 不变,不触发 reload。

## Section 4:浮动工作区集成(主入口)

浮动工作区(`FloatingWorkspace`)复用 `FileEditorSurface`,因此编辑器 tab 内预览自动可用;另新增专用 surface 提升体验:

新建 `client/lib/services/floating_workspace/surfaces/html_preview_floating_surface.dart`:

- 仿 `FilePreviewFloatingSurface`(`surfaces/file_preview_floating_surface.dart`),`id: 'htmlPreview'`。
- `createTab`:payload 为 html 绝对路径;标题为 basename。
- `build`:渲染 `HtmlPreviewPane`(内嵌 webview,直接渲染,不经过代码编辑器)。
- tab 工具栏操作:`refresh`(reload)+ `openExternal`(桌面端 `desktop_webview_window` 独立窗口;无则 url_launcher 系统浏览器)。
- `onTabClosed`:释放 `HtmlPreviewServer` mount 引用(引用计数减一)。

### 注册与分发

- `FloatingSurfaceRegistry.withDefaults`(floating_surface_registry.dart)新增 `html` 参数;`app_shell.dart:1680` 的调用点构造 `HtmlPreviewFloatingSurface` 传入。
- 打开 `.html` 文件的现有路径(`WorkbenchEditorOpener.openFile`)不变:浮动工作区经 `FilePreviewFloatingSurface` 打开**编辑 tab**(复用 `FileEditorSurface`,天然含 Edit|Preview 切换)。
- `HtmlPreviewFloatingSurface` 是浮动工作区内的**独立预览入口**(可"编辑 tab + 渲染 tab"并开对照,对应 orca 分屏体验),通过 surface 的打开命令/空态动作触发。

## Section 5:错误处理与降级

| 场景 | 行为 |
|---|---|
| 挂载目录不存在 / 文件读取失败(SSH 断开) | 预览区错误态(图标 + 文案 + 重试按钮) |
| 引擎不可用(缺 libwebkit2gtk / WebView2) | 预览区提示 + "在系统浏览器打开"按钮(url_launcher,file:// URL) |
| 路径穿越/越权请求 | 404,不返回内容 |
| 保存失败 | 不触发 reload(保持当前内容) |

## Section 6:测试

- `HtmlPreviewServer` 单测(`client/test/services/preview/`):
  - 目录挂载 + 相对资源解析;MIME 映射;
  - **路径穿越拒绝**(`../`、绝对路径、编码绕过);
  - 本地 fs 与 mock SSH fs(SftpFilesystem 注入)都通过;
  - 引用计数:挂载/卸载、复用、端口释放。
- `HtmlViewModeStore` 单测(per-path 模式切换与持久化行为)。
- `isHtmlPreviewPath` 单测(扩展名边界)。
- widget 测试:引擎不可用时 `HtmlPreviewPane` 显示降级 UI;`HtmlViewModeToggle` 交互。
- 遵循项目测试惯例:mock 文件系统/引擎用构造函数注入;`setUpTestAppStorage()` 支持(`test/support/post_frame_test_harness.dart`)。

## Section 7:文档更新

- `docs/DEVELOPMENT.md`:新增 Linux 系统库依赖说明(libwebkit2gtk-4.1)。
- 如涉及 vendored/补丁,同步 `docs/flutter-patches.md`。

## 非目标(v1 不做)

- 编辑器分屏(split view)预览——v1 为 tab 内切换 + 浮动工作区。
- 实时跟随未保存内容——v1 保存后刷新。
- 网页浏览(address bar / 前进后退)——v1 仅渲染本地 html 文件。
- Android 内嵌预览 v1 顺带获得(webview_flutter 官方支持),但 UI 布局以桌面验证为主。
