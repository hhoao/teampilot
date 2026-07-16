# Shared UI Toast (`TpToast`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Absorb vendored `toastification` into `shared_ui` as a private engine and ship a public `TpToast*` API, while keeping a thin TeamPilot `AppToast` facade for recorder / `showGlobal` / desktop title-bar inset.

**Architecture:** Copy engine sources under `shared_ui/lib/src/toast/engine/` (not barrel-exported). Public layer wraps the engine with `TpToast` / `TpToastWrapper` / `TpToastConfig` / `TpToastTheme` on `TpThemeData`. Client replaces `ToastificationWrapper` + deletes `packages/toastification`; renames `AppToastVariant`/`AppToastAction` → `TpToast*`.

**Tech Stack:** Flutter, existing `shared_ui` (`TpTheme`, `TpTextStyles`), vendored toastification deps (`equatable`, `pausable_timer`, `uuid`, `collection`).

**Spec:** [2026-07-16-shared-ui-toast-design.md](../specs/2026-07-16-shared-ui-toast-design.md)

---

## File map

| Path | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/toast/engine/**` | Private absorbed toastification sources + private barrel |
| `client/packages/shared_ui/lib/src/theme/components/tp_toast_theme.dart` | Visual slot + `fromColorScheme` / `accentFor(variant)` |
| `client/packages/shared_ui/lib/src/components/toast/tp_toast_config.dart` | Public config (maps to engine config) |
| `client/packages/shared_ui/lib/src/components/toast/tp_toast_wrapper.dart` | Thin wrapper over engine `ToastificationWrapper` |
| `client/packages/shared_ui/lib/src/components/toast/tp_toast.dart` | `TpToastVariant`, `TpToastAction`, `TpToast.show` / `dismiss` |
| `client/packages/shared_ui/lib/src/theme/tp_theme_data.dart` | Add optional `toast` / `toastTheme` |
| `client/packages/shared_ui/lib/shared_ui.dart` | Export public toast APIs only |
| `client/packages/shared_ui/test/components/toast/**` | Widget/unit tests |
| `client/lib/widgets/app_toast/app_toast.dart` | Thin product facade |
| `client/lib/theme/app_toast_theme.dart` | Delete or shrink to `buildTeamPilotToastConfig()` only |
| `client/lib/main.dart` | `TpToastWrapper` + `TpToastTheme(workspaceCard…)` on `TpThemeData` |
| `client/packages/toastification/**` | Delete after client migrates |

---

### Task 1: Absorb engine into `shared_ui` (private)

**Files:**
- Create: `client/packages/shared_ui/lib/src/toast/engine/**` (copy from `client/packages/toastification/lib/**`)
- Modify: `client/packages/shared_ui/pubspec.yaml`

- [ ] **Step 1: Copy sources**

```bash
mkdir -p client/packages/shared_ui/lib/src/toast/engine
cp -a client/packages/toastification/lib/. client/packages/shared_ui/lib/src/toast/engine/
# Expect: toastification.dart barrel + src/ tree under engine/
```

- [ ] **Step 2: Rewrite package imports**

From `client/packages/shared_ui`:

```bash
# Rewrite package:toastification/... → package:shared_ui/src/toast/engine/...
find lib/src/toast/engine -name '*.dart' -print0 | xargs -0 sed -i \
  's|package:toastification/|package:shared_ui/src/toast/engine/|g'
```

Confirm zero remaining `package:toastification` under `lib/src/toast/engine`.

- [ ] **Step 3: Add engine dependencies to `shared_ui/pubspec.yaml`**

```yaml
dependencies:
  flutter:
    sdk: flutter
  toggle_switch: ^2.3.0
  collection: ^1.19.0
  equatable: ^2.0.5
  pausable_timer: ^3.1.0+3
  uuid: ^4.5.1
```

Run: `cd client/packages/shared_ui && flutter pub get`

- [ ] **Step 4: Smoke-analyze the engine compiles (no public export yet)**

Create a temporary private import check by analyzing the package:

```bash
cd client/packages/shared_ui && dart analyze lib/src/toast/engine --fatal-infos 2>&1 | head -40
```

Expected: no errors (infos/warnings OK to triage; fix real errors only).

- [ ] **Step 5: Commit (shared_ui submodule)**

```bash
cd client/packages/shared_ui
git add lib/src/toast/engine pubspec.yaml pubspec.lock
git commit -m "$(cat <<'EOF'
chore: absorb toastification engine as private toast/engine

EOF
)"
```

---

### Task 2: `TpToastTheme` + wire into `TpThemeData` (TDD)

**Files:**
- Create: `client/packages/shared_ui/lib/src/theme/components/tp_toast_theme.dart`
- Create: `client/packages/shared_ui/test/theme/tp_toast_theme_test.dart`
- Modify: `client/packages/shared_ui/lib/src/theme/tp_theme_data.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart` (export theme later with toast barrel — export in Task 4 if preferred; export theme here is fine)

- [ ] **Step 1: Write failing theme test**

```dart
// test/theme/tp_toast_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('fromColorScheme maps accents and uses surfaceContainer background', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final theme = TpToastTheme.fromColorScheme(scheme);
    expect(theme.backgroundColor, scheme.surfaceContainer);
    expect(theme.foregroundColor, scheme.onSurface);
    expect(theme.accentFor(TpToastVariant.info), scheme.primary);
    expect(theme.accentFor(TpToastVariant.success), scheme.secondary);
    expect(theme.accentFor(TpToastVariant.warning), scheme.primary);
    expect(theme.accentFor(TpToastVariant.error), scheme.error);
    expect(theme.borderRadius, BorderRadius.circular(10));
  });

  test('TpThemeData.toastTheme resolves override', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
    final data = TpThemeData.fromColorScheme(
      scheme,
      scale: 1,
      toast: TpToastTheme.fromColorScheme(
        scheme,
        backgroundColor: const Color(0xFF112233),
      ),
    );
    expect(data.toastTheme.backgroundColor, const Color(0xFF112233));
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (types missing)**

```bash
cd client/packages/shared_ui && flutter test test/theme/tp_toast_theme_test.dart
```

Expected: FAIL — `TpToastTheme` / `TpToastVariant` not defined.

- [ ] **Step 3: Implement `TpToastTheme` + minimal `TpToastVariant`**

Put variant enum in `tp_toast.dart` early, or temporarily in `tp_toast_theme.dart` and move in Task 3. Prefer creating:

`lib/src/components/toast/tp_toast.dart` with only:

```dart
enum TpToastVariant { info, success, warning, error }
```

And `lib/src/theme/components/tp_toast_theme.dart`:

```dart
@immutable
class TpToastTheme {
  const TpToastTheme({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderSide,
    required this.borderRadius,
    required this.boxShadow,
    required this.padding,
    required this.iconSize,
    required this.infoAccent,
    required this.successAccent,
    required this.warningAccent,
    required this.errorAccent,
  });

  factory TpToastTheme.fromColorScheme(
    ColorScheme scheme, {
    Color? backgroundColor,
    double borderRadius = 10,
    double iconSize = 20,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    return TpToastTheme(
      backgroundColor: backgroundColor ?? scheme.surfaceContainer,
      foregroundColor: scheme.onSurface,
      borderSide: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.55),
      ),
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      iconSize: iconSize,
      infoAccent: scheme.primary,
      successAccent: scheme.secondary,
      warningAccent: scheme.primary,
      errorAccent: scheme.error,
    );
  }

  // fields…
  Color accentFor(TpToastVariant variant) => switch (variant) {
    TpToastVariant.info => infoAccent,
    TpToastVariant.success => successAccent,
    TpToastVariant.warning => warningAccent,
    TpToastVariant.error => errorAccent,
  };
}
```

Wire `toast` optional param + `toastTheme` getter on `TpThemeData` (mirror `card` / `cardTheme`). Include in `==` / `hashCode`.

Export both from `shared_ui.dart`.

- [ ] **Step 4: Run test — expect PASS**

```bash
cd client/packages/shared_ui && flutter test test/theme/tp_toast_theme_test.dart
```

- [ ] **Step 5: Commit**

```bash
cd client/packages/shared_ui
git add lib/src/theme/components/tp_toast_theme.dart \
  lib/src/components/toast/tp_toast.dart \
  lib/src/theme/tp_theme_data.dart \
  lib/shared_ui.dart \
  test/theme/tp_toast_theme_test.dart
git commit -m "$(cat <<'EOF'
feat: add TpToastTheme on TpThemeData

EOF
)"
```

---

### Task 3: `TpToastConfig` + `TpToastWrapper` + `TpToast.show` (TDD)

**Files:**
- Create: `lib/src/components/toast/tp_toast_config.dart`
- Create: `lib/src/components/toast/tp_toast_wrapper.dart`
- Modify: `lib/src/components/toast/tp_toast.dart`
- Create: `test/components/toast/tp_toast_test.dart`

- [ ] **Step 1: Write failing widget tests**

```dart
// test/components/toast/tp_toast_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

Widget _harness({required Widget child, TpToastTheme? toast}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return TpToastWrapper(
    config: const TpToastConfig(
      alignment: AlignmentDirectional.topEnd,
      itemWidth: 400,
      maxToastLimit: 1,
      animationDuration: Duration(milliseconds: 200),
    ),
    child: MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1, toast: toast),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('show presents message and dismiss removes it', (tester) async {
    await tester.pumpWidget(
      _harness(
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => TpToast.show(context, message: 'Hello toast'),
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump(); // start
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Hello toast'), findsOneWidget);

    TpToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Hello toast'), findsNothing);
  });

  testWidgets('empty message is a no-op', (tester) async {
    await tester.pumpWidget(
      _harness(
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => TpToast.show(context, message: '   '),
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('   '), findsNothing);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client/packages/shared_ui && flutter test test/components/toast/tp_toast_test.dart
```

- [ ] **Step 3: Implement public toast API**

**`TpToastConfig`** — public fields matching current TeamPilot defaults; convert to engine `ToastificationConfig` internally (private import of engine).

**`TpToastWrapper`** — wraps engine `ToastificationWrapper(config: config.toEngine(), child: child)`.

**`TpToastAction`** — `{ label, onPressed }`.

**`TpToast`**:

```dart
abstract final class TpToast {
  static Duration defaultDuration(
    TpToastVariant variant, {
    bool hasAction = false,
  }) { /* parity: 2/3/4/5s or 8s with action */ }

  static void show(
    BuildContext context, {
    required String message,
    TpToastVariant variant = TpToastVariant.info,
    TpToastAction? action,
    Duration? duration,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty || !context.mounted) return;

    // engine.dismissAll(delayForAnimation: false);
    // resolve TpTheme.of(context).toastTheme (or fromColorScheme fallback)
    // engine.show(... flat style, icons from engine type, title via _buildTitle)
  }

  static void dismiss() {
    // engine.dismissAll(delayForAnimation: false);
  }
}
```

Map `TpToastVariant` → engine `ToastificationType` **inside** `tp_toast.dart` only (not exported).

`_buildTitle` must match current AppToast: `TpTextStyles.md` / `mdSemibold`, action `TextButton` that calls `dismiss()` then `action.onPressed`.

Default `TpToastConfig` constants: `itemWidth: 400`, `maxToastLimit: 1`, `animationDuration: 200ms`, `maxTitleLines: 3`, `maxDescriptionLines: 1`, `alignment: topEnd`.

Export: `tp_toast.dart`, `tp_toast_config.dart`, `tp_toast_wrapper.dart`, `tp_toast_theme.dart`.

**Do not** export `src/toast/engine/**` from `shared_ui.dart`.

- [ ] **Step 4: Run — expect PASS**

```bash
cd client/packages/shared_ui && flutter test test/components/toast/
```

- [ ] **Step 5: Commit**

```bash
cd client/packages/shared_ui
git add lib/src/components/toast lib/shared_ui.dart test/components/toast
git commit -m "$(cat <<'EOF'
feat: add TpToast public API over private engine

EOF
)"
```

---

### Task 4: Client facade + `main` wiring

**Files:**
- Modify: `client/lib/widgets/app_toast/app_toast.dart`
- Modify or delete: `client/lib/theme/app_toast_theme.dart`
- Modify: `client/lib/main.dart`
- Create (optional): `client/lib/theme/team_pilot_toast_config.dart` if preferred over keeping helpers in `app_toast.dart`

- [ ] **Step 1: Slim `AppToast` to wrap `TpToast`**

`AppToast.show` / `showGlobal` / `dismiss`:
- Guards + global dedupe unchanged.
- Call `TpToast.show` / `TpToast.dismiss`.
- After show: if `variant != TpToastVariant.info`, `NotificationRecorder.maybeCurrent?.record(...)`.
- Replace `AppToastAction` → use `TpToastAction`.
- `showAppToast` extension takes `TpToastVariant` / `TpToastAction`.

- [ ] **Step 2: Move desktop config into client helper**

Replace `buildAppToastificationConfig()` with `buildTeamPilotToastConfig()` returning `TpToastConfig` (same marginBuilder: `tpSpacing`, viewPadding, `kDesktopWindowTitleBarHeight` when `useCustomDesktopWindowTitleBar`).

Delete `toastificationTypeFor`, `appToastStyleFor`, `AppToastVariant`, `defaultAppToastDuration`, `appToastAccentColor` from client (now in package).

Prefer **delete** `app_toast_theme.dart` and put `buildTeamPilotToastConfig` next to `AppToast` or in `client/lib/theme/team_pilot_toast_config.dart`.

- [ ] **Step 3: Update `main.dart`**

```dart
return TpToastWrapper(
  config: buildTeamPilotToastConfig(),
  child: MaterialApp.router(
    // …
    builder: (context, child) {
      // …
      final scheme = Theme.of(context).colorScheme;
      return TpTheme(
        data: TpThemeData.fromColorScheme(
          scheme,
          scale: 1.0,
          iconScale: _cachedIconMultiplier ?? 1.0,
          controlScale: _cachedEffectiveTextMult ?? 1.0,
          toast: TpToastTheme.fromColorScheme(
            scheme,
            backgroundColor: scheme.workspaceCard, // required parity
          ),
        ),
        child: content,
      );
    },
  ),
);
```

Remove `import 'package:toastification/toastification.dart'`.

- [ ] **Step 4: Mechanical rename across client**

```bash
cd client
# Prefer carefully scoped replaces — verify with analyze
rg -l 'AppToastVariant' --glob '*.dart' lib test | while read f; do
  sed -i 's/AppToastVariant/TpToastVariant/g' "$f"
done
rg -l 'AppToastAction' --glob '*.dart' lib test | while read f; do
  sed -i 's/AppToastAction/TpToastAction/g' "$f"
done
```

Fix imports: anything that imported `app_toast_theme.dart` only for the enum should import `package:shared_ui/shared_ui.dart` (or keep importing via `app_toast.dart` if you re-export — **do not** re-export; update imports explicitly).

`AppNotification` and notification tests: `TpToastVariant`.

- [ ] **Step 5: Analyze client**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | rg 'error •' | head -40
```

Expected: no errors related to toast.

- [ ] **Step 6: Commit (teampilot)**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/widgets/app_toast client/lib/theme client/lib/main.dart \
  client/lib/models/app_notification.dart \
  # plus all renamed call sites / tests
  client/packages/shared_ui
git commit -m "$(cat <<'EOF'
feat(ui): wire TpToast and slim AppToast product facade

EOF
)"
```

---

### Task 5: Remove `packages/toastification` + docs

**Files:**
- Delete: `client/packages/toastification/**`
- Modify: `client/pubspec.yaml` (remove path dep)
- Modify: `client/packages/shared_ui/README.md`
- Modify: `docs/CODE_QUALITY.md` / `AGENTS.md` if they still say toast is client-only

- [ ] **Step 1: Drop dependency and delete package**

```yaml
# client/pubspec.yaml — remove:
# toastification:
#   path: packages/toastification
```

```bash
rm -rf client/packages/toastification
cd client && flutter pub get
```

- [ ] **Step 2: Verify no toastification imports remain**

```bash
rg 'package:toastification' client --glob '*.dart' || true
rg 'toastification' client/pubspec.yaml || true
```

Expected: no matches (except possibly historical docs — update those).

- [ ] **Step 3: README + docs**

Add to `shared_ui` README component table:

| **Toast** | `TpToast`, `TpToastWrapper`, `TpToastConfig`, `TpToastTheme`, `TpToastVariant`, `TpToastAction` |

Note engine is private vendored code under `src/toast/engine/`.

- [ ] **Step 4: Full verify**

```bash
cd client/packages/shared_ui && flutter test
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/repositories/notification_repository_test.dart \
  test/cubits/notification_cubit_test.dart \
  test/services/notification/ --exclude-tags integration
```

Expected: all green.

- [ ] **Step 5: Commit submodule + teampilot**

```bash
# shared_ui
cd client/packages/shared_ui
git add README.md
git commit -m "docs: document TpToast in README" || true

# teampilot
cd /home/hhoa/git/hhoa/teampilot
git add client/pubspec.yaml client/pubspec.lock client/packages/shared_ui \
  docs/CODE_QUALITY.md AGENTS.md
# ensure packages/toastification deletion is staged
git add -u client/packages/toastification
git commit -m "$(cat <<'EOF'
chore: remove toastification package after TpToast absorb

EOF
)"
```

---

## Acceptance checklist (from spec)

- [ ] `shared_ui` barrel exports `TpToast` / `TpToastWrapper` / `TpToastConfig` / `TpToastTheme` / `TpToastVariant` / `TpToastAction`
- [ ] No `package:toastification` in client or public shared_ui API
- [ ] `packages/toastification` removed
- [ ] Non-info `AppToast.show` still records via `NotificationRecorder`
- [ ] Desktop top margin still clears custom title bar
- [ ] TeamPilot `TpThemeData` uses `workspaceCard` toast background
- [ ] No `AppToastVariant` / `AppToastAction` types remain

---

## Notes for implementers

- **Submodule first:** land shared_ui commits on its branch, then bump the gitlink in teampilot.
- **Do not** add `export 'src/toast/engine/...'` to `shared_ui.dart`.
- If widget tests flake on animation, pump fixed durations (200–300ms) rather than only `pumpAndSettle`.
- Keep `maxToastLimit: 1` and dismiss-all-before-show behavior identical to current `AppToast._present`.
