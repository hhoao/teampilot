# Home Sidebar Resizable Width Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the home (`/home-v2`) `HomeSidebar` drag-resizable, persist width via `LayoutCubit`, and keep a 480px minimum for the right content pane with no productized sidebar max.

**Architecture:** Add `homeSidebarWidth` to `LayoutPreferences` (default 420, min 280, soft max). Wire `HomePage` through `TwoPaneSplitView` like `WorkspaceSplitShell`. Remove the fixed width from `HomeSidebar` so the split owns sizing.

**Tech Stack:** Flutter, `flutter_bloc`, existing `TwoPaneSplitView` / `ResizableSplitView`, `LayoutCubit` / `LayoutPreferences`.

**Spec:** `docs/superpowers/specs/2026-07-11-home-sidebar-resizable-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/layout_preferences.dart` | `homeSidebarWidth` field, constants, JSON, clamp |
| `client/lib/cubits/layout_cubit.dart` | `setHomeSidebarWidth` |
| `client/lib/pages/home_workspace/home_workspace_page.dart` | `TwoPaneSplitView` + cubit wiring |
| `client/lib/pages/home_workspace/home_workspace_sidebar.dart` | Drop fixed outer width; alias default constant |
| `client/test/models/layout_preferences_default_test.dart` | Prefs load/clamp tests |

---

### Task 1: Persist `homeSidebarWidth`

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Test: `client/test/models/layout_preferences_default_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `layout_preferences_default_test.dart`:

```dart
test('homeSidebarWidth defaults, clamps min, keeps large', () {
  expect(
    const LayoutPreferences().homeSidebarWidth,
    LayoutPreferences.defaultHomeSidebarWidth,
  );
  expect(
    LayoutPreferences.fromJson(const {}).homeSidebarWidth,
    LayoutPreferences.defaultHomeSidebarWidth,
  );
  expect(
    LayoutPreferences.fromJson(const {'homeSidebarWidth': 'x'}).homeSidebarWidth,
    LayoutPreferences.defaultHomeSidebarWidth,
  );
  expect(
    LayoutPreferences.fromJson(const {'homeSidebarWidth': 10}).homeSidebarWidth,
    LayoutPreferences.minHomeSidebarWidth,
  );
  expect(
    LayoutPreferences.fromJson(const {'homeSidebarWidth': 900}).homeSidebarWidth,
    900,
  );
  final clamped = const LayoutPreferences().copyWith(homeSidebarWidth: 10);
  expect(clamped.homeSidebarWidth, LayoutPreferences.minHomeSidebarWidth);
  final roundTrip = LayoutPreferences.fromJson(
    const LayoutPreferences(homeSidebarWidth: 500).toJson(),
  );
  expect(roundTrip.homeSidebarWidth, 500);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart --name homeSidebarWidth`
Expected: FAIL (getter / constants missing)

- [ ] **Step 3: Implement prefs + cubit**

In `layout_preferences.dart`:

- Constants: `defaultHomeSidebarWidth = 420.0`, `minHomeSidebarWidth = 280.0`
- Field `homeSidebarWidth` defaulting to `defaultHomeSidebarWidth`
- `fromJson`: `_doubleValue(json['homeSidebarWidth'], fallback: defaultHomeSidebarWidth).clamp(minHomeSidebarWidth, double.infinity)`
- `copyWith` / `withAtLeastOneToolVisible` / `toJson`: include field; copyWith clamps ≥ min, no hard max

In `layout_cubit.dart`:

```dart
Future<void> setHomeSidebarWidth(double width) =>
    _save(state.preferences.copyWith(homeSidebarWidth: width));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart --name homeSidebarWidth`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/layout_preferences.dart client/lib/cubits/layout_cubit.dart client/test/models/layout_preferences_default_test.dart
git commit -m "feat(layout): persist home sidebar width preference"
```

---

### Task 2: Wire resizable home split

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_page.dart`

- [ ] **Step 1: Make `HomeSidebar` width-agnostic**

- Change `static const double width = 420` to alias `LayoutPreferences.defaultHomeSidebarWidth` (import layout_preferences).
- Remove `width: HomeSidebar.width` from the outer `Container` so the parent owns width (keep decoration + padding).

- [ ] **Step 2: Replace `HomePage` Row with `TwoPaneSplitView`**

Imports: `flutter_bloc`, `layout_cubit`, `layout_preferences`, `split_layout.dart` (exports `TwoPaneSplitView`).

Replace the `Row(...)` child of `WorkspacePageCardShell` with:

```dart
BlocBuilder<LayoutCubit, LayoutState>(
  buildWhen: (a, b) =>
      a.preferences.homeSidebarWidth != b.preferences.homeSidebarWidth,
  builder: (context, layoutState) {
    return TwoPaneSplitView(
      axis: Axis.horizontal,
      first: HomeSidebar(/* existing props */),
      second: Padding(
        padding: const EdgeInsets.fromLTRB(44, 48, 42, 18),
        child: _HomeRightPane(/* existing props */),
      ),
      initialSize: layoutState.preferences.homeSidebarWidth,
      minSize: LayoutPreferences.minHomeSidebarWidth,
      maxSize: double.infinity,
      minSecondarySize: LayoutPreferences.minWorkspaceHubContentWidth,
      onSizeChanged: (width) {
        context.read<LayoutCubit>().setHomeSidebarWidth(width);
      },
    );
  },
)
```

Do **not** copy `WorkspaceSplitShell`'s hard `maxWorkspaceNavWidth`.

- [ ] **Step 3: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/models/layout_preferences.dart lib/cubits/layout_cubit.dart lib/pages/home_workspace/home_workspace_page.dart lib/pages/home_workspace/home_workspace_sidebar.dart`
Expected: no issues in these files

- [ ] **Step 4: Re-run prefs tests**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/home_workspace_page.dart client/lib/pages/home_workspace/home_workspace_sidebar.dart
git commit -m "feat(home): make HomeSidebar drag-resizable"
```

---

### Task 3: Smoke verification

- [ ] **Step 1: Manual checklist (or note for human)**

1. Open `/home-v2`; drag home sidebar edge — width changes.
2. Restart app — width restored.
3. Drag until right pane hits ~480 — further widen blocked.
4. Drag narrow until sidebar ~280 — further narrow blocked.

- [ ] **Step 2: Final commit only if Task 3 produced code fixes** (skip if clean)
