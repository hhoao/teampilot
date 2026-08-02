# Mobile Leading Inset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared mobile leading inset (`TpMobileChrome` + `TpMobileLeading`) and apply it to settings hub AppBar back and workspace chat landing back so curved-edge phones match the home hamburger’s 16px left comfort.

**Architecture:** Put the token and wrapper in `shared_ui`. Mobile detection is `TpSidebarScope.maybeOf(context)?.isMobile ?? (width < narrowBreakpointWidth)`. Migrate home title-bar magic `16`, wrap settings `BackButton` (with raised `leadingWidth`), and ensure landing back left edge ≥ inset. Do not wrap `WorkspacePaneHeader` (already inside 44px page insets).

**Tech Stack:** Flutter / Dart, `shared_ui`, `flutter_test`, existing router / landing widget tests.

**Spec:** `docs/superpowers/specs/2026-08-02-mobile-leading-inset-design.md`

**Note:** `client/packages/shared_ui` is a git submodule — commit shared_ui changes inside that repo, then update the parent pointer.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/components/chrome/tp_mobile_chrome.dart` | `TpMobileChrome` token + `TpMobileLeading` wrapper |
| `client/packages/shared_ui/lib/shared_ui.dart` | Export new API |
| `client/packages/shared_ui/test/components/chrome/tp_mobile_chrome_test.dart` | Token + wrapper widget tests |
| `client/lib/pages/home_workspace/home_workspace_title_bar.dart` | Replace magic `16` with `TpMobileChrome.leadingInset` |
| `client/lib/router/app_router.dart` | Settings AppBar: `TpMobileLeading` + `leadingWidth` on hub detail back |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | Mobile left ≥ `leadingInset` for back button |
| `client/test/router/android_settings_chrome_drawer_test.dart` | Assert `TpMobileLeading` + unclipped back |
| `client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart` | Assert narrow left edge ≥ inset |

---

### Task 1: shared_ui — `TpMobileChrome` + `TpMobileLeading` (TDD)

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/chrome/tp_mobile_chrome.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Create: `client/packages/shared_ui/test/components/chrome/tp_mobile_chrome_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('TpMobileChrome tokens match locked design values', () {
    expect(TpMobileChrome.leadingInset, 16);
    expect(TpMobileChrome.narrowBreakpointWidth, 840);
  });

  testWidgets('force true always applies leading inset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TpMobileLeading(
            force: true,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(TpMobileLeading),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding, const EdgeInsets.only(left: 16));
  });

  testWidgets('wide viewport without force does not pad', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TpMobileLeading(
            child: SizedBox(width: 40, height: 40, key: Key('child')),
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(TpMobileLeading),
        matching: find.byType(Padding),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('child')), findsOneWidget);
  });

  testWidgets('narrow viewport without scope applies inset', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TpMobileLeading(
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(TpMobileLeading),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding.left, TpMobileChrome.leadingInset);
  });

  testWidgets('sidebar scope isMobile true applies inset even if wide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: TpSidebarProvider(
          // Force mobile classification via tiny breakpoint.
          mobileBreakpoint: 2000,
          child: const Scaffold(
            body: TpMobileLeading(
              child: SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(TpMobileLeading),
        matching: find.byType(Padding),
      ),
    );
    expect(padding.padding.left, TpMobileChrome.leadingInset);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/chrome/tp_mobile_chrome_test.dart
```

Expected: FAIL — `TpMobileChrome` / `TpMobileLeading` not found / not exported.

- [ ] **Step 3: Implement minimal API**

Create `client/packages/shared_ui/lib/src/components/chrome/tp_mobile_chrome.dart`:

```dart
import 'package:flutter/material.dart';

import '../sidebar/tp_sidebar_scope.dart';

/// Mobile chrome spacing tokens for edge-adjacent controls.
abstract final class TpMobileChrome {
  /// Left inset for edge-adjacent controls on curved / narrow screens.
  /// Matches home title-bar hamburger spacing.
  static const double leadingInset = 16;

  /// Narrow / mobile width fallback when no [TpSidebarScope] is present.
  /// Keep equal to app `WorkspacePanePolicy.narrowBreakpointWidth`.
  static const double narrowBreakpointWidth = 840;
}

/// Pads [child] on the left when the host is mobile / narrow.
class TpMobileLeading extends StatelessWidget {
  const TpMobileLeading({
    required this.child,
    this.force = false,
    super.key,
  });

  final Widget child;
  final bool force;

  static bool _isMobile(BuildContext context) {
    final scoped = TpSidebarScope.maybeOf(context)?.isMobile;
    if (scoped != null) return scoped;
    return MediaQuery.sizeOf(context).width <
        TpMobileChrome.narrowBreakpointWidth;
  }

  @override
  Widget build(BuildContext context) {
    if (!force && !_isMobile(context)) return child;
    return Padding(
      padding: const EdgeInsets.only(left: TpMobileChrome.leadingInset),
      child: child,
    );
  }
}
```

Export from `client/packages/shared_ui/lib/shared_ui.dart` (near other chrome / sidebar exports):

```dart
export 'src/components/chrome/tp_mobile_chrome.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client/packages/shared_ui && flutter test test/components/chrome/tp_mobile_chrome_test.dart
```

Expected: PASS

- [ ] **Step 5: Commit in shared_ui submodule**

```bash
cd client/packages/shared_ui
git add lib/src/components/chrome/tp_mobile_chrome.dart lib/shared_ui.dart test/components/chrome/tp_mobile_chrome_test.dart
git commit -m "$(cat <<'EOF'
feat(shared_ui): add TpMobileChrome leading inset wrapper

EOF
)"
```

---

### Task 2: Home title bar — replace magic `16`

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_title_bar.dart` (~line 304)

