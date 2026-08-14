# 子 Agent 自动跟随预览 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 opencode 座位会话解析会落到 task 子会话的 bug,并新增一个默认关闭的全局偏好:子 agent 出现时自动打开预览覆盖层并实时跟随,返回父会话后停止跟随。

**Architecture:** 三部分:①`opencodeNewestSessionId` 只解析根会话(排除 `parent_id` 非空的行,legacy 布局走 data-JSON 过滤);②`SubagentPreviewController` 增加纯状态跟随机(compute/apply/pop 语义);③全局偏好 `LayoutPreferences.autoOpenSubagentPreview`(默认 false)接线到配置页与 `SessionChatView` 的 builder(computeAutoFollow 返回待开 id,post-frame apply,避免 build 期 notify)。

**Tech Stack:** Flutter / flutter_bloc / sqlite3(worker isolate 查询)/ 现有测试 harness(flutter_test)。

## Global Constraints

- 测试命令:`cd client && flutter test --exclude-tags integration <path>`(单文件跑 `flutter test <path>`)
- 静态检查:`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- l10n 只编辑 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`,改后运行 `cd client && flutter gen-l10n`
- 不加注释之外的无关改动;每个任务独立可测、独立 commit
- `SubagentPreviewController` 保持零依赖(不 import flutter/widgets 之外的包、不 import ai_message_core)——running id 只是字符串
- 不在 build 阶段调用 `notifyListeners()`(computeAutoFollow 纯函数,apply 放 post-frame)

---

### Task 1:根因修复 — `opencodeNewestSessionId` 只解析根会话

**Files:**
- Modify: `client/lib/services/cli/opencode/capabilities/native_session_id.dart:102-115`
- Modify: `client/test/services/cli/registry/capabilities/history/opencode_sqlite_worker_pool_test.dart:24-45`(setUp 表结构 + 插入语句)
- Test: `client/test/services/cli/registry/capabilities/history/opencode_sqlite_worker_pool_test.dart`

**Interfaces:**
- Consumes: `OpencodeSqliteWorkerPool.instance.run<T>(dbPath:, query:, args:)`(现有)
- Produces: `String? opencodeNewestSessionId(Database db, Object? args)` —— 签名不变,语义变为"最新根会话";legacy 布局无 `parent_id` 列时回退 data-JSON 全扫描过滤

- [ ] **Step 1:更新现有 setUp 表结构并写失败测试**

修改 `opencode_sqlite_worker_pool_test.dart` 的 `setUp`(第 28-41 行),表结构对齐真实 schema:

```dart
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sqlite-pool-test-');
    dbPath = p.join(tmp.path, 'opencode.db');
    final db = sqlite3.open(dbPath);
    try {
      db.execute(
        'CREATE TABLE session ('
        'id TEXT, parent_id TEXT, time_updated INTEGER, data TEXT)',
      );
      db.execute(
        'INSERT INTO session (id, parent_id, time_updated) '
        'VALUES (?, ?, ?)',
        ['ses_1', null, 100],
      );
    } finally {
      db.close();
    }
  });
```

在文件末尾(第 192 行 `}` 前)追加测试:

