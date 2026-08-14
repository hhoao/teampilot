# HTML 文件预览 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 teampilot 中查看 `.html` 文件渲染结果：编辑器 tab 内 Edit|Preview 切换 + 浮动工作区内嵌预览 tab，本地与 SSH 远程工作区都支持，保存后自动刷新。

**Architecture:** 本地 HTTP 代理服务器（`HtmlPreviewServer`，dart:io 绑定 127.0.0.1 随机端口）通过 `Filesystem` 抽象（AppStorage.fs）读取挂载目录内文件，webview 引擎加载该 URL —— 从而统一本地/WSL/SSH。webview 用 `webview_flutter` 官方 API（Android/macOS 官方实现，Linux/Windows 由 `webview_win_floating` 提供实现）；`desktop_webview_window` 提供"独立窗口打开"补充。UI 层：`HtmlViewModeToggle`（Edit|Preview pill，复用 FileDiffSurfaceToggle 样式）+ `HtmlPreviewPane`（webview + 错误态 + 保存自动 reload）+ 浮动工作区 `HtmlPreviewFloatingSurface`。

**Tech Stack:** Flutter/Dart, webview_flutter, webview_win_floating, desktop_webview_window, dart:io HttpServer, Filesystem 抽象（Local/Sftp/Wsl）, flutter_bloc, shared_ui

## Global Constraints

- 平台：Linux/Windows/macOS 桌面 + Android；Linux 桌面运行时需系统库 `libwebkit2gtk-4.1-0`（文档记录，不强制检测）。
- webview 统一使用官方 `webview_flutter` API；禁止在业务代码里 `if (Platform.isLinux)` 分支换 API。
- 预览渲染**磁盘内容**，保存（Ctrl+S / EditorCubit.saveFile 成功）后 `reload()`。
- `.html`/`.htm` 文件打开默认 **Edit** 模式（先看源码）。
- SSH/远程文件必须走 `HtmlPreviewServer`（webview 无法读 sftp）；禁止直接用 file:// URL。
- 挂载目录外的任何路径请求一律 404（路径穿越防护）。
- l10n：只编辑 `client/lib/l10n/app_en.arb` 和 `app_zh.arb`。
- 日志用 AppLogger（如需要）；禁止 `print`。
- 测试惯例：文件系统 mock 用 `client/test/support/in_memory_filesystem.dart` 的 `InMemoryFilesystem`；构造函数注入。
- 验证命令：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。
- 依赖版本：`webview_flutter: ^4.13.0`、`webview_win_floating: ^3.0.0`、`desktop_webview_window: ^0.3.0`。

---

### Task 1: 接入 webview 依赖

**Files:**
- Modify: `client/pubspec.yaml`

**Interfaces:**
- Consumes: 无
- Produces: `webview_flutter` / `webview_win_floating` / `desktop_webview_window` 包可用（后续任务 import）

- [ ] **Step 1: 在 pubspec dependencies 增加三个包**

在 `client/pubspec.yaml` 的 `dependencies:` 段（`url_launcher: ^6.3.2` 附近，保持字母序无要求但就近即可）加入：

```yaml
  webview_flutter: ^4.13.0
  webview_win_floating: ^3.0.0
  desktop_webview_window: ^0.3.0
```

- [ ] **Step 2: pub get 验证**

Run: `cd client && flutter pub get`
Expected: 解析成功，无冲突报错。若出现版本冲突，`flutter pub add webview_flutter:^4.13.0 webview_win_floating:^3.0.0 desktop_webview_window:^0.3.0` 让 pub 自动解析。

- [ ] **Step 3: analyze 验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增 error（现有基线不回归）。

- [ ] **Step 4: Commit**

```bash
git add client/pubspec.yaml client/pubspec.lock
git commit -m "chore: add webview_flutter + webview_win_floating + desktop_webview_window deps"
```

---

### Task 2: l10n keys（全部新文案先落位）

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

**Interfaces:**
- Consumes: 无
- Produces: `AppLocalizations.htmlViewToggleEdit`, `htmlViewTogglePreview`, `htmlPreviewRefresh`, `htmlPreviewOpenWindow`, `htmlPreviewOpenBrowser`, `htmlPreviewErrorTitle`, `htmlPreviewErrorBody`, `floatingWorkspaceOpenHtmlPreview`（后续任务引用）

- [ ] **Step 1: app_en.arb 增加 keys**

在 `client/lib/l10n/app_en.arb` 末尾（`"fileDiffToggleFile": "File",` 所在文件内任意位置，保持 JSON 合法）追加：

```json
  "htmlViewToggleEdit": "Edit",
  "htmlViewTogglePreview": "Preview",
  "htmlPreviewRefresh": "Refresh",
  "htmlPreviewOpenWindow": "Open in Window",
  "htmlPreviewOpenBrowser": "Open in System Browser",
  "htmlPreviewErrorTitle": "Preview unavailable",
  "htmlPreviewErrorBody": "The file could not be loaded for preview.",
  "floatingWorkspaceOpenHtmlPreview": "Open HTML Preview"
```

- [ ] **Step 2: app_zh.arb 增加 keys**

在 `client/lib/l10n/app_zh.arb` 对应位置追加：

```json
  "htmlViewToggleEdit": "编辑",
  "htmlViewTogglePreview": "预览",
  "htmlPreviewRefresh": "刷新",
  "htmlPreviewOpenWindow": "在独立窗口打开",
  "htmlPreviewOpenBrowser": "在系统浏览器打开",
  "htmlPreviewErrorTitle": "预览不可用",
  "htmlPreviewErrorBody": "无法加载文件进行预览。",
  "floatingWorkspaceOpenHtmlPreview": "打开 HTML 预览"
```

- [ ] **Step 3: 生成并验证**

Run: `cd client && flutter gen-l10n && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 生成成功（`lib/l10n/gen/` 下 `AppLocalizations` 含新 getter），analyze 无新增 error。

- [ ] **Step 4: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/gen
git commit -m "feat(l10n): html preview strings (en/zh)"
```

---

### Task 3: `isHtmlPreviewPath` 检测

**Files:**
- Modify: `client/lib/services/editor/file_editor_theme.dart`（在 `isImagePreviewPath` 后新增函数）
- Test: `client/test/services/editor/file_editor_html_path_test.dart`（新建）

**Interfaces:**
- Consumes: 无
- Produces: `bool isHtmlPreviewPath(String filePath)` —— 扩展名 `.html` / `.htm`（大小写不敏感）返回 true

- [ ] **Step 1: 写失败测试**

`client/test/services/editor/file_editor_html_path_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';

void main() {
  group('isHtmlPreviewPath', () {
    test('accepts .html and .htm case-insensitively', () {
      expect(isHtmlPreviewPath('/repo/index.html'), isTrue);
      expect(isHtmlPreviewPath('/repo/a/b/page.htm'), isTrue);
      expect(isHtmlPreviewPath('/repo/INDEX.HTML'), isTrue);
    });

    test('rejects other extensions and extensionless', () {
      expect(isHtmlPreviewPath('/repo/app.dart'), isFalse);
      expect(isHtmlPreviewPath('/repo/readme.md'), isFalse);
      expect(isHtmlPreviewPath('/repo/Dockerfile'), isFalse);
      expect(isHtmlPreviewPath('/repo/page.html.tmp'), isFalse);
    });

    test('keeps workbench-openable path rules intact', () {
      expect(isWorkbenchOpenableFilePath('/repo/index.html'), isTrue);
      expect(isWorkbenchOpenableFilePath('/repo/photo.png'), isTrue);
      expect(isWorkbenchOpenableFilePath('/repo/notes.txt'), isTrue);
    });
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/editor/file_editor_html_path_test.dart`
Expected: FAIL —— `isHtmlPreviewPath` undefined。