- [ ] **Step 1: Swap token**

Change:

```dart
SizedBox(width: compactChrome ? 16 : 8),
```

to:

```dart
SizedBox(width: compactChrome ? TpMobileChrome.leadingInset : 8),
```

Ensure `shared_ui` is already imported (it is via existing `TpSidebarTrigger` / `TpIconButton` usage).

Do **not** change trailing `SizedBox(width: 16)` spacers on the right side of the bar.

- [ ] **Step 2: Quick analyze / existing title-bar tests**

```bash
cd client && flutter test test/pages/home_workspace/home_workspace_title_bar_test.dart
```

Expected: PASS (behavior unchanged; only constant source changes).

- [ ] **Step 3: Commit in teampilot (pointer + title bar together after later tasks if preferred; otherwise stage title bar with app commits in Task 5)**

No separate commit required if bundling with Task 3–4 app changes; otherwise:

```bash
git add client/lib/pages/home_workspace/home_workspace_title_bar.dart client/packages/shared_ui
git commit -m "$(cat <<'EOF'
refactor(home): use TpMobileChrome.leadingInset for mobile title spacer

EOF
)"
```

Prefer **one app commit** at the end of Task 4 that includes submodule pointer + all app call sites + tests.

---

### Task 3: Settings chrome AppBar back — wrap + leadingWidth

**Files:**
- Modify: `client/lib/router/app_router.dart` (`_settingsChromeShell`, ~lines 478–492)
- Modify: `client/test/router/android_settings_chrome_drawer_test.dart`

- [ ] **Step 1: Extend failing assertions in drawer test**

In `hub detail hides trigger, shows back, disables edge open`, after expecting `BackButton`, add:

```dart
expect(find.byType(TpMobileLeading), findsOneWidget);

final backRect = tester.getRect(find.byType(BackButton));
expect(backRect.left, greaterThanOrEqualTo(TpMobileChrome.leadingInset));
```

