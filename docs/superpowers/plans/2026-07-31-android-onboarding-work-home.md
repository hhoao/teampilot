# Android Onboarding Work-Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embed required Termux/SSH Connect→bind as the Android onboarding work-home step before CLI detect, replacing the save-only SSH step.

**Architecture:** Replace `OnboardingStepKind.ssh` with `workHome`. The step embeds the existing work-environment chooser + Termux/SSH Connect UIs (with `embedded` chrome so they fit the wizard viewport). Bind authority stays Connect → `select(...)`. Wizard footer blocks Skip/Next on that step until `hasBoundAndroidWorkHome`; Connect success auto-advances. StartupGate remains a safety net. If home is already bound when the wizard opens (settings reopen), omit the work-home step.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, existing Termux/SSH Connect + `ConnectionModeService`, l10n ARB.

**Spec:** `docs/superpowers/specs/2026-07-31-android-onboarding-work-home-design.md`  
**Depends on:** Termux home peer paths already landed (`WorkEnvironmentChooserPage`, `TermuxSetupPage`, `selectProfileOnConnect`).

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/pages/onboarding/onboarding_wizard.dart` | `workHome` step kind; step list; Skip/Next gating; auto-advance hook; skip workHome when already bound |
| `client/lib/pages/onboarding/steps/work_home_step.dart` | Onboarding chrome + embedded chooser / path bodies; listen for bind → `onBound` |
| `client/lib/pages/onboarding/steps/ssh_step.dart` | **Delete** (save-only path retired) |
| `client/lib/pages/termux/work_environment_chooser_page.dart` | Extract shared body; `embedded` mode (no Scaffold) for wizard + gate |
| `client/lib/pages/termux/termux_setup_page.dart` | `embedded` + optional `onHomeBound` after Connect OK |
| `client/lib/pages/ssh_profiles_page.dart` / section | Ensure SSH list usable embedded; Connect still binds via cubit |
| `client/lib/pages/ssh_profile_setup_page.dart` | Keep/finish `embedded` for nested editor inside wizard scroll |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | Work-home step title/subtitle; retire or stop using `onboardingSsh*` |
| `client/test/pages/onboarding/onboarding_wizard_test.dart` | Step list + gating tests |
| `client/test/pages/onboarding/work_home_step_test.dart` | Bind → onBound; no advance on save-only |

---

### Task 1: Step list — `workHome` replaces `ssh`

**Files:**
- Modify: `client/lib/pages/onboarding/onboarding_wizard.dart`
- Modify: `client/test/pages/onboarding/onboarding_wizard_test.dart`

- [ ] **Step 1: Write failing tests**

Replace the existing `onboardingStepsForPlatform` group that asserts `OnboardingStepKind.ssh` (that enum value will be deleted — old assertions will not compile).

```dart
group('onboardingStepsForPlatform', () {
  test('desktop has four steps without workHome', () {
    expect(
      onboardingStepsForPlatform(isAndroid: false),
      [
        OnboardingStepKind.appearance,
        OnboardingStepKind.cli,
        OnboardingStepKind.providerImport,
        OnboardingStepKind.defaultPreset,
      ],
    );
  });

  test('android includes workHome before cli when unbound', () {
    expect(
      onboardingStepsForPlatform(
        isAndroid: true,
        hasBoundAndroidWorkHome: false,
      ),
      [
        OnboardingStepKind.appearance,
        OnboardingStepKind.workHome,
        OnboardingStepKind.cli,
        OnboardingStepKind.providerImport,
        OnboardingStepKind.defaultPreset,
      ],
    );
  });

  test('android skips workHome when already bound', () {
    expect(
      onboardingStepsForPlatform(
        isAndroid: true,
        hasBoundAndroidWorkHome: true,
      ),
      isNot(contains(OnboardingStepKind.workHome)),
    );
  });
});
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/pages/onboarding/onboarding_wizard_test.dart`

Expected: FAIL (`workHome` / named params missing)

- [ ] **Step 3: Minimal implementation**

```dart
enum OnboardingStepKind {
  appearance,
  workHome,
  cli,
  providerImport,
  defaultPreset,
}