```dart
  test('returns newest ROOT session when a task child is newest', () async {
    final pool = OpencodeSqliteWorkerPool.instance;
    final db = sqlite3.open(dbPath);
    try {
      db.execute(
        'INSERT INTO session (id, parent_id, time_updated) VALUES (?, ?, ?)',
        ['ses_child', 'ses_1', 200],
      );
      db.execute(
        'INSERT INTO session (id, parent_id, time_updated) VALUES (?, ?, ?)',
        ['ses_other_root', null, 50],
      );
    } finally {
      db.close();
    }
    final result = await pool.run<String?>(
      dbPath: dbPath,
      query: opencodeNewestSessionId,
    );
    expect(result, 'ses_1'); // child 最新也不能被选中
    pool.dispose(dbPath);
  });

  test('empty parent_id is treated as a root', () async {
    final pool = OpencodeSqliteWorkerPool.instance;
    final db = sqlite3.open(dbPath);
    try {
      db.execute(
        'INSERT INTO session (id, parent_id, time_updated) VALUES (?, ?, ?)',
        ['ses_2', '', 200],
      );
    } finally {
      db.close();
    }
    final result = await pool.run<String?>(
      dbPath: dbPath,
      query: opencodeNewestSessionId,
    );
    expect(result, 'ses_2');
    pool.dispose(dbPath);
  });

  test('legacy layout without parent_id column filters children via data JSON',
      () async {
    final pool = OpencodeSqliteWorkerPool.instance;
    final legacyDir = tmp.createTempSync('legacy-');
    final legacyDbPath = p.join(legacyDir.path, 'opencode.db');
    final db = sqlite3.open(legacyDbPath);
    try {
      db.execute(
        'CREATE TABLE session (id TEXT, data TEXT, time_updated INTEGER)',
      );
      db.execute(
        'INSERT INTO session VALUES (?, ?, ?)',
        ['ses_child', '{"parentID":"ses_p"}', 300],
      );
      db.execute(
        'INSERT INTO session VALUES (?, ?, ?)',
        ['ses_root', '{}', 100],
      );
    } finally {
      db.close();
    }
    final result = await pool.run<String?>(
      dbPath: legacyDbPath,
      query: opencodeNewestSessionId,
    );
    expect(result, 'ses_root');
    pool.dispose(legacyDbPath);
  });
```

