# Unified Home Pane Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace inconsistent home/hub/config pane titles with one `WorkspacePaneHeader` matching 「全部工作区」chrome (xl title → 16 → Divider → 16; subtitle hidden by default; zero header padding).

**Architecture:** New header + shared `WorkspacePaneInsets.page`. Shells take `embedded` so home (which already pads) does not double-inset. Delete `WorkspaceHubTitleBar` and `WorkspaceSectionHeading` with no compat shims. Team identity `HomeTeamHeader` stays untouched.

**Tech Stack:** Flutter/Dart, `shared_ui` (`TpTextStyles`), existing hub shells under `client/lib/widgets/settings/`.

**Spec:** `docs/superpowers/specs/2026-08-01-unified-home-pane-title-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/widgets/settings/workspace_pane_insets.dart` | `WorkspacePaneInsets.page` constant |
| `client/lib/widgets/settings/workspace_pane_header.dart` | `WorkspacePaneHeader` widget |
| `client/test/widgets/settings/workspace_pane_header_test.dart` | Header widget tests |
| `client/lib/widgets/settings/workspace_hub_shell.dart` | Delete TitleBar + SectionHeading; `WorkspaceHubPage` uses new header + inset |
| `client/lib/widgets/settings/workspace_section_host.dart` | Desktop/adaptive shell: PaneHeader + `embedded` |
| `client/test/widgets/settings/workspace_section_host_test.dart` | Expect no subtitle by default; embedded vs route inset |
| `client/lib/pages/home_workspace/home_workspace_page.dart` | Use `WorkspacePaneInsets.page` |
| `client/lib/pages/home_workspace/home_all_workspaces_pane.dart` | Inline title → PaneHeader |
| `client/lib/pages/home_workspace/home_workspace_library_section.dart` | Same + divider rhythm |
| `client/lib/pages/automations/automation_management_page.dart` | Same |
| `client/lib/pages/home_workspace/home_workspace_global_section.dart` | Pass `embedded: true` into hosted pages |
| Skills / Plugins / MCP / Extensions management pages | `embedded` flag → adaptive shell |
| `client/lib/pages/my_teams/my_teams_page.dart` | Header swap; drop extra content H-padding |
| `client/lib/pages/my_experts/my_experts_page.dart` | Same |
| `client/lib/pages/team_hub/team_hub_page.dart` | Header swap |
| `client/lib/pages/expert_hub/expert_hub_page.dart` | Header swap |
| `client/lib/pages/llm_config/llm_config_workspace.dart` | SectionHeading → PaneHeader; drop wrapper padding |
| Config / about / logs / error / workspace_settings | SectionHeading/TitleBar → PaneHeader; drop duplicate `SizedBox(16)` after heading |
| `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart` | Adaptive shell `embedded` as appropriate |
| `client/lib/pages/team_config/team_config_page.dart` | Same if it uses TitleBar via adaptive shell |
| `client/lib/pages/config/config_workspace.dart` | Inherits shell change (`showSubtitle` false) |

**Locked implementer rules:**

1. **Do not commit** unless the user explicitly asks.
2. **Do not touch** `HomeTeamHeader` / identity tab chrome.
3. **All migrated call sites:** `showSubtitle: false` (may still pass `subtitle` for API completeness; it must not render).
4. **Home owns inset** for `/home-v2` right pane; embedded children must not apply `WorkspacePaneInsets.page` again.
5. **Route-owned pages** (non-embedded adaptive shell / hub page) apply `WorkspacePaneInsets.page` once around header+body.
6. **Delete** `WorkspaceHubTitleBar` and `WorkspaceSectionHeading` after migration — no typedef aliases.
7. After each logical task: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` on touched files is enough mid-plan; full test run in final task.

---

### Task 1: `WorkspacePaneInsets` + `WorkspacePaneHeader` (TDD)

**Files:**
- Create: `client/lib/widgets/settings/workspace_pane_insets.dart`
- Create: `client/lib/widgets/settings/workspace_pane_header.dart`
- Create: `client/test/widgets/settings/workspace_pane_header_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/settings/workspace_pane_header.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TpTheme(
          child: Builder(
            builder: (context) => child,
          ),
        ),
      ),
    );
  }

  testWidgets('shows title and divider; hides subtitle by default', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspacePaneHeader(
          title: '全部工作区',
          subtitle: 'should stay hidden',
        ),
      ),
    );
    expect(find.text('全部工作区'), findsOneWidget);
    expect(find.text('should stay hidden'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('shows subtitle when showSubtitle is true', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspacePaneHeader(
          title: 'Skills',
          subtitle: 'Manage skills',
          showSubtitle: true,
        ),
      ),
    );
    expect(find.text('Manage skills'), findsOneWidget);
  });

  testWidgets('blank subtitle stays hidden even when showSubtitle is true', (tester) async {
    await tester.pumpWidget(
      wrap(
        const WorkspacePaneHeader(
          title: 'Skills',
          subtitle: '   ',
          showSubtitle: true,
        ),
      ),
    );
    expect(find.text('   '), findsNothing);
  });

  testWidgets('onBack shows leading control', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        WorkspacePaneHeader(
          title: 'Backable',
          onBack: () => tapped = true,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(tapped, isTrue);
  });
}
```

Adjust `TpTheme` wrapping if the package requires a different host — mirror other widget tests under `client/test/widgets/`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/settings/workspace_pane_header_test.dart`

