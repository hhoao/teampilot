# MCP 添加/编辑 Dialog 表单 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 MCP「添加」「编辑」从整页路由（`/mcp/add`、`/mcp/edit/:serverId`）改为模态 dialog 表单，完全对齐 hook 的 `showHookEditorDialog` 模式。

**Architecture:** 新建 `mcp_editor_dialog.dart`（`showMcpEditorDialog` + `McpEditorDialog`，`TpDialog` + `TpForm` + `TpDialogPinnedLayout`，保存走 `McpCubit.upsert`）；`mcp_management_page.dart` 的 Add/Edit 回调改为打开 dialog；删除整页表单 `mcp_form_nav_page.dart` / `mcp_form_page.dart` 及两个路由；清理 `mcp_routes.dart`、`android_shell_chrome.dart` 中的 form 路径分支。

**Tech Stack:** Flutter, flutter_bloc, shared_ui（TpDialog / TpForm / TpFormField / TpTextarea / TpDialogPinnedLayout / TpDialogActions）, go_router, flutter_test。

## Global Constraints

- 复用现有 l10n key（`mcpForm*`、`mcpAddTitle`、`mcpEdit`、`mcpFormRequiredFields`、`cancel`、`save`、`mcpFormSubmitAdd`），**不新增 l10n 文案**。
- 保存路径不变：`McpCubit.upsert(record)` → `McpRepository.upsert` → `McpCatalogService`（`<teampilotRoot>/mcp/mcp_servers.json`）。
- 表单遵循 app 标准样式：label 走 `TpFormFieldLayout`（不复用 `InputDecoration.labelText`）；选择器/表单组件一律用 shared_ui `Tp*`。
- `McpServerValidator.validateName` **拒绝含空格的名字**（`name must not contain spaces`）——测试数据不得用带空格名字。
- 工作区/team-config 的 MCP「Manage」跳转不改（仍去 `/mcp/installed`）。
- 不重构 JSON 为结构化字段；metadata 折叠交互保留。
- 验证命令：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。
- 遵循 spec：`docs/superpowers/specs/2026-08-15-mcp-editor-dialog-design.md`。

---

### Task 1: 新建 `mcp_editor_dialog.dart` + 对话框测试（TDD）

**Files:**
- Test: `client/test/pages/mcp/mcp_editor_dialog_test.dart`（新建）
- Create: `client/lib/pages/mcp/mcp_editor_dialog.dart`

**Interfaces:**
- Produces: `Future<bool?> showMcpEditorDialog(BuildContext context, {required McpCubit cubit, McpServer? existing})` — 返回 `true`=保存成功；`false`/`null`=取消。
- Produces: `McpEditorDialog`（内部 widget，不对外）。
- Consumes: `McpCubit.upsert(McpServer) → Future<bool>`；`McpCubit.state.errorMessage`；`McpServer`/`parseMcpTags`（`client/lib/models/mcp_server.dart`）；`appMonoTextStyle`（`client/lib/theme/app_fonts.dart`）；`tpTextareaHeightForLines`（shared_ui）；`AppToast.show`（`client/lib/widgets/app_toast/app_toast.dart`）。

