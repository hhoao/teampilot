# Android SSH Startup List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On SSH-gated startup, show the SSH profile list instead of the add form; make add/edit dismissible; clear the gate only after Connect switches home to SSH.

**Architecture:** `StartupGate` hosts `SshProfilesPage`. Android add/edit stays on `Navigator.push` via `openSshProfileEditor` (save/`maybePop` already return to the list). Extract `applyAndroidSshConnectHome` so Connect runs `HomeTargetController.select('ssh:$id')` then `SshProfileCubit.selectProfile(id)`, replacing the gate’s save-time home select.

**Tech Stack:** Flutter, flutter_bloc, existing `ConnectionModeService` / `StartupGate` / `SshProfilesPage` / `SshConnectionCubit.selectProfileOnConnect`.

**Spec:** `docs/superpowers/specs/2026-07-29-android-ssh-startup-list-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/ssh/android_ssh_connect_home.dart` | Pure helper: home select + profile select after Android Connect |
| `client/lib/app/app_shell.dart` | Wire Android `selectProfileOnConnect` through the helper; declare `late` `homeTargetController` so the closure can capture it |
| `client/lib/pages/startup_gate.dart` | Gate UI → `SshProfilesPage`; drop inline setup + save-home path; optional `isAndroid` for tests |
| `client/lib/pages/ssh_profiles_page.dart` | `openSshProfileEditor({bool? useFullPageEditor})` test/host override (defaults to `Platform.isAndroid`) |
| `client/test/services/ssh/android_ssh_connect_home_test.dart` | Helper call order / args |
| `client/test/pages/startup_gate_test.dart` | Gate shows list; full-page add push/pop; home switch clears gate |

---

### Task 1: `applyAndroidSshConnectHome` helper

**Files:**
- Create: `client/lib/services/ssh/android_ssh_connect_home.dart`
- Create: `client/test/services/ssh/android_ssh_connect_home_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/android_ssh_connect_home.dart';

void main() {
  test('selects home ssh:id then selectProfile', () async {
    final calls = <String>[];
    await applyAndroidSshConnectHome(
      profileId: 'p1',
      selectHome: (id) async => calls.add('home:$id'),
      selectProfile: (id) async => calls.add('profile:$id'),
    );
    expect(calls, ['home:ssh:p1', 'profile:p1']);
  });
}
```

- [ ] **Step 2: Run test — expect FAIL** (library missing)

Run: `cd client && flutter test test/services/ssh/android_ssh_connect_home_test.dart`

Expected: FAIL — target URI does not exist / function not defined.

- [ ] **Step 3: Implement helper**

```dart
/// Android Connect side-effect: switch home to the connected profile, then
/// persist the selected profile id (existing cubit path).
Future<void> applyAndroidSshConnectHome({
  required String profileId,
  required Future<void> Function(String homeId) selectHome,
  required Future<void> Function(String profileId) selectProfile,
}) async {
  await selectHome('ssh:$profileId');
  await selectProfile(profileId);
}
```

- [ ] **Step 4: Run test — expect PASS**

Run: `cd client && flutter test test/services/ssh/android_ssh_connect_home_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/ssh/android_ssh_connect_home.dart \
  client/test/services/ssh/android_ssh_connect_home_test.dart
git commit -m "$(cat <<'EOF'
feat(ssh): add Android connect home-select helper

EOF
)"
```

---

### Task 2: Wire Connect in `app_shell`

**Files:**
- Modify: `client/lib/app/app_shell.dart` (around `sshConnectionCubit` construction ~970 and `homeTargetController` ~1196)

- [ ] **Step 1: Make `homeTargetController` late so Connect can close over it**

Near other `late final` locals in `buildAppShell` / bootstrap function, add:

```dart
late final HomeTargetController homeTargetController;
```

Replace the later `final homeTargetController = HomeTargetController(...)` with:

```dart
homeTargetController = HomeTargetController(
  registry: runtimeTargetRegistry,
  current: defaultTargetResolver,
  switchTo: switchHomeTarget,
);
```

- [ ] **Step 2: Point Android `selectProfileOnConnect` at the helper**

Import `android_ssh_connect_home.dart`. Change:

```dart
selectProfileOnConnect: Platform.isAndroid
    ? (id) => sshProfileCubit.selectProfile(id)
    : null,
```

to:

```dart
selectProfileOnConnect: Platform.isAndroid
    ? (id) => applyAndroidSshConnectHome(
        profileId: id,
        selectHome: homeTargetController.select,
        selectProfile: sshProfileCubit.selectProfile,
      )
    : null,
```