- [ ] **Step 2:运行测试确认失败**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/opencode_sqlite_worker_pool_test.dart`
Expected: 新测试 FAIL——`opencodeNewestSessionId` 返回 `ses_child`(无 parent 过滤),且现有测试因新表结构报错(`no such column: parent_id` 或插入失败)。

- [ ] **Step 3:实现根会话过滤**

修改 `client/lib/services/cli/opencode/capabilities/native_session_id.dart:102-115`:

```dart
/// Newest ROOT session row — never a task child, so the seat stays on the
/// parent conversation while a `task` sub-agent is running.
///
/// Current OpenCode layout: `parent_id` is a real column — one indexed
/// scoped query. Legacy layout (parent linkage inside the `data` JSON blob)
/// falls back to a full scan filtering out rows with a non-empty parent.
String? opencodeNewestSessionId(Database db, Object? args) {
  try {
    final rows = db.select(
      '''
SELECT id
FROM session
WHERE parent_id IS NULL OR parent_id = ''
ORDER BY time_updated DESC, id DESC
LIMIT 1
''',
    );
    if (rows.isEmpty) return null;
    final id = '${rows.first['id']}'.trim();
    return id.isEmpty ? null : id;
  } on SqliteException {
    // Legacy layout: no parent_id column; parent linkage lives in `data`.
    final rows = db.select(
      '''
SELECT id, data, time_updated
FROM session
ORDER BY time_updated DESC, id DESC
''',
    );
    for (final row in rows) {
      final id = '${row['id']}'.trim();
      if (id.isEmpty) continue;
      final obj = _decodeRowData(row['data']);
      if (obj == null) continue;
      final parent = '${obj['parent_id'] ?? obj['parentID'] ?? ''}'.trim();
      if (parent.isNotEmpty) continue;
      return id;
    }
    return null;
  }
}
```

在该文件末尾追加私有 helper(仿 side_resolver.dart:338 的模式):

```dart
Map<String, dynamic>? _decodeRowData(Object? raw) {
  try {
    final decoded = switch (raw) {
      final String s => jsonDecode(s),
      final List<int> bytes => jsonDecode(utf8.decode(bytes)),
      _ => null,
    };
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on Object {
    return null;
  }
  return null;
}
```

文件头部已有 `import 'package:sqlite3/sqlite3.dart';`(SqliteException 可用);追加 `import 'dart:convert';`(jsonDecode / utf8)。

- [ ] **Step 4:运行测试确认通过**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/opencode_sqlite_worker_pool_test.dart`
Expected: 全部 PASS(新 3 个 + 原有测试)。

- [ ] **Step 5:Commit**

```bash
git add client/lib/services/cli/opencode/capabilities/native_session_id.dart \
        client/test/services/cli/registry/capabilities/history/opencode_sqlite_worker_pool_test.dart
git commit -m "fix(opencode): resolve newest ROOT session, never a task child"
```

---

### Task 2:Controller 跟随状态机

**Files:**
- Modify: `client/lib/pages/chat/subagent_preview_controller.dart`
- Modify: `client/test/pages/chat/subagent_preview_controller_test.dart`
- Modify: `client/lib/pages/chat/session_chat_message_area.dart:293`(`onBack` 改用新方法)

**Interfaces:**
- Consumes: 现有 `push(String)` / `stack` / `clear()` / `pruneToAvailable(Set<String>)`
- Produces:
  - `String? computeAutoFollow({required bool prefEnabled, required List<String> runningIds, required Set<String> availableIds})` —— 纯函数,返回待自动打开的 id 或 null(不 notify)
  - `void autoOpen(String toolCallId)` —— 应用 computeAutoFollow 的结果(push,stack 已有则跳过)
  - `void popAndStopFollow()` —— 替换原 `pop()`:pop 一层;栈空时 `_followStopped = true` 且 `_followUntilId = 弹出的 id`
  - `bool get followStopped`、`void resetFollow()`

- [ ] **Step 1:写失败测试**

在 `client/test/pages/chat/subagent_preview_controller_test.dart` 追加:

```dart
  test('computeAutoFollow: pref off / follow stopped / duplicates', () {
    final c = SubagentPreviewController();

    // pref 关闭 → 不自动开
    expect(
      c.computeAutoFollow(
        prefEnabled: false,
        runningIds: ['task-1'],
        availableIds: {'task-1'},
      ),
      isNull,
    );

    // pref 开启 + running 且 attachment 可用 → 返回最新 running id
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-old', 'task-new'],
        availableIds: {'task-new', 'task-old'},
      ),
      'task-new',
    );
    c.autoOpen('task-new');
    expect(c.stack, ['task-new']);

    // 已打开的 id 不重复返回
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-new'],
        availableIds: {'task-new'},
      ),
      isNull,
    );

    // attachment 尚未膨胀 → 跳过(等到 available 后再弹)
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-2'],
        availableIds: const {},
      ),
      isNull,
    );
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-2'],
        availableIds: {'task-2'},
      ),
      'task-2',
    );
  });

  test('popAndStopFollow: nested pop keeps follow; back to parent stops it', () {
    final c = SubagentPreviewController();
    c.autoOpen('task-1');
    c.push('nested');
    c.popAndStopFollow(); // 嵌套层 → 仍在预览内
    expect(c.stack, ['task-1']);
    expect(c.followStopped, isFalse);

    c.popAndStopFollow(); // 回到父会话 → 停止跟随
    expect(c.stack, isEmpty);
    expect(c.followStopped, isTrue);

    // followStopped 后同一/其他子 agent 都不再自动开
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-2'],
        availableIds: {'task-2'},
      ),
      isNull,
    );

    // resetFollow(会话切换)解除
    c.resetFollow();
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-2'],
        availableIds: {'task-2'},
      ),
      'task-2',
    );
  });

  test('clear resets follow state', () {
    final c = SubagentPreviewController();
    c.autoOpen('task-1');
    c.popAndStopFollow();
    expect(c.followStopped, isTrue);
    c.clear();
    expect(c.followStopped, isFalse);
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-1'],
        availableIds: {'task-1'},
      ),
      'task-1',
    );
  });
```

同时把原测试中的 `c.pop()` 改为 `c.popAndStopFollow()`(push pop prune 那条)。原 `pop()` 语义测试(`push pop clear notify`)中 `pop` 调用改成 `popAndStopFollow`,`prune is silent` 保持。

- [ ] **Step 2:运行测试确认失败**

Run: `cd client && flutter test test/pages/chat/subagent_preview_controller_test.dart`
Expected: 编译失败(`computeAutoFollow` 等不存在)。

- [ ] **Step 3:实现 controller**

重写 `client/lib/pages/chat/subagent_preview_controller.dart`:

```dart
import 'package:flutter/foundation.dart';

/// Stack of subagent preview [toolCallId]s for the Chat overlay.
class SubagentPreviewController extends ChangeNotifier {
  final List<String> _stack = <String>[];

  /// Back-to-parent stops auto-follow for the rest of this session.
  bool _followStopped = false;

  /// Last id closed by back; it never re-opens automatically.
  String? _followUntilId;

  List<String> get stack => List<String>.unmodifiable(_stack);

  /// True once the user backed out of a preview to the parent conversation.
  bool get followStopped => _followStopped;

  void push(String toolCallId) {
    _stack.add(toolCallId);
    notifyListeners();
  }

  /// Applies a [computeAutoFollow] result (deferred to post-frame by callers).
  void autoOpen(String toolCallId) {
    if (_stack.contains(toolCallId)) return;
    push(toolCallId);
  }

  /// Pure: returns the id to auto-open, or null. Safe to call during build —
  /// never notifies. [runningIds] must be newest-first; the first id that is
  /// not handled, not already open, and has an inflated attachment wins.
  String? computeAutoFollow({
    required bool prefEnabled,
    required List<String> runningIds,
    required Set<String> availableIds,
  }) {
    if (!prefEnabled || _followStopped) return null;
    for (final id in runningIds) {
      if (id == _followUntilId) continue;
      if (_stack.contains(id)) continue;
      if (!availableIds.contains(id)) continue;
      return id;
    }
    return null;
  }

  /// Back from the preview: pops one level. Returning to the parent
  /// conversation stops auto-follow for this session.
  void popAndStopFollow() {
    if (_stack.isEmpty) return;
    final popped = _stack.removeLast();
    if (_stack.isEmpty) {
      _followStopped = true;
      _followUntilId = popped;
    }
    notifyListeners();
  }

  void resetFollow() {
    _followStopped = false;
    _followUntilId = null;
  }

  void clear() {
    if (_stack.isEmpty && !_followStopped && _followUntilId == null) return;
    _stack.clear();
    resetFollow();
    notifyListeners();
  }

  /// Keep the longest valid prefix from the root. Silent — no [notifyListeners].
  void pruneToAvailable(Set<String> available) {
    var keep = 0;
    while (keep < _stack.length && available.contains(_stack[keep])) {
      keep++;
    }
    if (keep < _stack.length) {
      _stack.removeRange(keep, _stack.length);
    }
  }
}
```

> 注:原 `pop()` 被 `popAndStopFollow()` 取代;`clear()` 现在也重置 follow 状态(会话切换单一入口,spec 3d)。

- [ ] **Step 4:更新 back 按钮接线**

`client/lib/pages/chat/session_chat_message_area.dart:293`:

```dart
onBack: subagentPreview.popAndStopFollow,
```

(原 `subagentPreview.pop` → `popAndStopFollow`。)

- [ ] **Step 5:运行测试确认通过**

Run: `cd client && flutter test test/pages/chat/subagent_preview_controller_test.dart`
Expected: 全部 PASS。

- [ ] **Step 6:Commit**

```bash
git add client/lib/pages/chat/subagent_preview_controller.dart \
        client/lib/pages/chat/session_chat_message_area.dart \
        client/test/pages/chat/subagent_preview_controller_test.dart
git commit -m "feat(chat): subagent preview auto-follow state machine"
```

---

### Task 3:全局偏好字段 + cubit setter

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`(构造默认值、fromJson、copyWith 参数与赋值、withAtLeastOneToolVisible、toJson 共 5 处)
- Modify: `client/lib/cubits/layout_cubit.dart`(setter,仿 368-372 行)
- Test: `client/test/models/layout_preferences_default_test.dart`

**Interfaces:**
- Consumes: 无新依赖
- Produces: `LayoutPreferences.autoOpenSubagentPreview`(bool,默认 false)、`LayoutPreferences.copyWith(autoOpenSubagentPreview:)`、`LayoutCubit.setAutoOpenSubagentPreview(bool value) -> Future<void>`

- [ ] **Step 1:写失败测试**

在 `client/test/models/layout_preferences_default_test.dart` 末尾追加:

```dart
  test('autoOpenSubagentPreview defaults false and round-trips', () {
    expect(const LayoutPreferences().autoOpenSubagentPreview, isFalse);
    expect(
      LayoutPreferences.fromJson(const {}).autoOpenSubagentPreview,
      isFalse,
    );
    final parsed = LayoutPreferences.fromJson(const {
      'autoOpenSubagentPreview': true,
    });
    expect(parsed.autoOpenSubagentPreview, isTrue);
    expect(parsed.toJson()['autoOpenSubagentPreview'], isTrue);
    final restored = LayoutPreferences.fromJson(
      const LayoutPreferences(autoOpenSubagentPreview: true).toJson(),
    );
    expect(restored.autoOpenSubagentPreview, isTrue);
  });
```

- [ ] **Step 2:运行测试确认失败**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart`
Expected: 编译失败(`autoOpenSubagentPreview` 未定义)。

- [ ] **Step 3:实现字段**

`client/lib/models/layout_preferences.dart` 五处改动(每处都紧跟 `cotExpandToolsOnOpen` 相关行):

1. 构造参数(第 74 行附近):
```dart
    this.cotExpandToolsOnOpen = false,
    this.autoOpenSubagentPreview = false,
```
2. fromJson(第 159-160 行附近,`cotExpandToolsOnOpen:` 之后):
```dart
      autoOpenSubagentPreview:
          json['autoOpenSubagentPreview'] as bool? ?? false,
```
3. copyWith 参数(第 306 行附近):
```dart
    bool? autoOpenSubagentPreview,
```
4. copyWith 赋值(第 383 行附近):
```dart
      autoOpenSubagentPreview:
          autoOpenSubagentPreview ?? this.autoOpenSubagentPreview,
```
5. withAtLeastOneToolVisible 构造(第 438 行附近):
```dart
      cotExpandToolsOnOpen: cotExpandToolsOnOpen,
      autoOpenSubagentPreview: autoOpenSubagentPreview,
```
6. toJson(第 487 行附近):
```dart
      'autoOpenSubagentPreview': autoOpenSubagentPreview,
```

- [ ] **Step 4:实现 cubit setter**

`client/lib/cubits/layout_cubit.dart` 在 `setCotExpandToolsOnOpen`(372 行)后追加:

```dart
  Future<void> setAutoOpenSubagentPreview(bool value) =>
      _save(state.preferences.copyWith(autoOpenSubagentPreview: value));
```

- [ ] **Step 5:运行测试确认通过**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart`
Expected: 全部 PASS。

- [ ] **Step 6:Commit**

```bash
git add client/lib/models/layout_preferences.dart \
        client/lib/cubits/layout_cubit.dart \
        client/test/models/layout_preferences_default_test.dart
git commit -m "feat(settings): autoOpenSubagentPreview preference + cubit setter"
```

---

### Task 4:配置页开关 + l10n

**Files:**
- Modify: `client/lib/pages/config/layout_appearance_in_layout_section.dart`(在 259 行 `cotExpandToolsOnOpen` 行之后插入新 TpPreferenceRow)
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`
- 生成:`cd client && flutter gen-l10n`(重新生成 `lib/l10n/app_localizations*.dart`)

**Interfaces:**
- Consumes: `LayoutPreferences.autoOpenSubagentPreview`、`LayoutCubit.setAutoOpenSubagentPreview`(Task 3)
- Produces: l10n getters `autoOpenSubagentPreviewTitle` / `autoOpenSubagentPreviewDescription`

- [ ] **Step 1:l10n 文案**

`app_en.arb` 追加(找 `cotExpandToolsOnOpenDescription` 条目后):

```json
  "autoOpenSubagentPreviewTitle": "Auto-open subagent preview",
  "autoOpenSubagentPreviewDescription": "When a subagent starts running, open its preview automatically and follow it live. Press Back to stop following for this session."
```

`app_zh.arb` 追加:

```json
  "autoOpenSubagentPreviewTitle": "自动打开子会话预览",
  "autoOpenSubagentPreviewDescription": "子 agent 开始运行时自动弹出预览并实时跟随;按返回后停止本会话的跟随。"
```

- [ ] **Step 2:生成 l10n**

Run: `cd client && flutter gen-l10n`
Expected: `lib/l10n/app_localizations*.dart` 出现新 getter(无报错)。

- [ ] **Step 3:配置页 UI**

`client/lib/pages/config/layout_appearance_in_layout_section.dart` 在 258-259 行(`cotExpandToolsOnOpen` 的 `TpPreferenceRow` 结束后、`thinkingProcessFoldSectionTitle` 之前)插入:

```dart
                TpPreferenceRow(
                  title: l10n.autoOpenSubagentPreviewTitle,
                  subtitle: l10n.autoOpenSubagentPreviewDescription,
                  trailing: Switch(
                    value: context.select<LayoutCubit, bool>(
                      (c) => c.state.preferences.autoOpenSubagentPreview,
                    ),
                    onChanged: controller.setAutoOpenSubagentPreview,
                  ),
                  showDividerBelow: true,
                ),
```

- [ ] **Step 4:编译验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增错误。

- [ ] **Step 5:Commit**

```bash
git add client/lib/pages/config/layout_appearance_in_layout_section.dart \
        client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/lib/l10n/app_localizations.dart \
        client/lib/l10n/app_localizations_en.dart \
        client/lib/l10n/app_localizations_zh.dart
git commit -m "feat(settings): auto-open subagent preview toggle in config UI"
```

---

### Task 5:SessionChatView 接线

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`(import、BlocSelector record、ListenableBuilder 内调用、私有 helper)
- Modify: `client/test/pages/chat/subagent_preview_controller_test.dart`(不改 —— 无新测试;接线由 analyze + 手动验证覆盖)

**Interfaces:**
- Consumes: `SubagentPreviewController.computeAutoFollow / autoOpen / popAndStopFollow`(Task 2)、`historyCap.subagentToolNames`(现有)、`AiHistorySeat.loadedMessages`(现有)、`prefs.autoOpenSubagentPreview`(Task 3)
- Produces: 无新公开 API

- [ ] **Step 1:补 import**

`client/lib/pages/chat/session_chat_view.dart` 顶部追加(若无):

```dart
import 'package:ai_message_core/ai_message_core.dart';
```

(提供 `AiToolCallPart` / `AiToolCallStatus`。若已由 `ai_message_ui.dart` 导出且可用,可省略。)

- [ ] **Step 2:BlocSelector record 增加偏好**

`session_chat_view.dart:1035-1050` 的 `BlocSelector<LayoutCubit, LayoutState, ({...})>` 的 record 加一个字段:

```dart
                      ({
                        bool expandReasoning,
                        bool expandTools,
                        bool autoOpenSubagentPreview,
                        ContentDisplayMode userMessageMode,
                        ContentDisplayMode chatCodeBlockMode,
                      })
```
selector 加一行:
```dart
                      autoOpenSubagentPreview:
                          s.preferences.autoOpenSubagentPreview,
```

- [ ] **Step 3:ListenableBuilder 内调用 computeAutoFollow + post-frame apply**

在 `session_chat_view.dart:1124`(`_subagentPreview.pruneToAvailable(...)` 之后)插入:

```dart
                                    final pendingAuto = _subagentPreview
                                        .computeAutoFollow(
                                          prefEnabled:
                                              prefs.autoOpenSubagentPreview,
                                          runningIds: _runningSubagentIds(
                                            historySeat,
                                            historyCap,
                                          ),
                                          availableIds: historySeat
                                              .subagentAttachments
                                              .keys
                                              .toSet(),
                                        );
                                    if (pendingAuto != null) {
                                      final id = pendingAuto;
                                      // Deferred: never notify inside build.
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (!mounted) return;
                                        _subagentPreview.autoOpen(id);
                                      });
                                    }
