# Expert Editor Dep Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compact the create/edit expert dialog by moving skills/plugins/MCP selection into nested configure dialogs; main dialog shows count (including `0`) + Configure per category.

**Architecture:** Keep `ExpertEditorDialog` for persona fields and `_selected*Ids`. Replace inline catalog rows with three compact dep rows. Each Configure opens `showExpertEditorDepPickerDialog`, which returns an updated `Set<String>?` (`null` = Cancel). Save path still uses `resolveExpertEditorDeps` unchanged.

**Tech Stack:** Flutter, `flutter_bloc`, existing `AppDialog` / `TeamSkillRow` / `TeamPluginRow` / `TeamMcpRow`, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-07-14-expert-editor-dep-picker-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ generated) | Picker titles + Done; reuse `configure` for the button |
| `client/lib/pages/expert_hub/expert_editor_dep_picker_dialog.dart` | **New** — nested picker for one category |
| `client/lib/pages/expert_hub/expert_editor_dialog.dart` | Compact dep rows; open picker; drop inline lists |
| `client/lib/pages/expert_hub/expert_editor_deps.dart` | Unchanged |
| `client/test/pages/expert_hub/expert_editor_dialog_test.dart` | Compact UI + picker Done/Cancel + orphan count |

---

### Task 1: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Generated: `app_localizations*.dart` (via `flutter gen-l10n`)

- [ ] **Step 1: Add ARB keys** (near existing `expertEditor*` keys)

English (`app_en.arb`):

```json
"expertEditorConfigureSkillsTitle": "Configure skills",
"expertEditorConfigurePluginsTitle": "Configure plugins",
"expertEditorConfigureMcpTitle": "Configure MCP",
"expertEditorDepPickerDone": "Done",
"expertEditorDepsHint": "Configure dependencies from your installed library. Items without a portable source are skipped on save."
```

Chinese (`app_zh.arb`):

```json
"expertEditorConfigureSkillsTitle": "配置技能",
"expertEditorConfigurePluginsTitle": "配置插件",
"expertEditorConfigureMcpTitle": "配置 MCP",
"expertEditorDepPickerDone": "完成",
"expertEditorDepsHint": "从本机已安装库中配置依赖。没有可移植来源的项会在保存时跳过。"
```

Reuse existing `configure` for the Configure button label (do not add a duplicate).

Also update `expertEditorDepsHint` values as above (replace “勾选/Select” wording to match the new flow).

- [ ] **Step 2: Regenerate l10n**

Run from `client/`:

```bash
flutter gen-l10n
```

Expected: new getters on `AppLocalizations` / `app_localizations_en.dart` / `app_localizations_zh.dart`.

If the project also regenerates warmup glyphs after ARB edits:

```bash
dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/
git commit -m "$(cat <<'EOF'
chore(l10n): expert editor dep picker strings

EOF
)"
```

---

### Task 2: Nested dep picker dialog

**Files:**
- Create: `client/lib/pages/expert_hub/expert_editor_dep_picker_dialog.dart`

Implement the picker first; cover behavior through `expert_editor_dialog_test.dart` in Task 3–4 (integration via the main dialog). No separate picker test file required.

- [ ] **Step 1: Create picker API + widget**