- [ ] **Step 3: 实现**

在 `client/lib/services/editor/file_editor_theme.dart` 的 `isImagePreviewPath` 函数之后新增：

```dart
const kHtmlPreviewExtensions = {'html', 'htm'};

/// Whether [filePath] supports the in-app rendered HTML preview (Edit|Preview).
bool isHtmlPreviewPath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext.isNotEmpty && kHtmlPreviewExtensions.contains(ext);
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/editor/file_editor_html_path_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/file_editor_theme.dart client/test/services/editor/file_editor_html_path_test.dart
git commit -m "feat: add isHtmlPreviewPath detection"
```

---

### Task 4: `HtmlViewModeStore`

**Files:**
- Create: `client/lib/services/editor/html_view_mode_store.dart`
- Test: `client/test/services/editor/html_view_mode_store_test.dart`（新建）

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum HtmlViewMode { edit, preview }`
  - `class HtmlViewModeStore extends ChangeNotifier`:
    - `HtmlViewMode modeFor(String path)` —— 默认 `HtmlViewMode.edit`
    - `void setMode(String path, HtmlViewMode mode)` —— 相同值不 notify
  - `bool isHtmlPreviewPath(String path)`（Task 3 已有，此处引用）

- [ ] **Step 1: 写失败测试**

`client/test/services/editor/html_view_mode_store_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/html_view_mode_store.dart';

void main() {
  test('defaults to edit for unknown paths', () {
    final store = HtmlViewModeStore();
    expect(store.modeFor('/a.html'), HtmlViewMode.edit);
  });

  test('remembers per-path modes', () {
    final store = HtmlViewModeStore();
    store.setMode('/a.html', HtmlViewMode.preview);
    store.setMode('/b.html', HtmlViewMode.edit);
    expect(store.modeFor('/a.html'), HtmlViewMode.preview);
    expect(store.modeFor('/b.html'), HtmlViewMode.edit);
    expect(store.modeFor('/c.html'), HtmlViewMode.edit);
  });

  test('setMode with same value does not notify', () {
    final store = HtmlViewModeStore();
    var notified = 0;
    store.addListener(() => notified++);
    store.setMode('/a.html', HtmlViewMode.preview);
    store.setMode('/a.html', HtmlViewMode.preview);
    expect(notified, 1);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/editor/html_view_mode_store_test.dart`
Expected: FAIL —— 包/类不存在。

- [ ] **Step 3: 实现**

`client/lib/services/editor/html_view_mode_store.dart`（仿 `markdown_view_mode_store.dart` 结构）：

```dart
import 'package:flutter/foundation.dart';

/// In-session Edit|Preview mode for html editor paths.
///
/// Survives File↔Diff and tab switches (FileEditorSurface dispose). Not
/// persisted to disk.
class HtmlViewModeStore extends ChangeNotifier {
  HtmlViewModeStore();

  final Map<String, HtmlViewMode> _modes = {};

  HtmlViewMode modeFor(String path) => _modes[path] ?? HtmlViewMode.edit;

  void setMode(String path, HtmlViewMode mode) {
    if (_modes[path] == mode) return;
    _modes[path] = mode;
    notifyListeners();
  }
}

enum HtmlViewMode { edit, preview }
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/editor/html_view_mode_store_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/editor/html_view_mode_store.dart client/test/services/editor/html_view_mode_store_test.dart
git commit -m "feat: add HtmlViewModeStore (Edit|Preview per path)"
```

---

### Task 5: `HtmlPreviewServer`（内容服务层，核心）

**Files:**
- Create: `client/lib/services/preview/html_preview_server.dart`
- Test: `client/test/services/preview/html_preview_server_test.dart`（新建）

**Interfaces:**
- Consumes: `Filesystem`（`client/lib/services/io/filesystem.dart` 的接口：`stat` / `readBytes` / `readString` / `pathContext`）、`InMemoryFilesystem`（测试）
- Produces:
  - `class HtmlPreviewMount { final String mountId; final Uri entryUri; }`（`entryUri` 形如 `http://127.0.0.1:<port>/m/<mountId>/<entryFileName>`）
  - `class HtmlPreviewServer { HtmlPreviewServer({required Filesystem fs}); Future<HtmlPreviewMount?> mount({required String htmlDirectory, required String entryFileName}); Future<void> unmount(String mountId); bool isServing(String mountId); Future<void> dispose(); }`
  - 语义：`(htmlDirectory, entryFileName)` 相同的再次 `mount` 返回同一 `mountId`（引用计数 +1）；`unmount` 计数归零后该 mount 失效（后续请求 404）。同一 server 实例所有 mount 共用同一端口（首次 mount 时 `HttpServer.bind(InternetAddress.loopbackIPv4, 0)`）。
  - 路由：`GET /m/<mountId>/<relative>` → 解析 `<relative>` 到 `htmlDirectory` 下的绝对路径，必须在目录内（`pathContext.isWithin`），读取返回；MIME 按扩展名白名单，未知扩展名 404；文件不存在 404；非 GET/HEAD 405。`GET /` → 404。
  - MIME 表：`html/htm → text/html; charset=utf-8`、`css → text/css`、`js → text/javascript`、`json → application/json`、`svg → image/svg+xml`、`png/jpg/jpeg/gif/webp/bmp/ico → image/<type>`、`woff/woff2 → font/<type>`、`txt → text/plain; charset=utf-8`、`pdf → application/pdf`。

- [ ] **Step 1: 写失败测试**

`client/test/services/preview/html_preview_server_test.dart`（dart:io HttpClient 在 flutter test 中可用）：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/preview/html_preview_server.dart';
import 'package:teampilot/test/support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late HtmlPreviewServer server;

  setUp(() async {
    fs = InMemoryFilesystem();
    await fs.ensureDir('/repo');
    await fs.writeString('/repo/index.html', '<h1>Hello</h1>');
    await fs.writeString('/repo/style.css', 'body { color: red; }');
    await fs.writeString('/repo/sub/app.js', 'console.log(1);');
    await fs.writeString('/repo/secret.key', 'do-not-serve');
    server = HtmlPreviewServer(fs: fs);
  });

  tearDown(() async {
    await server.dispose();
  });

  Future<(int, String)> getBody(HttpClient client, Uri uri) async {
    final req = await client.getUrl(uri);
    final res = await req.close();
    return (res.statusCode, await res.transform(utf8.decoder).join());
  }

  test('mount serves entry file with html mime', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    expect(mount, isNotNull);
    final client = HttpClient();
    try {
      final res = await client.getUrl(mount!.entryUri);
      final response = await res.close();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(await response.transform(utf8.decoder).join(), '<h1>Hello</h1>');
    } finally {
      client.close();
    }
  });

  test('serves relative subresources', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final css = await client.getUrl(mount!.entryUri.resolve('style.css'));
      final cssRes = await css.close();
      expect(cssRes.statusCode, 200);
      expect(await cssRes.transform(utf8.decoder).join(), 'body { color: red; }');

      final js = await client.getUrl(mount.entryUri.resolve('sub/app.js'));
      final jsRes = await js.close();
      expect(jsRes.statusCode, 200);
    } finally {
      client.close();
    }
  });

  test('rejects path traversal outside mount root', () async {
    await fs.writeString('/secret.txt', 'top secret');
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final base = mount!.entryUri;
      for (final attempt in [
        base.resolve('../secret.txt'),
        base.resolve('../../etc/passwd'),
        Uri.parse(base.toString().replaceFirst('index.html', '%2e%2e/secret.txt')),
      ]) {
        final (status, _) = await getBody(client, attempt);
        expect(status, 404, reason: 'must reject $attempt');
      }
    } finally {
      client.close();
    }
  });

  test('rejects unknown extensions (deny by default)', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final res = await client.getUrl(mount!.entryUri.resolve('secret.key'));
      final response = await res.close();
      expect(response.statusCode, 404);
    } finally {
      client.close();
    }
  });

  test('missing file is 404', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final res = await client.getUrl(mount!.entryUri.resolve('nope.html'));
      final response = await res.close();
      expect(response.statusCode, 404);
    } finally {
      client.close();
    }
  });

  test('mount dedupes same directory and refcounts', () async {
    final a = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final b = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    expect(a!.mountId, b!.mountId);
    await server.unmount(a.mountId);
    expect(server.isServing(a.mountId), isTrue);
    await server.unmount(a.mountId);
    expect(server.isServing(a.mountId), isFalse);
  });

  test('unmounted mount 404s', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    final client = HttpClient();
    try {
      final ok = await client.getUrl(mount!.entryUri);
      expect((await ok.close()).statusCode, 200);
      await server.unmount(mount.mountId);
      final gone = await client.getUrl(mount.entryUri);
      expect((await gone.close()).statusCode, 404);
    } finally {
      client.close();
    }
  });

  test('reads through injected filesystem (ssh-equivalent)', () async {
    final mount = await server.mount(htmlDirectory: '/repo', entryFileName: 'index.html');
    await fs.writeString('/repo/index.html', 'updated');
    final client = HttpClient();
    try {
      final res = await client.getUrl(mount!.entryUri);
      final response = await res.close();
      expect(await response.transform(utf8.decoder).join(), 'updated');
    } finally {
      client.close();
    }
  });
}
```

注意：`import 'dart:convert'` 需要加在测试文件顶部（`utf8`）。`HtmlPreviewServer` 需要 `Future<void> dispose()`（Task 内实现，关闭 HttpServer + 清空 mounts；`shared` 单例不应 dispose）。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/preview/html_preview_server_test.dart`
Expected: FAIL —— 包不存在。

