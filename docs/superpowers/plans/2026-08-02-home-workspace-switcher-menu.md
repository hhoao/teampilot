# Home Workspace Switcher Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the title-bar hover-only “recently closed” `⋯` menu with a tappable workspace switcher that shows Create, open tabs, and recently closed on both desktop and mobile.

**Architecture:** Extract `HomeWorkspaceSwitcherMenu` into its own page file. It reuses `TpActionMenuAnchor` / `TpPopoverController`, keeps desktop hover-open, and adds anchor tap-to-toggle. Host (`HomeTitleBar` / `_HomeShellTitleBar`) injects tabs, closed entries, and callbacks — the menu does not touch Cubits. Create reuses `showHomeNewWorkspaceDialog`.

**Tech Stack:** Flutter / Dart, `shared_ui` (`TpActionMenuAnchor`, `TpActionMenuItem`, `TpIconButton`, `TpPopoverController`), `flutter_bloc` only at host wiring, `flutter_test`, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-08-02-home-workspace-switcher-menu-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Add `homeWorkspaceOpenTabs` |
| Generated `app_localizations*.dart` | Via `flutter gen-l10n` |
| `client/lib/pages/home_workspace/home_workspace_switcher_menu.dart` | New menu widget + small testable helpers |
| `client/test/pages/home_workspace/home_workspace_switcher_menu_test.dart` | Unit + widget coverage for menu |
| `client/lib/pages/home_workspace/home_workspace_title_bar.dart` | Swap `_RecentlyClosedOverflowButton` → `HomeWorkspaceSwitcherMenu`; pass open tabs / create / select |
| `client/lib/pages/home_workspace/home_workspace_shell.dart` | Wire `onCreate` → `showHomeNewWorkspaceDialog` (via title-bar props) |
| `client/lib/pages/home_workspace/home_new_workspace_dialog.dart` | Reuse only (no API change expected) |
| Existing `recently_closed_menu_test.dart` | Keep; helpers stay on title_bar exports |

---

### Task 1: l10n — `homeWorkspaceOpenTabs`

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Generated: `client/lib/l10n/app_localizations*.dart`

- [ ] **Step 1: Add ARB keys**

Place next to `homeWorkspaceRecentlyClosed` in both files:

```json
"homeWorkspaceOpenTabs": "Open",
```

```json
"homeWorkspaceOpenTabs": "已打开",
```

- [ ] **Step 2: Regenerate l10n**

Run:

```bash
cd client && flutter gen-l10n
```

Expected: `AppLocalizations` exposes `homeWorkspaceOpenTabs` with no analyze errors for the new getter.

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart
git commit -m "$(cat <<'EOF'
feat(l10n): add homeWorkspaceOpenTabs for switcher menu

EOF
)"
```

---

### Task 2: Failing tests for switcher helpers + menu

**Files:**
- Create: `client/test/pages/home_workspace/home_workspace_switcher_menu_test.dart`
- Create (stub only until Task 3): `client/lib/pages/home_workspace/home_workspace_switcher_menu.dart` — **do not implement behavior yet beyond what is needed for the test to compile if required; prefer RED first**

- [ ] **Step 1: Write failing unit + widget tests**

Create `home_workspace_switcher_menu_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/home_closed_workspace_entry.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_switcher_menu.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TpTheme(
        child: Center(child: child),
      ),
    ),
  );
}