(If `SafeArea` / status padding shifts Y only, `left` should still clear the inset relative to the scaffold content; if the harness applies left MediaQuery padding, assert `backRect.left >= mediaPadding.left + TpMobileChrome.leadingInset` instead.)

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && flutter test test/router/android_settings_chrome_drawer_test.dart
```

Expected: FAIL — no `TpMobileLeading` yet.

- [ ] **Step 3: Implement AppBar leading wrap**

In `_settingsChromeShell` mobile drawer branch, when building `AppBar`:

```dart
appBar: AppBar(
  title: Text(AndroidShellChrome.title(context, path)),
  leadingWidth: hideDrawer
      ? kToolbarHeight + TpMobileChrome.leadingInset
      : null,
  leading: hideDrawer
      ? TpMobileLeading(
          child: BackButton(
            onPressed: () => AndroidShellChrome.pop(context, path),
          ),
        )
      : const TpSidebarTrigger(),
  actions: const [AndroidWorkEnvironmentSelector()],
),
```

Notes:
- Keep `TpSidebarTrigger` path unchanged (no forced leading inset on that branch).
- `kToolbarHeight` is from `package:flutter/material.dart` (already imported).
- Detection: hub detail routes are under `TpSidebarProvider(mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth)` so narrow tests get `isMobile == true` and the wrapper pads.

- [ ] **Step 4: Re-run drawer test**

```bash
cd client && flutter test test/router/android_settings_chrome_drawer_test.dart
```

Expected: PASS

---

### Task 4: Workspace chat landing back — mobile left ≥ inset

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Modify: `client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart`

- [ ] **Step 1: Add narrow landing inset test**

Add a second test (or extend pump helper with optional width):

```dart
testWidgets('narrow landing back left edge respects mobile leading inset', (
  tester,
) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await pumpLanding(tester);

  final back = find.byKey(AppKeys.workspaceChatLandingBackButton);
  expect(back, findsOneWidget);
  expect(
    tester.getRect(back).left,
    greaterThanOrEqualTo(TpMobileChrome.leadingInset),
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart
```

Expected: FAIL — current `left: spacing.md` is 12 `< 16`.

- [ ] **Step 3: Implement landing left inset**

In `workspace_chat_landing.dart`, replace the fixed `Positioned(left: spacing.md, …)` with mobile-aware left:

```dart
final isMobile =
    TpSidebarScope.maybeOf(context)?.isMobile ??
    MediaQuery.sizeOf(context).width < TpMobileChrome.narrowBreakpointWidth;
final backLeft = isMobile
    ? math.max(spacing.md, TpMobileChrome.leadingInset)
    : spacing.md;

// ...
Positioned(
  top: spacing.md,
  left: backLeft,
  child: TpIconButton(
    key: AppKeys.workspaceChatLandingBackButton,
    // ... unchanged
  ),
),
```

Or equivalently wrap the button in `TpMobileLeading` and set `left: spacing.md` only when not mobile — prefer the `max(...)` form so total left is exactly `max(md, inset)` without double-counting if `md` ever grows past 16.

Add imports as needed:

```dart
import 'dart:math' as math;
```

(`shared_ui` should already be imported for `TpIconButton` / spacing.)

- [ ] **Step 4: Re-run landing chrome tests**

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart
```

Expected: PASS

- [ ] **Step 5: Broader verification**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/router/android_settings_chrome_drawer_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart test/pages/home_workspace/home_workspace_title_bar_test.dart
cd client/packages/shared_ui && flutter test test/components/chrome/tp_mobile_chrome_test.dart
```

Expected: analyze clean enough for repo policy; all listed tests PASS.

- [ ] **Step 6: Commit app + submodule pointer**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add \
  client/packages/shared_ui \
  client/lib/pages/home_workspace/home_workspace_title_bar.dart \
  client/lib/router/app_router.dart \
  client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  client/test/router/android_settings_chrome_drawer_test.dart \
  client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart \
  docs/superpowers/specs/2026-08-02-mobile-leading-inset-design.md \
  docs/superpowers/plans/2026-08-02-mobile-leading-inset.md
git commit -m "$(cat <<'EOF'
feat(mobile): shared leading inset for edge-adjacent back chrome

EOF
)"
```

(Only include the spec/plan in the commit if the user wants docs committed with the feature; otherwise commit code alone.)

---

## Manual check

- Narrow phone / emulator: settings hub detail back sits ~16px in from content left, similar to home hamburger.
- Narrow landing: back button left ≥ 16.
- Wide desktop: no extra dead space before landing back / settings back (when that chrome appears).

## Out of scope (do not implement in this plan)

- Wrapping `WorkspacePaneHeader` back
- Trailing / right-edge insets
- Forcing inset on Android wide tablets when `isMobile == false`
- New `TpBackButton` product widget