- [ ] **Step 3: 实现 `HtmlPreviewServer`**

`client/lib/services/preview/html_preview_server.dart`：

```dart
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../io/filesystem.dart';

/// One mounted html directory on a shared [HtmlPreviewServer].
class HtmlPreviewMount {
  const HtmlPreviewMount({required this.mountId, required this.entryUri});

  final String mountId;
  final Uri entryUri;
}

class _Mount {
  _Mount({
    required this.mountId,
    required this.fs,
    required this.htmlDirectory,
    required this.entryFileName,
  });

  final String mountId;
  final Filesystem fs;
  final String htmlDirectory;
  final String entryFileName;
  int refs = 1;
}

/// Local HTTP proxy that serves files from a mounted directory through a
/// [Filesystem] abstraction (native / WSL / SFTP), so the embedded webview can
/// render html from any storage backend.
///
/// One instance binds one loopback port shared by all its mounts. Callers
/// typically create one instance per preview pane with the current
/// [AppStorage.fs]; mounts are deduped and reference-counted inside one
/// instance.
class HtmlPreviewServer {
  HtmlPreviewServer({required Filesystem fs}) : _fs = fs;

  final Filesystem _fs;
  HttpServer? _server;
  final Map<String, _Mount> _mounts = {};
  int _nextId = 0;

  int? get port => _server?.port;

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    _server = server;
    return server;
  }

  Future<HtmlPreviewMount?> mount({
    required String htmlDirectory,
    required String entryFileName,
  }) async {
    // Dedupe identical mounts (same fs identity + directory + entry).
    for (final m in _mounts.values) {
      if (identical(m.fs, _fs) &&
          m.htmlDirectory == htmlDirectory &&
          m.entryFileName == entryFileName) {
        m.refs++;
        return HtmlPreviewMount(
          mountId: m.mountId,
          entryUri: Uri.parse(
            'http://127.0.0.1:${(await _ensureServer()).port}/m/${m.mountId}/$entryFileName',
          ),
        );
      }
    }
    final server = await _ensureServer();
    final mountId = 'h${_nextId++}';
    final mount = _Mount(
      mountId: mountId,
      fs: _fs,
      htmlDirectory: htmlDirectory,
      entryFileName: entryFileName,
    );
    _mounts[mountId] = mount;
    return HtmlPreviewMount(
      mountId: mountId,
      entryUri: Uri.parse(
        'http://127.0.0.1:${server.port}/m/$mountId/$entryFileName',
      ),
    );
  }

  bool isServing(String mountId) => _mounts.containsKey(mountId);

  Future<void> unmount(String mountId) async {
    final mount = _mounts[mountId];
    if (mount == null) return;
    mount.refs--;
    if (mount.refs > 0) return;
    _mounts.remove(mountId);
    if (_mounts.isEmpty && _server != null) {
      await _server!.close(force: true);
      _server = null;
    }
  }

  Future<void> dispose() async {
    _mounts.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method != 'GET' && req.method != 'HEAD') {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
      }
      final path = req.uri.pathSegments;
      if (path.length < 3 || path[0] != 'm') {
        await _notFound(req);
        return;
      }
      final mountId = path[1];
      final mount = _mounts[mountId];
      if (mount == null) {
        await _notFound(req);
        return;
      }
      final relative = path.sublist(2).join('/');
      final ctx = mount.fs.pathContext;
      final root = ctx.normalize(mount.htmlDirectory);
      final candidate = ctx.normalize(ctx.join(root, relative));
      if (!ctx.isWithin(root, candidate)) {
        await _notFound(req);
        return;
      }
      final stat = await mount.fs.stat(candidate);
      if (!stat.isFile) {
        await _notFound(req);
        return;
      }
      final mime = _mimeFor(candidate);
      if (mime == null) {
        await _notFound(req);
        return;
      }
      final bytes = await mount.fs.readBytes(candidate);
      if (bytes == null) {
        await _notFound(req);
        return;
      }
      final res = req.response;
      res.statusCode = HttpStatus.ok;
      res.headers.contentType = ContentType.parse(mime);
      res.headers.set('Cache-Control', 'no-cache');
      if (req.method == 'HEAD') {
        res.contentLength = bytes.length;
        await res.close();
        return;
      }
      res.add(bytes);
      await res.close();
    } on Object {
      try {
        await _notFound(req);
      } on Object {
        // Client gone; nothing to do.
      }
    }
  }

  Future<void> _notFound(HttpRequest req) async {
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  static const _mimeByExtension = <String, String>{
    'html': 'text/html; charset=utf-8',
    'htm': 'text/html; charset=utf-8',
    'css': 'text/css',
    'js': 'text/javascript',
    'mjs': 'text/javascript',
    'json': 'application/json',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'ico': 'image/x-icon',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'txt': 'text/plain; charset=utf-8',
    'pdf': 'application/pdf',
  };

  static String? _mimeFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return null;
    return _mimeByExtension[path.substring(dot + 1).toLowerCase()];
  }
}
```

注意：`_byId` 字段实际上没有用到（dedupe 直接遍历 `_mounts.values`），删除 `_byId` 声明与 `_mounts` 键值合并逻辑。`_sharedFs` 的 StateError 只是占位 —— 若不想保留，直接让 `_fs` getter 用 `_fallbackFs!` 并在 mount 时校验。**实现时保持简洁**：`Filesystem get _fs => _fallbackFs!;` 即可（构造必须传 fs；测试与生产都传）。生产代码（Task 8 接线）用 `AppStorage.fs` 传参。