Create `client/lib/pages/expert_hub/expert_editor_dep_picker_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_text_styles.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../models/mcp_server.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../widgets/app_dialog.dart';
import '../team_config/team_config_mcp_section.dart';
import '../team_config/team_config_plugins_section.dart';
import '../team_config/team_config_skills_section.dart';

enum ExpertEditorDepCategory { skills, plugins, mcp }

/// Returns updated selection on Done, or `null` if Cancel / dismissed.
Future<Set<String>?> showExpertEditorDepPickerDialog(
  BuildContext context, {
  required ExpertEditorDepCategory category,
  required Set<String> selectedIds,
  List<Skill> skills = const [],
  List<Plugin> plugins = const [],
  List<McpServer> mcps = const [],
  List<SkillDependencyRef> existingSkillDeps = const [],
  List<PluginDependencyRef> existingPluginDeps = const [],
  List<McpDependencyRef> existingMcpDeps = const [],
}) {
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => ExpertEditorDepPickerDialog(
      category: category,
      initialSelectedIds: selectedIds,
      skills: skills,
      plugins: plugins,
      mcps: mcps,
      existingSkillDeps: existingSkillDeps,
      existingPluginDeps: existingPluginDeps,
      existingMcpDeps: existingMcpDeps,
    ),
  );
}

class ExpertEditorDepPickerDialog extends StatefulWidget {
  const ExpertEditorDepPickerDialog({
    super.key,
    required this.category,
    required this.initialSelectedIds,
    this.skills = const [],
    this.plugins = const [],
    this.mcps = const [],
    this.existingSkillDeps = const [],
    this.existingPluginDeps = const [],
    this.existingMcpDeps = const [],
  });

  final ExpertEditorDepCategory category;
  final Set<String> initialSelectedIds;
  final List<Skill> skills;
  final List<Plugin> plugins;
  final List<McpServer> mcps;
  final List<SkillDependencyRef> existingSkillDeps;
  final List<PluginDependencyRef> existingPluginDeps;
  final List<McpDependencyRef> existingMcpDeps;

  @override
  State<ExpertEditorDepPickerDialog> createState() =>
      _ExpertEditorDepPickerDialogState();
}

class _ExpertEditorDepPickerDialogState
    extends State<ExpertEditorDepPickerDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.of(widget.initialSelectedIds);
  }

  String _title(BuildContext context) {
    final l10n = context.l10n;
    return switch (widget.category) {
      ExpertEditorDepCategory.skills => l10n.expertEditorConfigureSkillsTitle,
      ExpertEditorDepCategory.plugins =>
        l10n.expertEditorConfigurePluginsTitle,
      ExpertEditorDepCategory.mcp => l10n.expertEditorConfigureMcpTitle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);

    // Copy orphan + catalog row logic from current expert_editor_dialog.dart
    // (~286–466) for all three categories:
    //   ids = catalog id set
    //   orphans = existing*Deps where selected && !ids.contains
    //   empty → skillsNoInstalled / pluginsNoInstalled / mcpNoInstalled
    //   else Team*Row with Key('expert-editor-skill|plugin|mcp-${id}')

    return AppDialog(
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: _title(context)),
          const SizedBox(height: 16),
          // orphan list (move _OrphanDepList here or duplicate privately)
          // catalog rows
          AppDialogActions(
            children: [
              TextButton(
                key: const Key('expert-editor-dep-picker-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const Key('expert-editor-dep-picker-done'),
                onPressed: () => Navigator.of(context).pop(
                  Set<String>.of(_selected),
                ),
                child: Text(l10n.expertEditorDepPickerDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

Implement the full body for all three categories (skills / plugins / mcp) — the sketch above is structural. Move `_OrphanDepList` (and optionally `_DepSectionTitle` if unused) out of `expert_editor_dialog.dart` into this file as a private widget so orphans stay removable in the picker.

Keep row keys identical to today (`expert-editor-skill-$id`, `expert-editor-plugin-$id`, `expert-editor-mcp-$id`) so existing test finders still work once the picker is open.

- [ ] **Step 2: Analyze**

```bash
cd client && dart analyze lib/pages/expert_hub/expert_editor_dep_picker_dialog.dart
```

Expected: no errors (may warn until main dialog imports it).

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/expert_hub/expert_editor_dep_picker_dialog.dart
git commit -m "$(cat <<'EOF'
feat(experts): add nested dep picker dialog

EOF
)"
```

---

### Task 3: Compact main dialog + wire picker

**Files:**
- Modify: `client/lib/pages/expert_hub/expert_editor_dialog.dart`
- Modify: `client/test/pages/expert_hub/expert_editor_dialog_test.dart`

- [ ] **Step 1: Write failing tests for compact UI + Done path**

In `expert_editor_dialog_test.dart`, update the existing `toggling portable skill saves skillDeps` test and add:

```dart
testWidgets('main dialog does not inline skill catalog rows', (tester) async {
  _largeSurface(tester);
  final skill = Skill(
    id: 'obra/superpowers:brainstorming',
    name: 'Brainstorming',
    description: '',
    directory: 'skills/brainstorming',
    repoOwner: 'obra',
    repoName: 'superpowers',
    repoBranch: 'main',
    installedAt: 1,
    updatedAt: 1,
  );
  // pump showExpertEditorDialog(..., skills: [skill], plugins: [], mcps: [])
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  expect(find.byKey(Key('expert-editor-skill-${skill.id}')), findsNothing);
  expect(find.byKey(const Key('expert-editor-plugin-p1')), findsNothing);
  expect(find.byKey(const Key('expert-editor-mcp-m1')), findsNothing);
  expect(find.byKey(const Key('expert-editor-configure-skills')), findsOneWidget);
  expect(find.byKey(const Key('expert-editor-skills-count')), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const Key('expert-editor-skills-count')),
      matching: find.text('0'),
    ),
    findsOneWidget,
  );
});

// Plugin/mcp keys above only appear when those rows are built; with empty
// catalogs, findsNothing is correct either way.

testWidgets('configure skills Done updates count and saves skillDeps', (
  tester,
) async {
  // same skill fixture + open dialog
  await tester.tap(find.byKey(const Key('expert-editor-configure-skills')));
  await tester.pumpAndSettle();

  final switchFinder = find.descendant(
    of: find.byKey(Key('expert-editor-skill-${skill.id}')),
    matching: find.byType(Switch),
  );
  await tester.ensureVisible(switchFinder);
  await tester.tap(switchFinder);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('expert-editor-dep-picker-done')));
  await tester.pumpAndSettle();

  expect(
    find.descendant(
      of: find.byKey(const Key('expert-editor-skills-count')),
      matching: find.text('1'),
    ),
    findsOneWidget,
  );

  // enter name+prompt, submit, expect skillDeps length 1 (same as old test)
});

testWidgets('configure skills Cancel leaves selection unchanged', (tester) async {
  // open → configure → toggle skill → Cancel (l10n.cancel)
  // count still 0; submit → skillDeps empty
});
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/pages/expert_hub/expert_editor_dialog_test.dart
```

Expected: FAIL — missing configure keys / catalog still inlined or count widgets absent.

- [ ] **Step 3: Refactor main dialog**

In `expert_editor_dialog.dart`:

1. Import `expert_editor_dep_picker_dialog.dart`.
2. Remove inline `for (final skill in skills) TeamSkillRow...` (and plugins/mcp equivalents) and orphan blocks from the main build.
3. After `expertEditorDepsHint`, render three compact rows:

```dart
_ExpertEditorDepSummaryRow(
  key: const Key('expert-editor-dep-skills'),
  title: l10n.expertEditorSkillsSection,
  countKey: const Key('expert-editor-skills-count'),
  count: _selectedSkillIds.length,
  configureKey: const Key('expert-editor-configure-skills'),
  onConfigure: () => _openDepPicker(ExpertEditorDepCategory.skills),
),
// plugins + mcp analogous keys:
// expert-editor-configure-plugins / expert-editor-plugins-count
// expert-editor-configure-mcp / expert-editor-mcp-count
```

4. Split catalog readers so `watch` stays in `build` only. Keep `_skills` /
   `_plugins` / `_mcps` using `context.watch` for rebuilds when inject lists are
   null. Add read-only helpers for callbacks (or pass lists captured in `build`
   into `onConfigure`):

```dart
List<Skill> _skillsRead(BuildContext context) {
  if (widget.skills != null) return widget.skills!;
  try {
    return context
        .read<SkillCubit>()
        .state
        .installed
        .where((s) => s.enabled)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}
// Same pattern for plugins (PluginCubit.installed) and mcps (enabled servers).
```

5. Implement `_openDepPicker` using **read** helpers (never `watch` from a button):

```dart
Future<void> _openDepPicker(ExpertEditorDepCategory category) async {
  final result = await showExpertEditorDepPickerDialog(
    context,
    category: category,
    selectedIds: switch (category) {
      ExpertEditorDepCategory.skills => _selectedSkillIds,
      ExpertEditorDepCategory.plugins => _selectedPluginIds,
      ExpertEditorDepCategory.mcp => _selectedMcpIds,
    },
    skills: _skillsRead(context),
    plugins: _pluginsRead(context),
    mcps: _mcpsRead(context),
    existingSkillDeps: _existingSkillDeps,
    existingPluginDeps: _existingPluginDeps,
    existingMcpDeps: _existingMcpDeps,
  );
  if (!mounted || result == null) return;
  setState(() {
    switch (category) {
      case ExpertEditorDepCategory.skills:
        _selectedSkillIds = result;
      case ExpertEditorDepCategory.plugins:
        _selectedPluginIds = result;
      case ExpertEditorDepCategory.mcp:
        _selectedMcpIds = result;
    }
  });
}
```

6. Add private `_ExpertEditorDepSummaryRow`:

```dart
class _ExpertEditorDepSummaryRow extends StatelessWidget {
  const _ExpertEditorDepSummaryRow({
    super.key,
    required this.title,
    required this.count,
    required this.countKey,
    required this.configureKey,
    required this.onConfigure,
  });

  final String title;
  final int count;
  final Key countKey;
  final Key configureKey;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(title, style: styles.mdBold),
                const SizedBox(width: 8),
                Text('$count', key: countKey, style: styles.sm),
              ],
            ),
          ),
          TextButton(
            key: configureKey,
            onPressed: onConfigure,
            child: Text(l10n.configure),
          ),
        ],
      ),
    );
  }
}
```