Note: Connect is only invoked after UI is up, so `homeTargetController` is assigned before any call. Double reload (`select` then `selectProfile` → `onActiveProfileChanged`) is acceptable for this change.

- [ ] **Step 3: Analyze touched file**

Run: `cd client && dart analyze lib/app/app_shell.dart lib/services/ssh/android_ssh_connect_home.dart`

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "$(cat <<'EOF'
feat(ssh): switch home on Android Connect

EOF
)"
```

---

### Task 3: Full-page editor override + `StartupGate` list (TDD)

**Files:**
- Modify: `client/lib/pages/ssh_profiles_page.dart` (`openSshProfileEditor`)
- Modify: `client/lib/pages/startup_gate.dart`
- Create: `client/test/pages/startup_gate_test.dart`

Reuse provider patterns from `client/test/pages/ssh_profiles/ssh_profiles_section_test.dart`. Host CI is Linux/macOS — do **not** rely on `Platform.isAndroid` for full-page editor tests.

- [ ] **Step 1: Add `useFullPageEditor` override on `openSshProfileEditor`**

```dart
Future<void> openSshProfileEditor(
  BuildContext context, {
  SshProfile? profile,
  bool? useFullPageEditor,
}) async {
  final fullPage = useFullPageEditor ?? Platform.isAndroid;
  if (fullPage) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SshProfileSetupPage(
          // ... unchanged ...
        ),
      ),
    );
    return;
  }
  await showSshProfileFormDialog(context, profile: profile);
}
```

Production callers stay unchanged (`useFullPageEditor` omitted → Android full page, desktop dialog).

For the gate Add-button path in tests, either:
- call `openSshProfileEditor(context, useFullPageEditor: true)` from a test-only button, **or**
- temporarily wrap the list’s Add action in the test harness by pumping `SshProfilesPage` and invoking the editor with the override via a small test helper that mirrors the Add button.

Preferred in `startup_gate_test.dart`: after pumping the gated list, call:

```dart
final ctx = tester.element(find.byType(SshProfilesPage));
await openSshProfileEditor(ctx, useFullPageEditor: true);
await tester.pumpAndSettle();
```

That avoids depending on `Platform.isAndroid` inside `SshProfilesSection`.

- [ ] **Step 2: Write failing widget tests**

Harness skeleton (align with section test `_host`):

```dart
Future<Widget> gateHost({
  required ConnectionModeService mode,
  required SshProfileCubit profileCubit,
  required SshConnectionCubit connectionCubit,
  required SshCredentialStore credentialStore,
  required TerminalTransportFactory transportFactory,
  required SshProfileRepository profileRepository,
  required SessionPreferencesCubit sessionPrefs,
  bool? isAndroid,
  Widget child = const Text('APP_CHILD'),
}) async {
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    // Wrap with TpTheme like ssh_profiles_section_test `_host` (TpTextStyles).
    home: MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ConnectionModeService>.value(value: mode),
        RepositoryProvider.value(value: credentialStore),
        RepositoryProvider.value(value: profileRepository),
        RepositoryProvider.value(value: transportFactory),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: profileCubit),
          BlocProvider.value(value: connectionCubit),
          BlocProvider.value(value: sessionPrefs),
        ],
        child: StartupGate(isAndroid: isAndroid, child: child),
      ),
    ),
  );
}
```

Tests:

```dart
testWidgets('gated startup shows SSH list, not bare setup title', (tester) async {
  final mode = ConnectionModeService(
    defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
    hasSshProfiles: () => false,
  );
  // empty SshProfileCubit (not loading), session prefs, connection cubit, repos…
  await tester.pumpWidget(await gateHost(mode: mode, /* … */));
  await tester.pumpAndSettle();

  expect(find.text('新增 SSH Profile'), findsNothing);
  expect(find.text('APP_CHILD'), findsNothing);
  expect(find.text(l10n.sshProfilesEmpty), findsOneWidget);
});

testWidgets('full-page editor push/pop returns to list', (tester) async {
  // Same gated empty-list harness
  await tester.pumpWidget(await gateHost(/* … */));
  await tester.pumpAndSettle();

  final ctx = tester.element(find.byType(SshProfilesPage));
  await openSshProfileEditor(ctx, useFullPageEditor: true);
  await tester.pumpAndSettle();
  expect(find.text('新增 SSH Profile'), findsOneWidget);

  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.text('新增 SSH Profile'), findsNothing);
  expect(find.text(l10n.sshProfilesEmpty), findsOneWidget);
});