Expected: FAIL — library/file missing

- [ ] **Step 3: Minimal implementation**

`workspace_pane_insets.dart`:

```dart
import 'package:flutter/material.dart';

abstract final class WorkspacePaneInsets {
  static const EdgeInsets page = EdgeInsets.fromLTRB(44, 48, 42, 18);
}
```

`workspace_pane_header.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

class WorkspacePaneHeader extends StatelessWidget {
  const WorkspacePaneHeader({
    required this.title,
    this.subtitle,
    this.showSubtitle = false,
    this.onBack,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final trimmed = subtitle?.trim();
    final showSub =
        showSubtitle && trimmed != null && trimmed.isNotEmpty;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.xl,
        ),
        if (showSub) ...[
          const SizedBox(height: 8),
          Text(
            trimmed!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: styles.mdColored(cs.onSurface.withValues(alpha: 0.66)),
          ),
        ],
        const SizedBox(height: 16),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
      ],
    );

    final back = onBack;
    if (back == null) return titleBlock;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: context.l10n.back,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: back,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        const SizedBox(width: 8),
        Expanded(child: titleBlock),
      ],
    );
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/widgets/settings/workspace_pane_header_test.dart`

- [ ] **Step 5: Commit only if user asked** — skip by default

---

### Task 2: Wire shells (`embedded` + PaneHeader)

**Files:**
- Modify: `client/lib/widgets/settings/workspace_section_host.dart`
- Modify: `client/lib/widgets/settings/workspace_hub_shell.dart` (`WorkspaceHubPage` only in this task; keep TitleBar/SectionHeading until later migrations so analyze stays green — or delete only after Task 4–5 if you migrate shells first and temporarily break call sites in the same commit batch)
- Modify: `client/test/widgets/settings/workspace_section_host_test.dart`

**Preferred batching:** In this task, change shell constructors to use `WorkspacePaneHeader` and add `embedded`. Leave old class definitions in `workspace_hub_shell.dart` until Task 5 deletes them after all call sites move (avoids a long red tree). Update tests now for the new default (subtitle hidden).

- [ ] **Step 1: Update failing expectations in host test**

Change desktop shell test:

- Still finds title text
- **Does not** find subtitle text when only `subtitle:` is passed (default hidden)
- Add test: `embedded: false` wraps with padding matching `WorkspacePaneInsets.page` (find `Padding` with that value, or assert via `tester.widget<Padding>`)
- Add test: `embedded: true` does **not** apply that page inset on the shell itself

- [ ] **Step 2: Run tests — expect FAIL on subtitle / inset assertions**

Run: `cd client && flutter test test/widgets/settings/workspace_section_host_test.dart`

- [ ] **Step 3: Implement shell API**

`WorkspaceHubDesktopShell` / `WorkspaceAdaptiveSectionPage`:

```dart
const WorkspaceHubDesktopShell({
  required this.title,
  this.subtitle,
  this.showSubtitle = false,
  required this.nav,
  required this.body,
  this.pageKey,
  this.onBack,
  this.embedded = false,
  super.key,
});
```

Build:

```dart
Widget column = Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    WorkspacePaneHeader(
      title: title,
      subtitle: subtitle,
      showSubtitle: showSubtitle,
      onBack: onBack,
    ),
    Expanded(child: /* existing LayoutCubit + WorkspaceSplitShell */),
  ],
);

if (!embedded) {
  column = Padding(padding: WorkspacePaneInsets.page, child: column);
}
return Container(key: pageKey, child: column);
```

Pass `embedded` through `WorkspaceAdaptiveSectionPage`.

`WorkspaceHubPage`: same header; `embedded` default false → apply `WorkspacePaneInsets.page`; `showSubtitle: false`.

Make `subtitle` optional (`String?`) on shell/page constructors. Call sites can keep passing strings.

- [ ] **Step 4: Run host tests — PASS**

- [ ] **Step 5: Commit only if user asked**

---

### Task 3: Home panes + global `embedded: true`

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_page.dart`
- Modify: `client/lib/pages/home_workspace/home_all_workspaces_pane.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_library_section.dart`
- Modify: `client/lib/pages/automations/automation_management_page.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart`
- Modify: `client/lib/pages/skills/skill_management_page.dart`
- Modify: `client/lib/pages/plugins/plugin_management_page.dart`
- Modify: `client/lib/pages/mcp/mcp_management_page.dart`
- Modify: `client/lib/pages/extensions/extension_management_page.dart`
- Modify: `client/lib/pages/llm_config/llm_config_workspace.dart`

- [ ] **Step 1: Home inset constant**

In `home_workspace_page.dart`, replace `EdgeInsets.fromLTRB(44, 48, 42, 18)` with `WorkspacePaneInsets.page`.

- [ ] **Step 2: All / library / automations headers**

Replace inline title (+ missing divider on library) with:

```dart
WorkspacePaneHeader(title: l10n.homeWorkspaceAllWorkspaces),
```

(and favorites/recent titles likewise). Remove duplicate `SizedBox`/`Divider` that the header already provides.

- [ ] **Step 3: Management pages `embedded`**

Add `final bool embedded;` (default `false`) to Skills/Plugins/MCP/Extensions management pages; forward to `WorkspaceAdaptiveSectionPage(embedded: embedded, showSubtitle: false, ...)`.

In `HomeGlobalSection`, construct them with `embedded: true`.

- [ ] **Step 4: Providers (`LlmConfigWorkspace` dual host)**

Same pattern as Skills: add `final bool embedded` (default `false`).

- Replace `WorkspaceSectionHeading` + outer `Padding(16,12,16,8)` with `WorkspacePaneHeader(title: …)` (`showSubtitle: false`).
- Build:
  ```dart
  final column = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showHeading) WorkspacePaneHeader(title: l10n.appProviderCatalogLabel),
      Expanded(child: body),
    ],
  );
  if (embedded) return column; // HomePage already applied WorkspacePaneInsets.page
  return Padding(padding: WorkspacePaneInsets.page, child: column);
  ```
- `HomeGlobalSection`: `LlmConfigWorkspace(embedded: true)` (and `showHeading: true` as today).
- Router `/providers…` keeps default `embedded: false` so standalone routes get page inset (`_settingsChromeShell` does not pad the child).

- [ ] **Step 5: Analyze touched files / smoke**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/home_workspace lib/pages/skills lib/pages/plugins lib/pages/mcp lib/pages/extensions lib/pages/automations lib/pages/llm_config lib/widgets/settings`

Fix any fallout.

---

### Task 4: Hub list pages + remaining TitleBar call sites

**Files:**
- Modify: `client/lib/pages/my_teams/my_teams_page.dart`
- Modify: `client/lib/pages/my_experts/my_experts_page.dart`
- Modify: `client/lib/pages/team_hub/team_hub_page.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_page.dart`
- Modify: `client/lib/pages/system/error_page.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_settings_view.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_config_workspace.dart` (pass `embedded` if hosted under already-padded parent)
- Modify: `client/lib/pages/mcp/mcp_form_nav_page.dart` (adaptive shell — default embedded false unless under padded parent)
- Modify: `client/lib/pages/team_config/team_config_page.dart`
- Modify: `client/lib/pages/config/config_workspace.dart` (inherits shell; ensure `showSubtitle: false`)

- [ ] **Step 1: My Teams / My Experts**