List<OnboardingStepKind> onboardingStepsForPlatform({
  bool? isAndroid,
  bool hasBoundAndroidWorkHome = false,
}) {
  final android = isAndroid ?? Platform.isAndroid;
  if (!android) {
    return const [
      OnboardingStepKind.appearance,
      OnboardingStepKind.cli,
      OnboardingStepKind.providerImport,
      OnboardingStepKind.defaultPreset,
    ];
  }
  if (hasBoundAndroidWorkHome) {
    return const [
      OnboardingStepKind.appearance,
      OnboardingStepKind.cli,
      OnboardingStepKind.providerImport,
      OnboardingStepKind.defaultPreset,
    ];
  }
  return const [
    OnboardingStepKind.appearance,
    OnboardingStepKind.workHome,
    OnboardingStepKind.cli,
    OnboardingStepKind.providerImport,
    OnboardingStepKind.defaultPreset,
  ];
}
```

In `_OnboardingWizardState.initState`, resolve steps via `ConnectionModeService` when available:

```dart
_steps = onboardingStepsForPlatform(
  hasBoundAndroidWorkHome:
      context.read<ConnectionModeService>().hasBoundAndroidWorkHome,
);
```

(If `initState` cannot `read` yet, resolve in first frame / constructor injection — prefer reading in `initState` only if providers are above the wizard, which they are under `OnboardingGate`.)

Temporarily map `workHome` to a `SizedBox.shrink()` placeholder until Task 3 (or fail compile — better add stub widget file in same commit if needed).

Remove `OnboardingStepKind.ssh` and `ssh_step` import once stub exists.

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/onboarding/onboarding_wizard.dart \
  client/test/pages/onboarding/onboarding_wizard_test.dart
git commit -m "feat(onboarding): replace Android SSH step with workHome list"
```

---

### Task 2: Embeddable chooser + Termux setup chrome

**Files:**
- Modify: `client/lib/pages/termux/work_environment_chooser_page.dart`
- Modify: `client/lib/pages/termux/termux_setup_page.dart`
- Modify: `client/test/pages/termux/termux_setup_page_test.dart` (if needed)
- Optional: extract `WorkEnvironmentChooserBody` / keep single file with `embedded`

- [ ] **Step 1: Failing widget test (chooser embedded has no Scaffold/AppBar)**

```dart
testWidgets('embedded chooser has no AppBar', (tester) async {
  await tester.pumpWidget(
    // MaterialApp + TpTheme + providers …
    const WorkEnvironmentChooserPage(embedded: true),
  );
  expect(find.byType(AppBar), findsNothing);
  expect(find.textContaining('Termux'), findsWidgets);
});
```

- [ ] **Step 2: Run — expect FAIL** (`embedded` missing)

- [ ] **Step 3: Implement**

`WorkEnvironmentChooserPage`:

```dart
const WorkEnvironmentChooserPage({
  super.key,
  this.embedded = false,
  this.onChooseTermux,
  this.onChooseSsh,
});

final bool embedded;
/// When set (onboarding), call instead of Navigator.push.
final VoidCallback? onChooseTermux;
final VoidCallback? onChooseSsh;
```

- If `embedded`: return body `Column`/`ListView` only (tiles).  
- `onTap`: if callbacks non-null → call them; else existing `_pushWithGateProviders`.  
- Extract `_EnvironmentTile` stays private in-file.

`TermuxSetupPage`:

```dart
const TermuxSetupPage({
  super.key,
  this.embedded = false,
  this.onHomeBound,
});

final bool embedded;
final VoidCallback? onHomeBound;
```

**Embedded contract (locked):** `embedded: true` means:
- no `Scaffold` / `AppBar`
- form body only
- after successful `connect()`: toast + `onHomeBound?.call()` — **do not** call `Navigator.popUntil(...)` (today’s success path uses `popUntil(isFirst)`, which would tear down GoRouter / shell when the wizard replaced `OnboardingGate` content or was reopened from settings)
- clear-setup / other exits that `popUntil` must likewise no-op or only `maybePop` when embedded

Gate-pushed (non-embedded) path keeps existing `popUntil` behavior.

- [ ] **Step 4: Tests PASS** (update existing Termux setup tests if they assume Scaffold; add case that embedded connect does not pop)

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/termux/work_environment_chooser_page.dart \
  client/lib/pages/termux/termux_setup_page.dart \
  client/test/pages/termux/