testWidgets('save does not clear gate (still list, not APP_CHILD)', (tester) async {
  // Harness: isAndroid: true + local home + hasProfiles starts false.
  // After save, profiles exist but home stays local → androidNeedsSshHome still true.
  // Do NOT use "ssh home + empty profiles" here — saving would clear requiresSshProfileSetup
  // without Connect and falsely show APP_CHILD.
  // Open full-page editor; fill required fields; tap 保存 Profile.
  // Expect: popped to list; find.text('APP_CHILD') still missing.
});

testWidgets('after home becomes ssh:*, rebuilding gate shows child', (tester) async {
  var homeId = 'local';
  RuntimeTarget current() => homeId == 'local'
      ? RuntimeTarget.local()
      : RuntimeTarget.ssh('p1', label: 'box');

  // First pump: hasProfiles true, isAndroid: true, local home → androidNeedsSshHome → list
  await tester.pumpWidget(await gateHost(
    mode: ConnectionModeService(
      defaultTargetResolver: current,
      hasSshProfiles: () => true,
    ),
    isAndroid: true,
    // seed one profile in cubit
  ));
  await tester.pumpAndSettle();
  expect(find.text('APP_CHILD'), findsNothing);

  await applyAndroidSshConnectHome(
    profileId: 'p1',
    selectHome: (id) async => homeId = id,
    selectProfile: (_) async {},
  );

  // Rebuild with same resolvers (homeId now ssh:p1) — do not rely on watch alone
  await tester.pumpWidget(await gateHost(
    mode: ConnectionModeService(
      defaultTargetResolver: current,
      hasSshProfiles: () => true,
    ),
    isAndroid: true,
  ));
  await tester.pumpAndSettle();
  expect(find.text('APP_CHILD'), findsOneWidget);
});
```

- [ ] **Step 3: Run tests — expect FAIL**

Run: `cd client && flutter test test/pages/startup_gate_test.dart`

Expected: FAIL — gate still shows setup / missing APIs.

- [ ] **Step 4: Implement gate + editor override**

`StartupGate`:

```dart
class StartupGate extends StatelessWidget {
  const StartupGate({
    super.key,
    required this.child,
    this.isAndroid,
  });

  final Widget child;
  /// Test override; defaults to `Platform.isAndroid`.
  final bool? isAndroid;

  @override
  Widget build(BuildContext context) {
    context.watch<SessionPreferencesCubit>();
    final mode = context.read<ConnectionModeService>();
    final android = isAndroid ?? Platform.isAndroid;
    final androidNeedsSshHome = android && !mode.isSshMode;
    if (!mode.isSshMode && !androidNeedsSshHome) return child;

    final sshState = context.watch<SshProfileCubit>().state;
    if (sshState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (mode.requiresSshProfileSetup || androidNeedsSshHome) {
      return const SshProfilesPage();
    }
    return child;
  }
}
```

Remove unused imports from `startup_gate.dart`. Apply Step 1’s `useFullPageEditor` change if not already done.

- [ ] **Step 5: Run tests — expect PASS**

Run: `cd client && flutter test test/pages/startup_gate_test.dart test/pages/ssh_profiles/ssh_profiles_section_test.dart`

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/startup_gate.dart \
  client/lib/pages/ssh_profiles_page.dart \
  client/test/pages/startup_gate_test.dart
git commit -m "$(cat <<'EOF'
fix(ssh): land gated startup on SSH list page

EOF
)"
```

---

### Task 4: Verification sweep

**Files:** none (run only)

- [ ] **Step 1: Analyze + targeted tests**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test \
  test/services/ssh/android_ssh_connect_home_test.dart \
  test/pages/startup_gate_test.dart \
  test/pages/ssh_profiles/ssh_profiles_section_test.dart \
  test/cubits/ssh_connection_cubit_test.dart \
  test/services/app/connection_mode_service_test.dart
```

Expected: analyze clean enough for repo policy; all listed tests PASS.

- [ ] **Step 2: Manual Android check (if emulator available)**

1. Clear app data / no SSH profiles → first screen is list (empty + Add).
2. Add profile → can Back without saving; Save returns to list (still gated).
3. Connect succeeding profile → main app appears.

- [ ] **Step 3: Final commit only if sweep left dirty files**

Otherwise done — no empty commit.

---

## Out of scope (do not implement)

- Onboarding wizard `OnboardingSshStep`
- `/config/ssh-profiles` cold-start redirect
- Requiring connected UI status beyond existing Connect + home switch
- Redesigning add-form fields