```dart
WorkspacePaneHeader(title: l10n.myTeamsTitle),
```

Remove `fromLTRB(28, …)` horizontal padding on toolbar/grid so content aligns with title (keep vertical spacing as needed, e.g. top 0–18). Same for My Experts.

These pages are home-hosted → do **not** wrap with `WorkspacePaneInsets.page`.

- [ ] **Step 2: Team Hub / Expert Hub**

Replace `WorkspaceHubTitleBar` with `WorkspacePaneHeader` (list mode). Home-hosted → no extra page inset.

- [ ] **Step 3: error_page / workspace_settings_view**

Swap TitleBar → PaneHeader (`showSubtitle: false`; error page may pass version string as subtitle only if you set `showSubtitle: true` — default **false**, keep version elsewhere or in body).

After removing TitleBar self-padding:

- `error_page`: wrap header+body column in `Padding(padding: WorkspacePaneInsets.page)` inside `SafeArea`, and **remove** the inner body `fromLTRB(16, …)` so horizontal inset is not doubled.
- `workspace_settings_view`: wrap the right-pane header+scroll column in a modest inset (reuse `WorkspacePaneInsets.page` horizontal values, or `EdgeInsets.fromLTRB(24,…)` matching the existing scroll padding — **do not** leave the header unpadded while the scroll body stays padded). Prefer one shared padding on the column so title and body share the same left edge; drop the scroll view’s redundant horizontal padding if it would double.

- [ ] **Step 4: Adaptive section pages still on routes**

Ensure `/skills` etc. (embedded false) get shell page inset. Home global uses embedded true.

`WorkspaceConfigPanel` (`workspace_config_workspace.dart`) is **not** under `HomePage` right-pane padding — keep `embedded: false` (default) on its `WorkspaceAdaptiveSectionPage` so the shell applies `WorkspacePaneInsets.page`. Do **not** pass `embedded: true` here.

- [ ] **Step 5: Analyze**

Run analyze on modified paths; fix.

---

### Task 5: Config SectionHeading migration + delete old widgets

**Files:**
- Modify: every file still referencing `WorkspaceSectionHeading` (grep):
  - `client/lib/pages/config/github_config_section.dart`
  - `client/lib/pages/config/ssh_profiles_config_section.dart`
  - `client/lib/pages/config/layout_config_section.dart`
  - `client/lib/pages/config/shortcuts_config_section.dart`
  - `client/lib/pages/config/download_sources_config_section.dart`
  - `client/lib/pages/about_page.dart` (`AboutConfigWorkspace`)
  - `client/lib/pages/system/log_config_workspace.dart`
- Modify: `client/lib/widgets/settings/workspace_hub_shell.dart` — **delete** `WorkspaceHubTitleBar` and `WorkspaceSectionHeading`
- Update any tests importing deleted symbols

- [ ] **Step 1: Grep for remaining references**

Run: `cd client && rg -n 'WorkspaceHubTitleBar|WorkspaceSectionHeading' lib test`

Expect only intentional hits before deletion; migrate each.

- [ ] **Step 2: Replace SectionHeading**

```dart
if (showHeading) WorkspacePaneHeader(title: l10n.…),
```

Remove the following `const SizedBox(height: 16)` when it only existed to separate heading from body (header already ends with 16).

Keep `showHeading: false` behavior inside `ConfigWorkspace` (shell title only).

- [ ] **Step 3: Delete old classes from `workspace_hub_shell.dart`**

Remove `WorkspaceHubTitleBar` and `WorkspaceSectionHeading` entirely. Fix exports/imports.

- [ ] **Step 4: Full verify**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/widgets/settings/workspace_pane_header_test.dart test/widgets/settings/workspace_section_host_test.dart
```

Then broader non-integration smoke if time:

```bash
cd client && flutter test --exclude-tags integration test/widgets/settings test/pages/home_workspace
```

Expected: PASS; zero references to deleted widgets.

- [ ] **Step 5: Commit only if user asked**

---

## Execution notes

- Prefer **subagent-driven-development**: one fresh subagent per task, review between tasks.
- If a page is both routed and home-embedded, **always** thread `embedded` from the home host; route entry leaves default `false`.
- Visual check (manual): home 「全部工作区」 vs Skills vs 我的团队 — title baseline and divider should match; no double top padding on Skills.