git commit -m "feat(termux): support embedded chooser and setup for onboarding"
```

---

### Task 3: `OnboardingWorkHomeStep` + l10n

**Files:**
- Create: `client/lib/pages/onboarding/steps/work_home_step.dart`
- Create: `client/test/pages/onboarding/work_home_step_test.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` (+ generated locals via flutter gen-l10n as project does)
- Delete: `client/lib/pages/onboarding/steps/ssh_step.dart`
- Modify: `client/lib/pages/onboarding/onboarding_wizard.dart` (wire real step)
- Modify: `client/lib/pages/ssh_profiles_page.dart` — ensure `embedded: true` usable as body; optional `onHomeBound` via listening parent

- [ ] **Step 1: ARB strings**

```json
"onboardingWorkHomeTitle": "Choose work environment",
"onboardingWorkHomeSubtitle": "Connect Termux on this device or a remote SSH host before detecting AI CLIs.",
```

中文：

```json
"onboardingWorkHomeTitle": "选择工作环境",
"onboardingWorkHomeSubtitle": "先连接本机 Termux 或远程 SSH，再检测 AI CLI。",
```

Stop referencing `onboardingSshTitle` / `onboardingSshSubtitle` (may leave keys unused until a later cleanup — do not expand scope to mass-delete ARB unless trivial).

- [ ] **Step 2: Failing tests for work-home step**

Mirror provider setup from `termux_setup_page_test.dart` (`TermuxCubit` spy, `SessionPreferencesCubit`, `ConnectionModeService`, `SshProfileCubit`, MaterialApp + TpTheme + l10n).

```dart
testWidgets('Termux onHomeBound notifies parent', (tester) async {
  var boundCalls = 0;
  // Pump OnboardingWorkHomeStep(onBound: () => boundCalls++).
  // Navigate to Termux subpage; drive SpyTermuxCubit connect success
  // (or invoke TermuxSetupPage.onHomeBound).
  expect(boundCalls, 1);
});

testWidgets('SSH Connect notifies via SessionPreferencesCubit watch',
    (tester) async {
  var boundCalls = 0;
  // Pump step; open SSH subpage; simulate home bind by updating the same
  // preference/home signal StartupGate watches, then pump.
  // Assert onBound fired. Do not watch ConnectionModeService directly.
  expect(boundCalls, 1);
});

testWidgets('saving SSH profile alone does not call onBound', (tester) async {
  var boundCalls = 0;
  // Open SSH path, save profile without Connect; boundCalls stays 0.
  expect(boundCalls, 0);
});
```

- [ ] **Step 3: Implement `OnboardingWorkHomeStep`**

```dart
class OnboardingWorkHomeStep extends StatefulWidget {
  const OnboardingWorkHomeStep({
    super.key,
    required this.onBound,
  });

  final VoidCallback onBound;
  // …
}

enum _WorkHomeSubpage { chooser, termux, ssh }
```

Structure:

- `OnboardingStepScaffold(title/subtitle from l10n, body: …)`  
- Subpage state: chooser | termux | ssh  
- Chooser: `WorkEnvironmentChooserPage(embedded: true, onChooseTermux: …, onChooseSsh: …)`  
- Termux: `TermuxSetupPage(embedded: true, onHomeBound: widget.onBound)` + back-to-chooser control  
- SSH: `SshProfilesPage(embedded: true)` (or `SshProfilesSection` in scroll) + back-to-chooser  
- SSH Connect binds via `SshConnectionCubit` + `selectProfileOnConnect`. **Do not** `watch`/`listen` `ConnectionModeService` — it is a plain derived service, not a Listenable. Mirror `StartupGate`: `context.watch<SessionPreferencesCubit>()` (rebuild on home change), then `context.read<ConnectionModeService>().hasBoundAndroidWorkHome`. When true, call `onBound` once (guard with `_didNotify`). Termux path may also fire `onHomeBound` directly; the watch covers SSH and any other bind.

Do **not** call `onBound` from profile save.

Delete `ssh_step.dart`. Wire wizard:

```dart
OnboardingStepKind.workHome => OnboardingWorkHomeStep(
  onBound: () => unawaited(_goNext()),
),
```

Ensure nested SSH editor uses `SshProfileSetupPage(embedded: true)` if opened inside the step (finish any in-progress embedded refactor).

- [ ] **Step 4: Tests PASS + `flutter gen-l10n` if required by project**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/onboarding/steps/work_home_step.dart \
  client/lib/pages/onboarding/steps/ssh_step.dart \
  client/lib/pages/onboarding/onboarding_wizard.dart \
  client/lib/pages/ssh_profile_setup_page.dart \
  client/lib/pages/ssh_profiles_page.dart \
  client/lib/l10n/ \
  client/test/pages/onboarding/work_home_step_test.dart
git commit -m "feat(onboarding): Android work-home step with Termux/SSH Connect"
```