void main() {
  test('homeWorkspaceSwitcherShouldShowOpenSection is false when empty', () {
    expect(homeWorkspaceSwitcherShouldShowOpenSection(const []), isFalse);
  });

  test('homeWorkspaceSwitcherShouldShowOpenSection is true when tabs exist', () {
    expect(
      homeWorkspaceSwitcherShouldShowOpenSection(const [
        HomeWorkspaceTab(id: 'a', name: 'A'),
      ]),
      isTrue,
    );
  });

  testWidgets('tap anchor opens menu with create and sections', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [
            HomeWorkspaceTab(id: 'open-1', name: 'Open One'),
          ],
          activeTabKey: 'open-1',
          recentlyClosed: const [
            HomeClosedWorkspaceEntry(
              workspaceId: 'closed-1',
              displayName: 'Closed One',
              primaryPath: '/tmp/c',
            ),
          ],
          onCreate: () {},
          onSelectOpen: (_) {},
          onReopenClosed: (_) {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.newWorkspace), findsOneWidget);
    expect(find.text(l10n.homeWorkspaceOpenTabs), findsOneWidget);
    expect(find.text('Open One'), findsOneWidget);
    expect(find.text(l10n.homeWorkspaceRecentlyClosed), findsOneWidget);
    expect(find.text('Closed One'), findsOneWidget);
  });

  testWidgets('tap create invokes onCreate', (tester) async {
    var created = false;
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [],
          recentlyClosed: const [],
          onCreate: () => created = true,
          onSelectOpen: (_) {},
          onReopenClosed: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.tap(find.text(l10n.newWorkspace));
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });

  testWidgets('tap open tab invokes onSelectOpen', (tester) async {
    String? selected;
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [
            HomeWorkspaceTab(id: 'open-1', name: 'Open One'),
          ],
          activeTabKey: 'open-1',
          recentlyClosed: const [],
          onCreate: () {},
          onSelectOpen: (id) => selected = id,
          onReopenClosed: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Open One'));
    await tester.pumpAndSettle();
    expect(selected, 'open-1');
  });

  testWidgets('tap recently closed invokes onReopenClosed', (tester) async {
    String? reopened;
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [],
          recentlyClosed: const [
            HomeClosedWorkspaceEntry(
              workspaceId: 'closed-1',
              displayName: 'Closed One',
            ),
          ],
          onCreate: () {},
          onSelectOpen: (_) {},
          onReopenClosed: (key) => reopened = key,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closed One'));
    await tester.pumpAndSettle();
    expect(reopened, isNotNull);
  });

  testWidgets('omits open section when no open tabs', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HomeWorkspaceSwitcherMenu(
          openTabs: const [],
          recentlyClosed: const [],
          onCreate: () {},
          onSelectOpen: (_) {},
          onReopenClosed: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.homeWorkspaceOpenTabs), findsNothing);
    expect(find.text(l10n.homeWorkspaceRecentlyClosedEmpty), findsOneWidget);
  });
}
```

Adjust imports if `lookupAppLocalizations` / `TpTheme` wrapping differs in this repo — follow patterns from `home_workspace_title_bar_test.dart` and `shared_ui` action-menu tests. Prefer reading l10n via `AppLocalizations.of(context)!` inside a builder if `lookupAppLocalizations` is unavailable.

**Note:** Desktop hover-open is Manual QA only (Task 5) — no automated hover test required.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/pages/home_workspace/home_workspace_switcher_menu_test.dart
```

Expected: FAIL (missing library / undefined symbols / unimplemented menu).

- [ ] **Step 3: Commit failing tests**

If intermediate commits must stay green for CI, skip this step and commit tests together with Task 3.

```bash
git add client/test/pages/home_workspace/home_workspace_switcher_menu_test.dart
git commit -m "$(cat <<'EOF'
test: add failing coverage for workspace switcher menu

EOF
)"
```

---

### Task 3: Implement `HomeWorkspaceSwitcherMenu`

**Files:**
- Create: `client/lib/pages/home_workspace/home_workspace_switcher_menu.dart`
- Reuse helpers/widgets from: `home_workspace_title_bar.dart` (`recentlyClosedEntryLabel`, `recentlyClosedSubtitleLine`, `recentlyClosedTopology`, `WorkspaceTabTopologyIcon`, `HomeWorkspaceTab`)

- [ ] **Step 1: Minimal implementation**

Implement approximately:

```dart
@visibleForTesting
bool homeWorkspaceSwitcherShouldShowOpenSection(List<HomeWorkspaceTab> openTabs) =>
    openTabs.isNotEmpty;

class HomeWorkspaceSwitcherMenu extends StatefulWidget {
  const HomeWorkspaceSwitcherMenu({
    required this.openTabs,
    this.activeTabKey,
    this.recentlyClosed = const [],
    this.workspaces = const [],
    this.launchProfiles = const [],
    this.onCreate,
    this.onSelectOpen,
    this.onReopenClosed,
    super.key,
  });

  final List<HomeWorkspaceTab> openTabs;
  final String? activeTabKey;
  final List<HomeClosedWorkspaceEntry> recentlyClosed;
  final List<Workspace> workspaces;
  final List<LaunchProfile> launchProfiles;
  final VoidCallback? onCreate;
  final ValueChanged<String>? onSelectOpen;
  final ValueChanged<String>? onReopenClosed;
  // ...
}
```

Behavior requirements (match spec):