测试依赖 `server.dispose()` —— 已在接口。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/preview/html_preview_server_test.dart`
Expected: 全部 PASS。若 `InMemoryFilesystem.stat` 对未知文件抛异常而非返回 notFound，用 `fs.stat` 的异常兜底（`_handle` 的 `on Object` 已转 404）。测试里 `fs.writeString` / `fs.ensureDir` 都是 async 方法，测试体与 `setUp` 中统一 `await`（例如 `await fs.ensureDir('/repo'); await fs.writeString('/repo/index.html', ...)`），避免竞态。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/preview/html_preview_server.dart client/test/services/preview/html_preview_server_test.dart
git commit -m "feat: add HtmlPreviewServer local http proxy (fs-backed, path-traversal safe)"
```

---

### Task 6: `HtmlPreviewSession`（webview controller 抽象 + 挂载生命周期）

**Files:**
- Create: `client/lib/services/preview/html_preview_session.dart`
- Test: `client/test/services/preview/html_preview_session_test.dart`（新建）

**Interfaces:**
- Consumes: `HtmlPreviewServer.mount/unmount`（Task 5）、`Filesystem`、`InMemoryFilesystem`
- Produces:
  - `abstract interface class HtmlWebViewController { Widget buildWidget(BuildContext context); Future<void> loadRequest(Uri uri); Future<void> reload(); Future<void> dispose(); }`
  - `class WebviewHtmlController implements HtmlWebViewController`（生产实现：内部 `WebViewController`，`buildWidget` 返回 `WebViewWidget`；loadRequest 用 `loadRequest(WebViewRequest(uri: uri, method: WebViewRequestMethod.get))`；reload 用 `WebViewController.reload`；dispose 为空实现）
  - `class HtmlPreviewSession { HtmlPreviewSession({required String htmlDirectory, required String entryFileName, required HtmlPreviewServer server, required HtmlWebViewController Function(Uri initialUri) controllerFactory}); Future<HtmlPreviewMount?> start(); Future<void> reload(); Future<void> dispose(); HtmlWebViewController? get controller; }`
  - 语义：`start()` = server.mount + controllerFactory(entryUri) + controller.loadRequest(entryUri)；`reload()` 转发 controller.reload；`dispose()` = controller.dispose + server.unmount。

- [ ] **Step 1: 写失败测试**

`client/test/services/preview/html_preview_session_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/preview/html_preview_server.dart';
import 'package:teampilot/services/preview/html_preview_session.dart';
import 'package:teampilot/test/support/in_memory_filesystem.dart';

class _FakeController implements HtmlWebViewController {
  final loaded = <Uri>[];
  int reloads = 0;
  bool disposed = false;

  @override
  Widget buildWidget(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> loadRequest(Uri uri) async {
    loaded.add(uri);
  }

  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test('start mounts and loads entry uri', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController();
    final session = HtmlPreviewSession(
      htmlDirectory: '/repo',
      entryFileName: 'index.html',
      server: server,
      controllerFactory: (_) => controller,
    );

    final mount = await session.start();
    expect(mount, isNotNull);
    expect(controller.loaded, hasLength(1));
    expect(controller.loaded.single.path, endsWith('/m/${mount!.mountId}/index.html'));
    await server.dispose();
  });

  test('reload forwards and dispose unmounts', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController();
    final session = HtmlPreviewSession(
      htmlDirectory: '/repo',
      entryFileName: 'index.html',
      server: server,
      controllerFactory: (_) => controller,
    );
    final mount = await session.start();

    await session.reload();
    expect(controller.reloads, 1);

    await session.dispose();
    expect(controller.disposed, isTrue);
    expect(server.isServing(mount!.mountId), isFalse);
    await server.dispose();
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/preview/html_preview_session_test.dart`
Expected: FAIL —— 包不存在。

- [ ] **Step 3: 实现**

`client/lib/services/preview/html_preview_session.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'html_preview_server.dart';

/// Host-side surface for one html preview. Implementations wrap the platform
/// webview engine (webview_flutter official API on all platforms; Linux/Windows
/// use webview_win_floating under the platform interface).
abstract interface class HtmlWebViewController {
  Widget buildWidget(BuildContext context);

  Future<void> loadRequest(Uri uri);

  Future<void> reload();

  Future<void> dispose();
}

/// Production controller backed by the official webview_flutter API.
class WebviewHtmlController implements HtmlWebViewController {
  WebviewHtmlController()
    : _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);

  final WebViewController _controller;

  @override
  Widget buildWidget(BuildContext context) => WebViewWidget(controller: _controller);

  @override
  Future<void> loadRequest(Uri uri) => _controller.loadRequest(
    WebViewRequest(uri: uri, method: WebViewRequestMethod.get),
  );

  @override
  Future<void> reload() => _controller.reload();

  @override
  Future<void> dispose() async {}
}

/// Binds one mounted html directory to a webview controller for the lifetime
/// of a preview tab.
class HtmlPreviewSession {
  HtmlPreviewSession({
    required this.htmlDirectory,
    required this.entryFileName,
    required this.server,
    required this.controllerFactory,
  });

  final String htmlDirectory;
  final String entryFileName;
  final HtmlPreviewServer server;
  final HtmlWebViewController Function(Uri initialUri) controllerFactory;

  HtmlPreviewMount? _mount;
  HtmlWebViewController? _controller;

  HtmlWebViewController? get controller => _controller;
  HtmlPreviewMount? get mount => _mount;

  Future<HtmlPreviewMount?> start() async {
    final mount = await server.mount(
      htmlDirectory: htmlDirectory,
      entryFileName: entryFileName,
    );
    if (mount == null) return null;
    _mount = mount;
    final controller = controllerFactory(mount.entryUri);
    _controller = controller;
    await controller.loadRequest(mount.entryUri);
    return mount;
  }

  Future<void> reload() async {
    await _controller?.reload();
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
    final mount = _mount;
    _mount = null;
    if (mount != null) {
      await server.unmount(mount.mountId);
    }
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/preview/html_preview_session_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/preview/html_preview_session.dart client/test/services/preview/html_preview_session_test.dart
git commit -m "feat: add HtmlPreviewSession (webview controller abstraction + mount lifecycle)"
```

---

### Task 7: `HtmlPreviewPane` widget（内嵌预览 + 错误态 + 保存自动刷新 + 独立窗口）

**Files:**
- Create: `client/lib/pages/preview/html_preview_pane.dart`
- Test: `client/test/pages/preview/html_preview_pane_test.dart`（新建）

**Interfaces:**
- Consumes: `HtmlPreviewSession` / `HtmlWebViewController`（Task 6）、`HtmlPreviewServer`（Task 5）、`EditorCubit`（`state.bucket(workspaceId).isDirty(path)`）、`AppStorage.fs`、l10n（Task 2）
- Produces: `class HtmlPreviewPane extends StatefulWidget { const HtmlPreviewPane({required this.workspaceId, required this.path, this.sessionFactory, this.fs, super.key}); }` —— `sessionFactory` 类型 `HtmlPreviewSession Function(String htmlDirectory, String entryFileName)?`，默认生产实现（`WebviewHtmlController` + `HtmlPreviewServer(fs: fs)`）；测试注入 fake。
  - 行为：initState 创建 session 并 start；顶部 36px 工具栏（刷新按钮 + 独立窗口按钮；l10n tooltip）；`BlocListener<EditorCubit>` 监听 `isDirty` true→false 时 `reload()`；加载异常（start/loadRequest 抛错）显示错误态（`htmlPreviewErrorTitle` + `htmlPreviewErrorBody` + "在系统浏览器打开"按钮 `htmlPreviewOpenBrowser` → `url_launcher.launchUrl`）；dispose 释放 session。

- [ ] **Step 1: 写失败测试**