```

- [ ] **Step 4:私有 helper**

在 `session_chat_view.dart` 文件末尾(class 外)追加:

```dart
/// Subagent tool calls still in flight (newest-first), for auto-follow.
/// Only ids whose attachment is inflated can be opened; [computeAutoFollow]
/// re-checks against the attachment index.
List<String> _runningSubagentIds(
  AiHistorySeat seat,
  AiHistoryCapability? cap,
) {
  if (cap == null) return const [];
  final names = cap.subagentToolNames;
  final out = <String>[];
  final messages = seat.loadedMessages;
  for (var i = messages.length - 1; i >= 0; i--) {
    for (final part in messages[i].parts) {
      if (part is! AiToolCallPart) continue;
      if (part.status != AiToolCallStatus.incomplete) continue;
      if (!names.contains(part.toolName.trim().toLowerCase())) continue;
      final id = part.toolCallId.trim();
      if (id.isNotEmpty) out.add(id);
    }
  }
  return out;
}
```

需要的 import:`AiHistorySeat` 来自 `../../cubits/ai_history_cubit.dart`(该文件已 export seat 类 —— 若未 export,改为 import `../../cubits/ai_history_seat.dart`);`AiHistoryCapability` 已 import(line 35)。

- [ ] **Step 5:编译 + 相关测试验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Run: `cd client && flutter test test/pages/chat/subagent_preview_controller_test.dart test/models/layout_preferences_default_test.dart test/services/cli/registry/capabilities/history/opencode_sqlite_worker_pool_test.dart`
Expected: analyze 无新增错误;三组测试全部 PASS。

- [ ] **Step 6:Commit**

```bash
git add client/lib/pages/chat/session_chat_view.dart
git commit -m "feat(chat): wire auto-follow subagent preview into session chat"
```

---

### Task 6:全量验证

**Files:** 无代码改动。

- [ ] **Step 1:全量静态检查 + 测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze 干净;全部测试 PASS。

- [ ] **Step 2:手工验收清单**

1. opencode 会话首次启动,发消息触发 `task` 子 agent → 聊天页保持父会话内容,不再"跳转"到子会话。
2. 设置默认关闭时,子 agent 出现不自动弹预览;点击 task 气泡标签手动打开,预览有返回箭头,返回正常。
3. 开启"自动打开子会话预览"后:子 agent 出现自动弹预览并实时跟随;按返回 → 回到父会话;该会话后续子 agent 不再自动弹。
4. 切换会话/标签页后再回来:跟随状态已重置(开关仍开启时,新会话第一个子 agent 重新自动弹)。
5. 子 agent 运行中关闭开关:不再自动弹;已打开的预览保留。

- [ ] **Step 3:Commit(如有剩余改动)**

```bash
git status
git add -A
git commit -m "chore: subagent auto-follow verification fixes"
```
(若无改动则跳过。)

---

## 自审记录

- **Spec 覆盖**:Section 1(座位翻转修复)→ Task 1;Section 2(跟随状态机)→ Task 2;Section 3a(偏好字段)→ Task 3;3b(配置页+l10n)→ Task 4;3c/3d(接线+会话重置)→ Task 5(clear 重置已在 Task 2 的 `clear()` 内实现);Section 4(测试)→ 各任务内。
- **偏差说明**:spec 的 `maybeAutoFollow` 拆为纯函数 `computeAutoFollow` + post-frame `autoOpen`,避免 build 期 `notifyListeners`(spec 的行为契约不变);`pop()` 更名为 `popAndStopFollow()`(唯一调用点已同步)。
- **类型一致性**:`computeAutoFollow({required bool prefEnabled, required List<String> runningIds, required Set<String> availableIds})` 在 Task 2 定义、Task 5 使用,签名一致;`prefs.autoOpenSubagentPreview` 在 Task 3 定义、Task 4/5 使用一致。