7. Remove unused imports of `TeamSkillRow` etc. from the main dialog if no longer referenced. Keep `_skills` / `_plugins` / `_mcps` (`watch`) only if still needed for rebuilds; prefer `_skillsRead` / `_pluginsRead` / `_mcpsRead` in `_submit` and `_openDepPicker` so callbacks never call `watch`.

8. Drop orphan UI from the main dialog (lives only in the picker now).

- [ ] **Step 4: Run tests — expect PASS** for new + existing create/edit tests

```bash
cd client && flutter test test/pages/expert_hub/expert_editor_dialog_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/expert_hub/expert_editor_dialog.dart \
  client/test/pages/expert_hub/expert_editor_dialog_test.dart
git commit -m "$(cat <<'EOF'
feat(experts): compact expert editor deps with configure picker

EOF
)"
```

---

### Task 4: Orphan count coverage

**Files:**
- Modify: `client/test/pages/expert_hub/expert_editor_dialog_test.dart`

- [ ] **Step 1: Write orphan test**

```dart
testWidgets('orphan skill counts on main; remove in picker updates count', (
  tester,
) async {
  _largeSurface(tester);
  final orphan = const SkillDependencyRef(
    repoOwner: 'missing',
    repoName: 'pack',
    repoBranch: 'main',
    directory: 'skills/gone',
    name: 'Gone Skill',
  );
  // expectedLocalId == 'missing/pack:gone'
  final initial = DiscoverableMember(
    key: 'local/orphan-expert',
    name: 'Orphaned',
    description: '',
    category: '',
    source: ExpertMemberSource.local,
    member: const DiscoverableTeamMember(
      name: 'Orphaned',
      prompt: 'prompt',
    ),
    skillDeps: [orphan],
  );

  // showExpertEditorDialog(..., initial: initial, skills: [], ...)
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  expect(
    find.descendant(
      of: find.byKey(const Key('expert-editor-skills-count')),
      matching: find.text('1'),
    ),
    findsOneWidget,
  );

  await tester.tap(find.byKey(const Key('expert-editor-configure-skills')));
  await tester.pumpAndSettle();

  await tester.tap(find.text(/* l10n.expertEditorOrphanRemove — use finder by button text from AppLocalizations */));
  // Prefer: find.widgetWithText(TextButton, 'Remove') with en locale
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('expert-editor-dep-picker-done')));
  await tester.pumpAndSettle();

  expect(
    find.descendant(
      of: find.byKey(const Key('expert-editor-skills-count')),
      matching: find.text('0'),
    ),
    findsOneWidget,
  );
});
```

Use English locale (default in existing tests) so orphan remove label is `Remove`.

- [ ] **Step 2: Run test — FAIL then fix picker orphan remove if needed**

```bash
cd client && flutter test test/pages/expert_hub/expert_editor_dialog_test.dart
```

- [ ] **Step 3: Commit**

```bash
git add client/test/pages/expert_hub/expert_editor_dialog_test.dart
git commit -m "$(cat <<'EOF'
test(experts): cover orphan dep count in editor picker

EOF
)"
```

---

### Task 5: Verification

- [ ] **Step 1: Analyze + full targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/pages/expert_hub/expert_editor_dialog.dart \
  lib/pages/expert_hub/expert_editor_dep_picker_dialog.dart

cd client && flutter test test/pages/expert_hub/expert_editor_dialog_test.dart
```

Expected: clean analyze for touched files; all tests PASS.

- [ ] **Step 2: Manual smoke (optional)**

1. My Experts → New expert → confirm three rows show `0` + Configure.
2. Configure skills → select one → Done → count `1`.
3. Configure again → Cancel after toggling → count unchanged.
4. Save expert; reopen edit → count restored.

- [ ] **Step 3: Final commit if any leftover fixes**

Only if analyze/tests required small fixes not already committed.

---

## Notes for implementers

- Do **not** change `resolveExpertEditorDeps` or capability-pack merge.
- Do **not** add search/filter in the picker.
- Nested dialogs are intentional (spec approach 1).
- `_selected*Ids` must remain `Set<String>` (mutable via reassignment after Done).
- Main dialog height should shrink substantially; picker owns the long scroll.