---

### Task 4: Wizard footer gating (no Skip / blocked Next)

**Files:**
- Modify: `client/lib/pages/onboarding/onboarding_wizard.dart`
- Modify: `client/test/pages/onboarding/onboarding_wizard_test.dart`

- [ ] **Step 1: Failing widget tests**

```dart
testWidgets('workHome step hides Skip and disables Next until bound', …);
testWidgets('Skip still works on appearance', …);
```

Pump wizard with `isAndroid: true` forced via injecting steps list if needed (test seam: optional `steps:` on `OnboardingWizard` for tests only is OK if kept `@visibleForTesting`).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

```dart
bool get _isWorkHomeStep =>
    _pageIndex < _steps.length &&
    _steps[_pageIndex] == OnboardingStepKind.workHome;

// In build(), mirror StartupGate so Next re-enables after bind:
context.watch<SessionPreferencesCubit>();
final workHomeBound =
    context.read<ConnectionModeService>().hasBoundAndroidWorkHome;

// Skip button:
onPressed: navigationLocked || _isWorkHomeStep
    ? null
    : _skip,
// Or omit Skip widget entirely when _isWorkHomeStep.

// Next:
onPressed: navigationLocked || (_isWorkHomeStep && !workHomeBound)
    ? null
    : () => unawaited(_goNext()),
```

In `_goNext`, defensive guard:

```dart
if (_isWorkHomeStep &&
    !context.read<ConnectionModeService>().hasBoundAndroidWorkHome) {
  return;
}
```

Auto-advance remains via `OnboardingWorkHomeStep.onBound` → `_goNext`.

- [ ] **Step 4: PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/onboarding/onboarding_wizard.dart \
  client/test/pages/onboarding/onboarding_wizard_test.dart
git commit -m "fix(onboarding): block Skip/Next on Android work-home step"
```

---

### Task 5: Smoke — CLI path after bind + analyze

**Files:**
- Optionally light touch: `client/test/pages/onboarding/cli_step_test.dart` if it mocks connection mode
- No product change if CLI already branches on `isRemoteWorkPlane`

- [ ] **Step 1: Confirm CLI step test covers remote when `isRemoteWorkPlane`**

If missing, add a focused unit/widget test that with bound SSH/Termux mode, detect calls remote locate (mock `SshClientFactory` / discovery) — only if cheap; do not rewrite CLI step.

- [ ] **Step 2: Run targeted suite**

```bash
cd client && flutter test \
  test/pages/onboarding/ \
  test/pages/termux/ \
  test/services/app/connection_mode_service_test.dart
```

Expected: PASS

- [ ] **Step 3: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/pages/onboarding/ \
  lib/pages/termux/ \
  lib/pages/ssh_profiles_page.dart \
  lib/pages/ssh_profile_setup_page.dart
```

- [ ] **Step 4: Manual checklist (document in commit body or PR)**

1. Fresh Android: Appearance → Work home (cannot Skip) → Connect Termux or SSH → lands on CLI with remote detect  
2. Save SSH profile without Connect → still on work home  
3. Complete wizard → StartupGate does not show chooser  
4. Clear Termux/SSH home → StartupGate chooser returns  
5. Reopen wizard with bound home → no work-home step  
6. Desktop onboarding unchanged  

- [ ] **Step 5: Final commit if any test-only fixes**

```bash
git commit -m "test(onboarding): cover work-home gating and remote CLI precondition"
```

---

## Out of scope

- Shared-storage migration  
- Merging OnboardingGate and StartupGate  
- Desktop work-home step  
- Moving CLI out of the wizard  