1. **Anchor:** `TpIconButton(Icons.more_horiz)`, tooltip `homeWorkspaceRecentlyClosed`, `onTap` toggles `_popoverController.show()` / `hide()`.
2. **Desktop hover:** keep existing `MouseRegion` open-on-enter + delayed close on exit (both anchor and panel), same delays as old `_RecentlyClosedOverflowButton` (`180ms`).
3. **Panel layout (top → bottom):**
   - Create row: `TpActionMenuItem(icon: Icons.add, label: l10n.newWorkspace, …)`.
   - On create tap: `_popoverController.hide()` then `WidgetsBinding.instance.addPostFrameCallback((_) => onCreate?.call())` so the dialog is not stacked under an open popover. (Do **not** rely on “host closes menu”.)
   - If open tabs non-empty: section header `homeWorkspaceOpenTabs`, then one item per tab — `WorkspaceTabTopologyIcon` + name; active tab `trailing: Icon(Icons.check, …)`; `onTap` → `onSelectOpen(tab.id)`.
   - Section header `homeWorkspaceRecentlyClosed`; empty → disabled empty item; else scrollable list (max height `320`, width `300`) using existing closed-entry helpers / item chrome.
4. Pass `TpActionMenuController(_popoverController)` into items so select/reopen also close the menu (Create already hides explicitly before `onCreate`).
5. No Cubit reads inside this file.

Port the old `_RecentlyClosedOverflowButton` hover/timer/`TpActionMenuAnchor` structure; delete duplication when Task 4 removes the private widget.

- [ ] **Step 2: Run tests — expect PASS**

```bash
cd client && flutter test test/pages/home_workspace/home_workspace_switcher_menu_test.dart
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_switcher_menu.dart client/test/pages/home_workspace/home_workspace_switcher_menu_test.dart
git commit -m "$(cat <<'EOF'
feat(home): add HomeWorkspaceSwitcherMenu with create/open/closed

EOF
)"
```

---

### Task 4: Wire into title bar + shell create

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_title_bar.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_shell.dart`
- Possibly update: `client/test/pages/home_workspace/home_workspace_title_bar_test.dart` if it asserts on old private behavior

- [ ] **Step 1: Extend `HomeTitleBar` API**

Add optional:

```dart
final VoidCallback? onCreateWorkspace;
```

Replace both `_RecentlyClosedOverflowButton(...)` call sites with:

```dart
HomeWorkspaceSwitcherMenu(
  openTabs: widget.tabs,
  activeTabKey: widget.activeTabKey,
  recentlyClosed: widget.recentlyClosed,
  workspaces: widget.workspaces,
  launchProfiles: widget.launchProfiles,
  onCreate: widget.onCreateWorkspace,
  onSelectOpen: widget.onSelectTab,
  onReopenClosed: widget.onReopenClosedTab,
),
```

Delete `_RecentlyClosedOverflowButton` / `_RecentlyClosedOverflowButtonState` / `_RecentlyClosedMenuItem` from `home_workspace_title_bar.dart` after the new file owns that UI (keep exported helpers used by tests + menu).

- [ ] **Step 2: Wire create from `_HomeShellTitleBar`**

In `home_workspace_shell.dart`, pass:

```dart
onCreateWorkspace: () {
  unawaited(
    showHomeNewWorkspaceDialog(
      context,
      chatCubit: context.read<ChatCubit>(),
      repository: context.read<SessionRepository>(),
    ),
  );
},
```

**Important:** Match `workspaces_tab.dart` exactly (`ChatCubit` + `SessionRepository` from context). Import `home_new_workspace_dialog.dart`.

- [ ] **Step 3: Run focused tests**

```bash
cd client && flutter test test/pages/home_workspace/home_workspace_switcher_menu_test.dart test/pages/home_workspace/home_workspace_title_bar_test.dart test/pages/home_workspace/recently_closed_menu_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_title_bar.dart client/lib/pages/home_workspace/home_workspace_shell.dart client/test/pages/home_workspace/
git commit -m "$(cat <<'EOF'
feat(home): wire workspace switcher menu into title bar

EOF
)"
```

---

### Task 5: Verify analyze + broader regression

**Files:** none expected beyond fixes from failures

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new errors related to switcher / title bar / l10n.

- [ ] **Step 2: Broader home_workspace tests (optional but preferred)**

```bash
cd client && flutter test test/pages/home_workspace/ --exclude-tags integration
```

Expected: PASS (or only pre-existing unrelated failures — do not leave new failures).

- [ ] **Step 3: Manual checklist (human or device)**

- Mobile: tap `⋯` opens menu; Create / Open / Recently closed work.
- Desktop: hover still opens; click also toggles.
- Create opens existing new-workspace dialog; after success lands on new workspace.
- Selecting an open tab switches; selecting closed reopens.

- [ ] **Step 4: Final commit only if analyze/test fixes were needed**

```bash
git add -u
git commit -m "$(cat <<'EOF'
fix(home): address switcher menu analyze/test fallout

EOF
)"
```

---

## Manual QA notes

- Open section omitted when `_openTabs` is empty (e.g. home with no workspace tabs).
- Active open tab shows check trailing.
- Recently closed continues to exclude currently open tab keys (shell already filters in `_reloadRecentlyClosed`).