- [ ] **Step 1: 写失败的测试** `client/test/pages/mcp/mcp_editor_dialog_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/mcp_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/pages/mcp/mcp_editor_dialog.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/mcp/mcp_catalog_service.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late McpRepository repository;
  late McpCubit cubit;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = McpRepository(
      catalog: McpCatalogService(
        catalogPath: '/root/mcp/mcp_servers.json',
        fs: fs,
      ),
    );
    cubit = McpCubit(repository);
  });

  tearDown(() => cubit.close());

  Future<void> pumpHost(
    WidgetTester tester, {
    McpServer? existing,
  }) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
          child: BlocProvider<McpCubit>.value(
            value: cubit,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showMcpEditorDialog(
                    context,
                    cubit: cubit,
                    existing: existing,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('save creates the server and closes the dialog', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mcp-id')), 'fetch');
    await tester.enterText(find.byKey(const Key('mcp-name')), 'Fetch');
    await tester.tap(find.byKey(const Key('mcp-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-save')), findsNothing);
    final saved = await repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.id, 'fetch');
    expect(saved.single.name, 'Fetch');
    expect(saved.single.server['type'], 'stdio');
  });

  testWidgets('required fields block save', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('mcp-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-save')), findsOneWidget);
    expect(find.text('MCP ID and display name are required.'), findsWidgets);
    expect(await repository.loadAll(), isEmpty);
  });

  testWidgets('invalid JSON keeps the dialog open', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('mcp-id')), 'fetch');
    await tester.enterText(find.byKey(const Key('mcp-name')), 'Fetch');
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('mcp-json')),
        matching: find.byType(TextField),
      ),
      '{oops',
    );
    await tester.tap(find.byKey(const Key('mcp-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-save')), findsOneWidget);
    expect(await repository.loadAll(), isEmpty);
  });

  testWidgets('cancel closes the dialog without saving', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mcp-id')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mcp-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsNothing);
    expect(await repository.loadAll(), isEmpty);
  });

  testWidgets('edit pre-fills fields and disables the id', (tester) async {
    final existing = McpServer(
      id: 'fetch',
      name: 'Fetch',
      server: const {
        'type': 'stdio',
        'command': 'uvx',
        'args': ['mcp-server-fetch'],
      },
      description: 'Fetch server',
      tags: const ['utility'],
    );
    await repository.upsert(existing);

    await pumpHost(tester, existing: existing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mcp-id')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mcp-name')))
          .controller!
          .text,
      'Fetch',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mcp-desc')))
          .controller!
          .text,
      'Fetch server',
    );

    await tester.tap(find.byKey(const Key('mcp-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-save')), findsNothing);
    final saved = await repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.id, 'fetch');
    expect(saved.single.tags, ['utility']);
  });
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
cd client && flutter test test/pages/mcp/mcp_editor_dialog_test.dart
```

Expected: 编译失败 / `showMcpEditorDialog not defined`。

- [ ] **Step 3: 实现 `client/lib/pages/mcp/mcp_editor_dialog.dart`**

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/app_toast/app_toast.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../theme/app_fonts.dart';

/// 打开新建/编辑 MCP server 对话框。返回 `true` = 保存成功；`false`/`null` = 取消。
Future<bool?> showMcpEditorDialog(
  BuildContext context, {
  required McpCubit cubit,
  McpServer? existing,
}) {
  return showTpDialog<bool>(
    context: context,
    builder: (_) => McpEditorDialog(cubit: cubit, existing: existing),
  );
}

/// 新建/编辑 MCP server 的对话框表单：id、name、可展开 metadata
/// （description/tags/homepage/docs）、server JSON；保存走 [McpCubit.upsert]。
class McpEditorDialog extends StatefulWidget {
  const McpEditorDialog({
    required this.cubit,
    this.existing,
    super.key,
  });

  final McpCubit cubit;

  /// 编辑目标；null = 新建。
  final McpServer? existing;

  @override
  State<McpEditorDialog> createState() => _McpEditorDialogState();
}

class _McpEditorDialogState extends State<McpEditorDialog> {
  final _formKey = GlobalKey<TpFormState>();

  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _tagsCtrl;
  late final TextEditingController _homepageCtrl;
  late final TextEditingController _docsCtrl;
  late final TextEditingController _jsonCtrl;