`client/test/pages/preview/html_preview_pane_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/pages/preview/html_preview_pane.dart';
import 'package:teampilot/services/preview/html_preview_server.dart';
import 'package:teampilot/services/preview/html_preview_session.dart';
import 'package:teampilot/test/support/in_memory_filesystem.dart';

class _FakeController implements HtmlWebViewController {
  final loaded = <Uri>[];
  int reloads = 0;
  bool disposed = false;
  Object? loadError;

  @override
  Widget buildWidget(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> loadRequest(Uri uri) async {
    if (loadError != null) throw loadError!;
    loaded.add(uri);
  }

  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  testWidgets('renders webview surface when load succeeds', (tester) async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController();
    final editor = EditorCubit();

    await tester.pumpWidget(
      BlocProvider<EditorCubit>(
        create: () => editor,
        child: HtmlPreviewPane(
          workspaceId: 'ws1',
          path: '/repo/index.html',
          fs: fs,
          sessionFactory: (dir, entry) => HtmlPreviewSession(
            htmlDirectory: dir,
            entryFileName: entry,
            server: server,
            controllerFactory: (_) => controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.loaded, hasLength(1));
    expect(controller.loaded.single.path, contains('/m/'));
    await editor.close();
    await server.dispose();
  });

  testWidgets('shows error state when load fails and offers reload', (tester) async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController()..loadError = StateError('boom');
    final editor = EditorCubit();

    await tester.pumpWidget(
      BlocProvider<EditorCubit>(
        create: () => editor,
        child: HtmlPreviewPane(
          workspaceId: 'ws1',
          path: '/repo/index.html',
          fs: fs,
          sessionFactory: (dir, entry) => HtmlPreviewSession(
            htmlDirectory: dir,
            entryFileName: entry,
            server: server,
            controllerFactory: (_) => controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview unavailable'), findsOneWidget);
    await editor.close();
    await server.dispose();
  });
}
```

说明：l10n 默认 locale 为 en（AppLocalizations 未指定 locale 时默认 en），因此断言英文文案。`EditorCubit()` 无参构造可用（`_fs = fs ?? AppStorage.fs` —— 测试环境 AppStorage 未初始化会有问题吗？`EditorCubit()` 构造 `_fs = fs ?? AppStorage.fs`：AppStorage.fs 是静态 getter，测试未绑定 context 可能抛错。检查 AppStorage.fs 实现 —— 若会抛，改用 `EditorCubit(fs: fs)` 注入。**实现注意**：`HtmlPreviewPane` 的 `fs` 参数传给 session；编辑器 cubit 单独注入。测试里 `EditorCubit(fs: fs)` 更稳。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/pages/preview/html_preview_pane_test.dart`
Expected: FAIL —— 包不存在。

- [ ] **Step 3: 实现 `HtmlPreviewPane`**

`client/lib/pages/preview/html_preview_pane.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/io/filesystem.dart';
import '../../services/preview/html_preview_server.dart';
import '../../services/preview/html_preview_session.dart';

/// Embedded rendered preview for one html file.
///
/// Hosts a platform webview (webview_flutter official API) loading the file
/// through [HtmlPreviewServer]. Reloads after the file is saved (dirty→clean).
class HtmlPreviewPane extends StatefulWidget {
  const HtmlPreviewPane({
    required this.workspaceId,
    required this.path,
    this.fs,
    this.sessionFactory,
    super.key,
  });

  final String workspaceId;
  final String path;
  final Filesystem? fs;
  final HtmlPreviewSession Function(String htmlDirectory, String entryFileName)?
  sessionFactory;

  @override
  State<HtmlPreviewPane> createState() => _HtmlPreviewPaneState();
}

class _HtmlPreviewPaneState extends State<HtmlPreviewPane> {
  HtmlPreviewSession? _session;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final fs = widget.fs ?? AppStorage.fs;
    final dir = fs.pathContext.dirname(widget.path);
    final entry = p.basename(widget.path);
    final factory =
        widget.sessionFactory ??
        (dir, entry) => HtmlPreviewSession(
          htmlDirectory: dir,
          entryFileName: entry,
          server: HtmlPreviewServer(fs: fs),
          controllerFactory: (_) => WebviewHtmlController(),
        );
    final session = factory(dir, entry);
    _session = session;
    try {
      final mount = await session.start();
      if (!mounted) return;
      setState(() => _failed = mount == null);
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _reload() async {
    setState(() => _failed = false);
    try {
      await _session?.reload();
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_session?.dispose());
    _session = null;
    super.dispose();
  }

  bool _wasDirty(EditorState state) =>
      state.bucket(widget.workspaceId).isDirty(widget.path);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<EditorCubit, EditorState>(
      listenWhen: (prev, next) =>
          _wasDirty(prev) && !_wasDirty(next),
      listener: (context, state) {
        if (!_failed) unawaited(_reload());
      },
      child: ColoredBox(
        color: cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HtmlPreviewToolbar(
              path: widget.path,
              onRefresh: () => unawaited(_reload()),
              onOpenWindow: () => unawaited(_openExternalWindow()),
              onOpenBrowser: () => unawaited(_openSystemBrowser()),
              failed: _failed,
            ),
            const Divider(height: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final session = _session;
    if (session == null || _failed) {
      return _HtmlPreviewError(
        onOpenBrowser: () => unawaited(_openSystemBrowser()),
        onRetry: () => unawaited(_start()),
      );
    }
    final controller = session.controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return controller.buildWidget(context);
  }

  Future<void> _openExternalWindow() async {
    final uri = _session?.mount?.entryUri;
    if (uri == null) return;
    try {
      final webview = await _createDesktopWindow();
      webview?.launch(uri.toString());
    } on Object {
      await _openSystemBrowser();
    }
  }

  Future<void> _openSystemBrowser() async {
    final uri = _session?.mount?.entryUri;
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Desktop "Open in Window" uses desktop_webview_window when available;
/// non-desktop platforms fall back to the system browser (handled by caller).
Future<dynamic> _createDesktopWindow() async {
  if (kIsWeb) return null;
  if (!isDesktopPlatform()) return null;
  final desktop = await _tryDesktopWebviewWindow();
  return desktop;
}
```

实现提示：`_createDesktopWindow` 的桌面分支用 `desktop_webview_window`：

```dart
Future<dynamic> _tryDesktopWebviewWindow() async {
  final webview = await WebviewWindow.create(
    configuration: CreateConfiguration(
      title: 'Preview',
      windowWidth: 960,
      windowHeight: 720,
      center: true,
    ),
  );
  return webview;
}
```

`isDesktopPlatform()`：`Platform.isLinux || Platform.isWindows || Platform.isMacOS`（import dart:io，kIsWeb 先行短路）。为保持文件可测试，桌面分支包在 try/catch（插件缺失时抛异常 → 上层 catch → 系统浏览器）。

`_HtmlPreviewToolbar` 与 `_HtmlPreviewError` 实现（同文件内私有 widget）：

```dart
class _HtmlPreviewToolbar extends StatelessWidget {
  const _HtmlPreviewToolbar({
    required this.path,
    required this.onRefresh,
    required this.onOpenWindow,
    required this.onOpenBrowser,
    required this.failed,
  });

  final String path;
  final VoidCallback onRefresh;
  final VoidCallback onOpenWindow;
  final VoidCallback onOpenBrowser;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final iconColor = Theme.of(context).colorScheme.tpIconMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              p.basename(path),
              style: TpTextStyles.of(context).mdSemibold,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TpIconButton(
            tooltip: l10n.htmlPreviewRefresh,
            icon: Icons.refresh,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: iconColor,
            onTap: onRefresh,
          ),
          const SizedBox(width: 4),
          TpIconButton(
            tooltip: l10n.htmlPreviewOpenWindow,
            icon: Icons.open_in_new,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: iconColor,
            onTap: onOpenWindow,
          ),
          if (failed) ...[
            const SizedBox(width: 4),
            TpIconButton(
              tooltip: l10n.htmlPreviewOpenBrowser,
              icon: Icons.public,
              size: TpIconButton.kCompactSize,
              compact: true,
              color: iconColor,
              onTap: onOpenBrowser,
            ),
          ],
        ],
      ),
    );
  }
}

class _HtmlPreviewError extends StatelessWidget {
  const _HtmlPreviewError({
    required this.onOpenBrowser,
    required this.onRetry,
  });

  final VoidCallback onOpenBrowser;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: cs.error),
            const SizedBox(height: 12),
            Text(l10n.htmlPreviewErrorTitle, style: TpTextStyles.of(context).mdSemibold),
            const SizedBox(height: 4),
            Text(
              l10n.htmlPreviewErrorBody,
              style: TpTextStyles.of(context).sm.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TpButton(
                  label: l10n.htmlPreviewOpenBrowser,
                  icon: Icons.public,
                  onTap: onOpenBrowser,
                ),
                const SizedBox(width: 8),
                TpButton(
                  label: l10n.retry,
                  icon: Icons.refresh,
                  onTap: onRetry,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

注意：`isDesktopPlatform()` 需要 `dart:io` 的 `Platform`；`kIsWeb` 从 `package:flutter/foundation.dart`。`AppStorage.fs` 静态 getter 在测试中不触碰（测试注入 `fs` + `sessionFactory`）。`AppStorage.fs` 的实现若在测试环境抛错，注意 `_start` 的 `widget.fs ?? AppStorage.fs` 只在未注入时执行（测试注入 fs 即安全）。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/pages/preview/html_preview_pane_test.dart`
Expected: PASS。若 `EditorCubit(fs: fs)` 构造签名与测试不符，检查 `EditorCubit` 构造参数（`editor_cubit.dart:259` 附近，`_fs = fs ?? AppStorage.fs`），测试用 `EditorCubit(fs: fs)`。

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/preview/html_preview_pane.dart client/test/pages/preview/html_preview_pane_test.dart
git commit -m "feat: add HtmlPreviewPane (embedded webview, save reload, error fallback)"
```

---

### Task 8: `HtmlViewModeToggle` + `FileEditorSurface` 集成

**Files:**
- Create: `client/lib/widgets/workbench/html_view_mode_toggle.dart`
- Modify: `client/lib/pages/workbench/file_editor_surface.dart`（`_FileEditorToolbar` 加 pill；`_FileEditorBody` 加 preview 分支）
- Modify: `client/lib/services/workbench/workbench_editor_opener.dart`（新增 `htmlViewModes` 字段 + getter）
- Test: `client/test/widgets/workbench/html_view_mode_toggle_test.dart`（新建）

**Interfaces:**
- Consumes: `HtmlViewModeStore` / `HtmlViewMode`（Task 4）、`isHtmlPreviewPath`（Task 3）、`HtmlPreviewPane`（Task 7）、l10n（Task 2）
- Produces:
  - `class HtmlViewModeToggle extends StatelessWidget { const HtmlViewModeToggle({required this.mode, required this.onModeChanged, super.key}); }`（Edit|Preview pill，样式复制 `MarkdownViewModeToggle` 的 `_Segment`）
  - `WorkbenchEditorOpener` 新增：`final HtmlViewModeStore htmlViewModes;`（构造参数 `HtmlViewModeStore? htmlViewModes`，默认自建 `HtmlViewModeStore()`）
  - `FileEditorSurface`：html 文件 toolbar 显示 toggle；preview 模式时 body 渲染 `HtmlPreviewPane(workspaceId, path)`

- [ ] **Step 1: 写失败测试**

`client/test/widgets/workbench/html_view_mode_toggle_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/html_view_mode_store.dart';
import 'package:teampilot/widgets/workbench/html_view_mode_toggle.dart';

void main() {
  testWidgets('tapping preview segment reports preview mode', (tester) async {
    HtmlViewMode? reported;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HtmlViewModeToggle(
            mode: HtmlViewMode.edit,
            onModeChanged: (mode) => reported = mode,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    expect(reported, HtmlViewMode.preview);

    await tester.tap(find.byIcon(Icons.code));
    expect(reported, HtmlViewMode.edit);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/widgets/workbench/html_view_mode_toggle_test.dart`
Expected: FAIL —— 包不存在。

- [ ] **Step 3: 实现 `HtmlViewModeToggle`**

`client/lib/widgets/workbench/html_view_mode_toggle.dart`（直接复用 `MarkdownViewModeToggle` 的结构与样式，改枚举与 l10n）：

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/editor/html_view_mode_store.dart';

/// Compact Edit | Preview pill for html files (mirrors File|Diff).
class HtmlViewModeToggle extends StatelessWidget {
  const HtmlViewModeToggle({
    required this.mode,
    required this.onModeChanged,
    super.key,
  });

  final HtmlViewMode mode;
  final ValueChanged<HtmlViewMode> onModeChanged;

  static const double _size = TpIconButton.kCompactSize;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final color = cs.tpIconMuted;
    return Container(
      height: _size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.code,
            tooltip: l10n.htmlViewToggleEdit,
            selected: mode == HtmlViewMode.edit,
            color: color,
            onTap: () => onModeChanged(HtmlViewMode.edit),
          ),
          Container(width: 1, height: 14, color: cs.outlineVariant),
          _Segment(
            icon: Icons.visibility_outlined,
            tooltip: l10n.htmlViewTogglePreview,
            selected: mode == HtmlViewMode.preview,
            color: color,
            onTap: () => onModeChanged(HtmlViewMode.preview),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: TpHover(
        backgroundColor: selected
            ? cs.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.zero,
        width: 30,
        height: HtmlViewModeToggle._size,
        hoverColor: color.withValues(alpha: 0.12),
        splashColor: color.withValues(alpha: 0.2),
        onTap: onTap,
        child: Center(
          child: Icon(icon, size: context.tpIconSizes.sm, color: color),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 集成到 `WorkbenchEditorOpener`**

`client/lib/services/workbench/workbench_editor_opener.dart`：

- import `../editor/html_view_mode_store.dart`；
- 构造参数新增 `HtmlViewModeStore? htmlViewModes`，字段：

```dart
  final HtmlViewModeStore htmlViewModes;

  // constructor:
  HtmlViewModeStore? htmlViewModes,
  ...
       htmlViewModes = htmlViewModes ?? HtmlViewModeStore(),
```

- [ ] **Step 5: 集成到 `FileEditorSurface`**

`client/lib/pages/workbench/file_editor_surface.dart`：

1. import 增加：
```dart
import '../../services/editor/html_view_mode_store.dart';
import '../../widgets/workbench/html_view_mode_toggle.dart';
import '../preview/html_preview_pane.dart';
```

2. `_FileEditorToolbar.build` 中 `final isMarkdown = ...` 之后新增：
```dart
    final isHtml = isHtmlPreviewPath(path);
```
并在 `isMarkdown` 块之后、`canToggleDiff` 块之前插入：
```dart
          if (isHtml) ...[
            const SizedBox(width: 4),
            ListenableBuilder(
              listenable: opener.htmlViewModes,
              builder: (context, _) {
                return HtmlViewModeToggle(
                  mode: opener.htmlViewModes.modeFor(path),
                  onModeChanged: (mode) =>
                      opener.htmlViewModes.setMode(path, mode),
                );
              },
            ),
          ],
```

3. `_FileEditorBody.build` 中，`if (!isMarkdownEditorPath(path))` 分支前新增 html preview 分支：
```dart
    if (isHtmlPreviewPath(path)) {
      final opener = context.read<WorkbenchEditorOpener>();
      return ListenableBuilder(
        listenable: opener.htmlViewModes,
        builder: (context, _) {
          final mode = opener.htmlViewModes.modeFor(path);
          if (mode == HtmlViewMode.preview) {
            return HtmlPreviewPane(workspaceId: workspaceId, path: path);
          }
          return _CodeEditorPane(
            workspaceId: workspaceId,
            path: path,
            controller: controller,
            readOnly: model.readOnly,
          );
        },
      );
    }
```
（放在 `controller == null` 检查之后、现有 `if (!isMarkdownEditorPath(path))` 之前。）

- [ ] **Step 6: 运行确认通过**

Run: `cd client && flutter test test/widgets/workbench/html_view_mode_toggle_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: toggle 测试 PASS；analyze 无新增 error。

- [ ] **Step 7: Commit**

```bash
git add client/lib/widgets/workbench/html_view_mode_toggle.dart client/lib/pages/workbench/file_editor_surface.dart client/lib/services/workbench/workbench_editor_opener.dart client/test/widgets/workbench/html_view_mode_toggle_test.dart
git commit -m "feat: html Edit|Preview toggle in file editor toolbar"
```

---

### Task 9: 浮动工作区 `HtmlPreviewFloatingSurface` + `WorkbenchTabKind.htmlPreview`

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_tab.dart`（枚举 + `surfaceIdFor` + `isCenterStripWorkbenchTab` + `WorkbenchTabId.htmlPreview` factory）
- Create: `client/lib/services/floating_workspace/surfaces/html_preview_floating_surface.dart`
- Modify: `client/lib/services/floating_workspace/floating_surface_registry.dart`（`withDefaults` 加 `html` 参数）
- Modify: `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart`（`floatingTabMenuIdentity` + `_iconFor` 分支）
- Modify: `client/lib/services/workbench/workbench_editor_opener.dart`（`openHtmlPreview` + `_closeReplaced` 的 htmlPreview case）
- Modify: `client/lib/services/commands/command_ids.dart`（`floatingOpenHtmlPreview`）
- Modify: `client/lib/services/floating_workspace/floating_workspace_commands.dart`（`onOpenHtmlPreview` 参数 + 注册）
- Modify: `client/lib/services/floating_workspace/floating_workspace_open_file.dart`（`pickAndOpenFloatingHtmlPreview`）
- Modify: `client/lib/pages/floating_workspace/floating_workspace_panel.dart`（`_labelFor` 分支）
- Modify: `client/lib/app/app_shell.dart`（`floatingSurfaceRegistry` 加 html、命令 handler 接线）
- Test: `client/test/services/floating_workspace/html_preview_floating_surface_test.dart`（新建）+ Modify: `client/test/services/floating_workspace/floating_surface_registry_test.dart`

**Interfaces:**
- Consumes: `HtmlPreviewPane`（Task 7）、`FloatingSurface` 基类、`WorkbenchTabId`、`CommandIds`
- Produces:
  - `enum WorkbenchTabKind { session, file, diff, shell, run, htmlPreview }`
  - `WorkbenchTabId.htmlPreview(String absolutePath)` factory；`surfaceIdFor(htmlPreview) => 'htmlPreview'`；`isCenterStripWorkbenchTab(htmlPreview) => false`
  - `class HtmlPreviewFloatingSurface extends FloatingSurface`：`id => 'htmlPreview'`，`allowMultipleTabs => true`，`createTab` 生成 `FloatingTab(id: 'htmlPreview:$path', surfaceId: id, title: basename, payload: path)`，`build` 返回 `HtmlPreviewPane(workspaceId: _floating.state.activeWorkspaceId, path: payload)`（workspaceId 空时 `SizedBox.shrink`），`activate`/`canClose` 默认
  - `CommandIds.floatingOpenHtmlPreview = 'floatingWorkspace.openHtmlPreview'`
  - `pickAndOpenFloatingHtmlPreview({required FloatingWorkspaceCubit floating, required WorkbenchEditorOpener opener, required List<Workspace> workspaces, FloatingWorkspaceFilePicker? pickFiles})`（仿 `pickAndOpenFloatingWorkspaceFile`，选中后调 `opener.openHtmlPreview`）
  - `WorkbenchEditorOpener.openHtmlPreview(String workspaceId, String path)`：`_floating.ensureOpen(); _floating.setActiveWorkspace(workspaceId); _workbench.openFloating(workspaceId, WorkbenchTabId.htmlPreview(normalized), activate: true);`

- [ ] **Step 1: 写失败测试**

`client/test/services/floating_workspace/html_preview_floating_surface_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/services/floating_workspace/surfaces/html_preview_floating_surface.dart';

void main() {
  test('createTab builds stable tab for html path', () {
    final floating = FloatingWorkspaceCubit();
    final surface = HtmlPreviewFloatingSurface(floating: floating);
    final tab = surface.createTab(workspaceId: 'ws1', payload: '/repo/a.html');
    expect(tab.surfaceId, 'htmlPreview');
    expect(tab.id, 'htmlPreview:/repo/a.html');
    expect(tab.title, 'a.html');
    expect(tab.payload, '/repo/a.html');
    floating.close();
  });
}
```

（`FloatingWorkspaceCubit` 构造无参即可；`close()` 释放。）

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/floating_workspace/html_preview_floating_surface_test.dart`
Expected: FAIL —— 类不存在。

- [ ] **Step 3: `WorkbenchTabKind.htmlPreview`**

`client/lib/cubits/workbench/workbench_tab.dart`：

- 枚举改为：`enum WorkbenchTabKind { session, file, diff, shell, run, htmlPreview }`
- `surfaceIdFor` 加分支：`WorkbenchTabKind.htmlPreview => 'htmlPreview',`
- `isCenterStripWorkbenchTab` 不变（htmlPreview 非 session/shell/run → 返回 true！）—— **注意**：`isCenterStripWorkbenchTab` 当前实现是 `kind != shell && kind != run`，htmlPreview 会落到 true（center strip）。需要改为浮动专属：

```dart
bool isCenterStripWorkbenchTab(WorkbenchTabKind kind) =>
    kind == WorkbenchTabKind.session ||
    kind == WorkbenchTabKind.file ||
    kind == WorkbenchTabKind.diff;
```

- `WorkbenchTabId` 新增 factory：

```dart
  factory WorkbenchTabId.htmlPreview(String absolutePath) =>
      WorkbenchTabId._(WorkbenchTabKind.htmlPreview, absolutePath);
```

- [ ] **Step 4: `HtmlPreviewFloatingSurface`**

`client/lib/services/floating_workspace/surfaces/html_preview_floating_surface.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../../models/floating_workspace_tab.dart';
import '../../../pages/preview/html_preview_pane.dart';
import '../floating_surface.dart';

/// Floating surface that hosts an embedded rendered html preview tab.
class HtmlPreviewFloatingSurface extends FloatingSurface {
  HtmlPreviewFloatingSurface({required FloatingWorkspaceCubit floating})
    : _floating = floating;

  final FloatingWorkspaceCubit _floating;

  @override
  String get id => 'htmlPreview';

  @override
  FloatingEmptyAction? get emptyAction => const FloatingEmptyAction(
    commandId: 'floatingWorkspace.openHtmlPreview',
    labelKey: 'openHtmlPreview',
    icon: Icons.preview_outlined,
  );

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final path = payload is String ? payload.trim() : '';
    return FloatingTab(
      id: path.isEmpty ? 'htmlPreview:' : 'htmlPreview:$path',
      surfaceId: id,
      title: path.isEmpty ? 'HTML Preview' : p.basename(path),
      payload: path.isEmpty ? null : path,
    );
  }

  @override
  Widget build(BuildContext context, FloatingTab tab) {
    final path = tab.payload;
    if (path is! String || path.isEmpty) {
      return const SizedBox.shrink();
    }
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    return HtmlPreviewPane(workspaceId: workspaceId, path: path);
  }

  @override
  Future<void> activate(FloatingTab tab) async {}
}
```

注意：`emptyAction.commandId` 直接引用字符串 `'floatingWorkspace.openHtmlPreview'` 而不是 `CommandIds.floatingOpenHtmlPreview`（避免 import 循环）——改为 import `../../commands/command_ids.dart` 用常量更佳；若出现循环依赖则用字符串字面量（与 `CommandIds.floatingOpenHtmlPreview` 常量值必须一致）。

- [ ] **Step 5: registry + tab bar + opener + 命令接线**

`floating_surface_registry.dart` 的 `withDefaults`：

```dart
  factory FloatingSurfaceRegistry.withDefaults({
    required FloatingSurface file,
    required FloatingSurface terminal,
    FloatingSurface? diff,
    FloatingSurface? run,
    FloatingSurface? html,
  }) => FloatingSurfaceRegistry([
    terminal,
    file,
    if (diff != null) diff,
    if (run != null) run,
    if (html != null) html,
  ]);
```

`floating_workspace_tab_bar.dart`：

- `floatingTabMenuIdentity` 加分支：
```dart
    'htmlPreview' => (
      WorkbenchTabKind.htmlPreview,
      tab.payload is String ? tab.payload as String : null,
    ),
```
- `_iconFor` 加分支：`'htmlPreview' => Icons.preview_outlined,`

`workbench_editor_opener.dart`：

- 新增方法（`openDiff` 之后）：

```dart
  /// Opens a floating rendered html preview tab (no editor bucket entry).
  void openHtmlPreview(String workspaceId, String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return;
    _floating.ensureOpen();
    _floating.setActiveWorkspace(workspaceId);
    _workbench.openFloating(
      workspaceId,
      WorkbenchTabId.htmlPreview(normalized),
      activate: true,
    );
  }
```

- `_closeReplaced` 的 switch 加 case：`case WorkbenchTabKind.htmlPreview: break;`

`command_ids.dart` 加：

```dart
  static const String floatingOpenHtmlPreview = 'floatingWorkspace.openHtmlPreview';
```

`floating_workspace_open_file.dart` 新增（仿 `pickAndOpenFloatingWorkspaceFile`）：

```dart
/// Picks an html file and opens it as a floating rendered preview tab.
Future<void> pickAndOpenFloatingHtmlPreview({
  required FloatingWorkspaceCubit floating,
  required WorkbenchEditorOpener opener,
  required List<Workspace> workspaces,
  FloatingWorkspaceFilePicker? pickFiles,
}) async {
  final workspaceId = floating.state.activeWorkspaceId.trim();
  if (workspaceId.isEmpty) return;
  final root = workspaces
      .where((w) => w.workspaceId == workspaceId)
      .map((w) => w.firstFolderPath.trim())
      .where((p) => p.isNotEmpty)
      .firstOrNull ??
      '';
  final picker =
      pickFiles ??
      ({
        type = FileType.any,
        allowMultiple = false,
        initialDirectory,
      }) => FilePicker.platform.pickFiles(
        type: type,
        allowMultiple: allowMultiple,
        initialDirectory: initialDirectory,
      );
  final result = await picker(
    type: FileType.any,
    allowMultiple: false,
    initialDirectory: root.isEmpty ? null : root,
  );
  final path = result?.files.firstOrNull?.path?.trim() ?? '';
  if (path.isEmpty) return;
  if (!isHtmlPreviewPath(path)) {
    await opener.openFile(workspaceId, path);
    return;
  }
  opener.openHtmlPreview(workspaceId, path);
}
```

`floating_workspace_commands.dart`：签名加 `Future<void> Function()? onOpenHtmlPreview`，注册：

```dart
  bus.register(CommandIds.floatingOpenHtmlPreview, () {
    floating.ensureOpen();
    final handler = onOpenHtmlPreview;
    if (handler != null) unawaited(handler());
  });
```

`floating_workspace_panel.dart` 的 `_labelFor` 加分支：`'openHtmlPreview' => l10n.floatingWorkspaceOpenHtmlPreview,`

`app_shell.dart`：
- `HtmlPreviewPane` 生产路径自建 `HtmlPreviewServer(fs: fs)`（Task 7 已定：每个 pane 一个 server 实例、随机端口，Task 5 的 dedupe/refcount 在单实例内生效）—— app_shell **无需**为 server 接线。
- `floatingSurfaceRegistry` 构造加 `html: HtmlPreviewFloatingSurface(floating: floatingWorkspaceCubit)`
- 命令注册处加 `onOpenHtmlPreview: openFloatingHtmlPreviewPicker`，并定义：

```dart
  Future<void> openFloatingHtmlPreviewPicker() async {
    final opener = workbenchEditorOpenerRef;
    if (opener == null) return;
    await pickAndOpenFloatingHtmlPreview(
      floating: floatingWorkspaceCubit,
      opener: opener,
      workspaces: chatCubit.state.workspaces,
    );
  }
```

- [ ] **Step 6: 运行确认通过**

Run: `cd client && flutter test test/services/floating_workspace/html_preview_floating_surface_test.dart test/services/floating_workspace/floating_surface_registry_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: PASS + 无新增 error（registry 测试若因 `withDefaults` 新参数需要更新，补 `html:` 参数或保持可选不破坏）。

- [ ] **Step 7: Commit**

```bash
git add client/lib/cubits/workbench/workbench_tab.dart client/lib/services/floating_workspace/ client/lib/pages/floating_workspace/ client/lib/services/workbench/workbench_editor_opener.dart client/lib/services/commands/command_ids.dart client/lib/app/app_shell.dart client/test/services/floating_workspace/
git commit -m "feat: floating workspace html preview surface + command entry"
```

---

### Task 10: 文档 + 全量验证

**Files:**
- Modify: `docs/DEVELOPMENT.md`（Linux 系统库依赖）

- [ ] **Step 1: 文档更新**

`docs/DEVELOPMENT.md` 的系统依赖部分（Linux 段落）补充：

```markdown
### Linux 系统库(HTML 预览)

HTML 预览(webview)依赖 WebKitGTK 4.1:

```bash
sudo apt-get install libwebkit2gtk-4.1-0 libwebkit2gtk-4.1-dev libsoup-3.0-0 libsoup-3.0-dev
```
```

- [ ] **Step 2: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze 无 error（允许既有 info/warning 基线）；测试全部 PASS（含既有测试，确认无回归）。

- [ ] **Step 3: Commit**

```bash
git add docs/DEVELOPMENT.md
git commit -m "docs: html preview linux webkit2gtk system dependency"
```

---

## Self-Review 记录

- **Spec 覆盖**：
  - Section 1 HtmlPreviewServer → Task 5（含 MIME/路径穿越/引用计数/SSH fs 注入测试）
  - Section 2 HtmlPreviewPane/依赖 → Task 1（依赖）、6（session/controller 抽象）、7（pane + 降级）
  - Section 3 编辑器 Edit|Preview + 保存刷新 → Task 3（isHtmlPreviewPath）、4（store）、7（保存 reload）、8（toggle + surface 集成）
  - Section 4 浮动工作区 → Task 9（surface + kind + 命令 + 接线）
  - Section 5 错误处理 → Task 7（错误态 + 系统浏览器降级）
  - Section 6 测试 → 各任务测试内
  - Section 7 文档 → Task 10
- **占位符扫描**：无 TBD/TODO；所有代码步骤含完整代码。
- **类型一致性**：`HtmlPreviewMount.entryUri`/`mountId` 在 Task 5/6/7 一致；`HtmlWebViewController` 接口三处一致；`WorkbenchTabKind.htmlPreview` 在 Task 9 内一致；`HtmlPreviewServer(fs:)` 构造在 Task 5/6/7/9 一致；`openHtmlPreview` 签名在 opener/命令/picker 一致。