  bool _metadataExpanded = false;
  String? _jsonError;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _idCtrl = TextEditingController(text: existing?.id ?? '');
    _nameCtrl = TextEditingController(text: existing?.name ?? '');
    _descriptionCtrl = TextEditingController(text: existing?.description ?? '');
    _tagsCtrl = TextEditingController(text: existing?.tags.join(', ') ?? '');
    _homepageCtrl = TextEditingController(text: existing?.homepage ?? '');
    _docsCtrl = TextEditingController(text: existing?.docs ?? '');
    _jsonCtrl = TextEditingController(
      text: existing != null
          ? const JsonEncoder.withIndent('  ').convert(existing.server)
          : const JsonEncoder.withIndent('  ').convert({
              'type': 'stdio',
              'command': 'uvx',
              'args': ['mcp-server-fetch'],
            }),
    );
    _metadataExpanded = existing?.hasMetadata ?? false;
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _tagsCtrl.dispose();
    _homepageCtrl.dispose();
    _docsCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _formatJson() {
    try {
      final decoded = jsonDecode(_jsonCtrl.text);
      _jsonCtrl.text = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() => _jsonError = null);
    } catch (e) {
      setState(() => _jsonError = e.toString());
    }
  }

  Map<String, Object?>? _parseServerJson() {
    try {
      final decoded = jsonDecode(_jsonCtrl.text);
      if (decoded is! Map) {
        setState(() => _jsonError = 'JSON must be an object');
        return null;
      }
      setState(() => _jsonError = null);
      return decoded.cast<String, Object?>();
    } catch (e) {
      setState(() => _jsonError = e.toString());
      return null;
    }
  }

  Widget _textField({
    required Key fieldKey,
    required TextEditingController controller,
    required Widget label,
    String? hint,
    String? Function(String?)? validator,
    bool enabled = true,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TpFormField<String>(
      initialValue: controller.text,
      label: label,
      validator: validator,
      builder: (state) {
        return TextField(
          key: fieldKey,
          controller: controller,
          focusNode: state.focusNode,
          enabled: enabled,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: state.didChange,
          decoration: InputDecoration(
            hintText: hint,
            errorText: state.hasError ? '' : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final server = _parseServerJson();
    if (server == null) return;

    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = widget.existing;
    final record = McpServer(
      id: _idCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      server: server,
      description: _descriptionCtrl.text.trim(),
      tags: parseMcpTags(_tagsCtrl.text),
      homepage: _homepageCtrl.text.trim(),
      docs: _docsCtrl.text.trim(),
      enabled: existing?.enabled ?? true,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      source: existing?.source ?? McpServerSource.catalog,
      importedFrom: existing?.importedFrom,
    );

    final ok = await widget.cubit.upsert(record);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    final message = widget.cubit.state.errorMessage;
    if (message != null) {
      AppToast.show(context, message: message, variant: TpToastVariant.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return TpDialog(
      maxWidth: 560,
      maxHeight: 680,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(
          title: _isEditing ? l10n.mcpEdit : l10n.mcpAddTitle,
        ),
        body: TpForm(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _textField(
                fieldKey: const Key('mcp-id'),
                controller: _idCtrl,
                enabled: !_isEditing,
                label: Text(l10n.mcpFormIdLabel),
                hint: 'my-mcp-server',
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.mcpFormRequiredFields
                    : null,
              ),
              const SizedBox(height: 12),
              _textField(
                fieldKey: const Key('mcp-name'),
                controller: _nameCtrl,
                label: Text(l10n.mcpFormDisplayNameLabel),
                hint: l10n.mcpFormDisplayNameHint,
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.mcpFormRequiredFields
                    : null,
              ),
              const SizedBox(height: 8),
              TpHover(
                onTap: () =>
                    setState(() => _metadataExpanded = !_metadataExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.mcpFormMetadata,
                        style: TpTextStyles.of(context).mdSemiboldTightSnug,
                      ),
                      const Spacer(),
                      Icon(
                        _metadataExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                    ],
                  ),
                ),
              ),
              if (_metadataExpanded) ...[
                const SizedBox(height: 8),
                _textField(
                  fieldKey: const Key('mcp-desc'),
                  controller: _descriptionCtrl,
                  label: Text(l10n.mcpFormDescriptionLabel),
                  hint: l10n.mcpFormDescriptionHint,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _textField(
                  fieldKey: const Key('mcp-tags'),
                  controller: _tagsCtrl,
                  label: Text(l10n.mcpFormTagsLabel),
                  hint: l10n.mcpFormTagsHint,
                ),
                const SizedBox(height: 12),
                _textField(
                  fieldKey: const Key('mcp-homepage'),
                  controller: _homepageCtrl,
                  keyboardType: TextInputType.url,
                  label: Text(l10n.mcpFormHomepageLabel),
                  hint: 'https://example.com',
                ),
                const SizedBox(height: 12),
                _textField(
                  fieldKey: const Key('mcp-docs'),
                  controller: _docsCtrl,
                  keyboardType: TextInputType.url,
                  label: Text(l10n.mcpFormDocsLabel),
                  hint: 'https://example.com/docs',
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    l10n.mcpFormJsonLabel,
                    style: TpTextStyles.of(context).mdSemiboldTightSnug,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _formatJson,
                    child: Text(l10n.mcpFormFormatJson),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final mono = appMonoTextStyle(context, height: 1.45);
                  return TpTextarea(
                    key: const Key('mcp-json'),
                    controller: _jsonCtrl,
                    minHeight: tpTextareaHeightForLines(mono, lines: 8),
                    maxHeight: tpTextareaHeightForLines(mono, lines: 12),
                    style: mono,
                    decoration: InputDecoration(
                      errorText: _jsonError,
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        footer: TpDialogActions(
          children: [
            TextButton(
              key: const Key('mcp-cancel'),
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const Key('mcp-save'),
              onPressed: _saving ? null : _save,
              child: Text(_isEditing ? l10n.save : l10n.mcpFormSubmitAdd),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试，确认全部通过**

```bash
cd client && flutter test test/pages/mcp/mcp_editor_dialog_test.dart
```

Expected: 5 个测试全绿。

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/mcp/mcp_editor_dialog.dart client/test/pages/mcp/mcp_editor_dialog_test.dart
git commit -m "feat(mcp): add/edit server as dialog form"
```

---

### Task 2: 重接 `mcp_management_page.dart` 打开 dialog + 页面级测试

**Files:**
- Modify: `client/lib/pages/mcp/mcp_management_page.dart`（54-64、107-134、256-257 行）
- Test: `client/test/pages/mcp/mcp_management_page_test.dart`（新建）

**Interfaces:**
- Consumes: `showMcpEditorDialog`（Task 1）。
- Produces: `_openAdd()` / `_openEdit(McpServer server)`（`_McpManagementPageState` 私有方法）—— `_McpInstalledSectionState` 之外无外部依赖。

- [ ] **Step 1: 修改 `mcp_management_page.dart`**

删除顶层 `navigateMcpAdd` / `navigateMcpEdit`（54-60 行），删除 `import 'mcp_routes.dart';`（20 行）。

在 `_McpManagementPageState` 中新增：

```dart
  Future<void> _openAdd() async {
    await showMcpEditorDialog(context, cubit: context.read<McpCubit>());
  }

  Future<void> _openEdit(McpServer server) async {
    await showMcpEditorDialog(
      context,
      cubit: context.read<McpCubit>(),
      existing: server,
    );
  }
```

替换调用点：

- `_addFromListing`（113 行）`navigateMcpEdit(context, existing.first);` → `await _openEdit(existing.first);`
- `_addFromListing`（132 行，upsert 失败分支）`navigateMcpEdit(context, draft);` → `await _openEdit(draft);`
- `onAdd: () => navigateMcpAdd(context),`（256 行）→ `onAdd: _openAdd,`
- `onEdit: (s) => navigateMcpEdit(context, s),`（257 行）→ `onEdit: _openEdit,`

新增 import：`import 'mcp_editor_dialog.dart';`

- [ ] **Step 2: 新建页面级测试 `client/test/pages/mcp/mcp_management_page_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/mcp_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/mcp_server.dart';
import 'package:teampilot/pages/mcp/mcp_management_page.dart';
import 'package:teampilot/repositories/mcp_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/mcp/mcp_catalog_service.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late McpRepository repository;
  late McpCubit cubit;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = McpRepository(
      catalog: McpCatalogService(
        catalogPath: '/root/mcp/mcp_servers.json',
        fs: fs,
      ),
    );
    cubit = McpCubit(repository);
  });

  tearDown(() => cubit.close());

  Future<void> pumpListPage(WidgetTester tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
          child: BlocProvider<McpCubit>.value(
            value: cubit,
            child: const Scaffold(
              body: McpManagementPage(section: McpSection.installed),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Add MCP opens the editor dialog and cancel exits', (
    tester,
  ) async {
    await pumpListPage(tester);

    await tester.tap(find.text('Add MCP'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsOneWidget);

    await tester.tap(find.byKey(const Key('mcp-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsNothing);
  });

  testWidgets('edit row opens the dialog pre-filled', (tester) async {
    await cubit.upsert(
      const McpServer(
        id: 'fetch',
        name: 'Fetch',
        server: {'type': 'stdio', 'command': 'uvx'},
      ),
    );
    await pumpListPage(tester);

    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mcp-id')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('mcp-name')))
          .controller!
          .text,
      'Fetch',
    );
  });
}
```

- [ ] **Step 3: 运行测试，确认通过**

```bash
cd client && flutter test test/pages/mcp/mcp_management_page_test.dart
```

Expected: 2 个测试全绿（页面能 pump、点击 Add MCP 弹 dialog、点编辑行弹 dialog 且预填）。

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/mcp/mcp_management_page.dart client/test/pages/mcp/mcp_management_page_test.dart
git commit -m "refactor(mcp): open editor dialog from management page"
```

---

### Task 3: 删除整页表单、路由与 chrome 分支

**Files:**
- Delete: `client/lib/pages/mcp/mcp_form_nav_page.dart`
- Delete: `client/lib/pages/mcp/mcp_form_page.dart`
- Delete: `client/lib/pages/mcp/mcp_routes.dart`
- Modify: `client/lib/router/app_router.dart`（437-451 行 + 15 行 import）
- Modify: `client/lib/router/android_shell_chrome.dart`（8 行 import、31 行、140-142 行）
- Modify: `client/test/router/android_shell_chrome_test.dart`（33-36 行）

- [ ] **Step 1: 删除路由**

`client/lib/router/app_router.dart`：

- 删除 `import '../pages/mcp/mcp_form_nav_page.dart';`（15 行）；
- 删除 `/mcp/add` 与 `/mcp/edit/:serverId` 两个 `GoRoute`（437-451 行）。

- [ ] **Step 2: 清理 `android_shell_chrome.dart`**

- 删除 `import '../pages/mcp/mcp_routes.dart';`（8 行）；
- 删除 `isLibrarySectionPath` 中 `if (mcpPathIsForm(path)) return false;`（31 行）；
- 删除 `pop` 中 `if (mcpPathIsForm(path)) { context.go(mcpInstalledRoute); return; }` 分支（140-142 行）。

- [ ] **Step 3: 删除文件**

```bash
rm client/lib/pages/mcp/mcp_form_nav_page.dart \
   client/lib/pages/mcp/mcp_form_page.dart \
   client/lib/pages/mcp/mcp_routes.dart
```

- [ ] **Step 4: 更新 `client/test/router/android_shell_chrome_test.dart`**

删除 33-36 行的 `excludes MCP form paths` 测试组（form 路由已不存在）。

- [ ] **Step 5: 静态检查 + 测试**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 无新增告警（尤其确认没有残留对 `McpFormNavPage` / `mcp_form_page.dart` / `mcp_routes.dart` 的引用）。

```bash
cd client && flutter test --exclude-tags integration test/router/android_shell_chrome_test.dart test/pages/mcp
```

Expected: 全绿。

- [ ] **Step 6: Commit**

```bash
git add -A client/lib client/test
git commit -m "refactor(mcp): remove fullscreen add/edit routes and form pages"
```

---

### Task 4: 全量验证

- [ ] **Step 1: analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 2: 全量测试**

```bash
cd client && flutter test --exclude-tags integration
```

- [ ] **Step 3: 人工验收（桌面端）**

1. `/mcp/installed` 点「Add MCP」→ 弹出 dialog，不跳整页；
2. 安装列表某行点编辑 → 弹 dialog，id 字段禁用、其余预填；
3. Discovery 列表点条目（已存在/失败分支）→ 弹编辑 dialog；
4. 取消 / 保存成功均关闭 dialog；保存失败留在 dialog 且 AppToast 报错；
5. Android 返回键不再处理 `/mcp/add`、`/mcp/edit/*`（路由已删除）。
