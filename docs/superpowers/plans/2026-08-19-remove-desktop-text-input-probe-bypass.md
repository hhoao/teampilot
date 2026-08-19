# Remove Desktop Text Input Probe Bypass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove TeamPilot's desktop text-input probe bypass, including its custom binding, platform-channel interception, startup self-check, diagnostics, and dedicated tests.

**Architecture:** Restore the normal Flutter binding in `main.dart`. Delete the self-contained custom binding and messenger; affected probes return to Flutter's normal platform-channel path.

**Tech Stack:** Flutter/Dart, `flutter_test`, repository-standard `flutter analyze` and test commands.

## Global Constraints

- Do not modify unrelated existing working-tree changes.
- Do not add a replacement bypass or platform-channel interception.
- Keep all startup behavior after binding initialization unchanged.
- Remove all references to `DesktopTextInputProbeBypass`, `TeampilotWidgetsFlutterBinding`, and `Teampilot probe bypass`.

---

### Task 1: Restore standard Flutter bootstrap

**Files:**
- Modify: `client/lib/main.dart`

**Interfaces:**
- Consumes: Flutter's existing `WidgetsFlutterBinding.ensureInitialized()` API.
- Produces: The existing `binding` value passed to `preserveBootSplash(binding)` without a TeamPilot-specific messenger wrapper or startup probe check.

- [ ] **Step 1: Replace the custom initialization and remove the self-check**

At the beginning of `main()`, the resulting initialization must be exactly:

```dart
  final binding = WidgetsFlutterBinding.ensureInitialized();
  unawaited(LivePerfDriver.ensureStarted());
```

Delete the existing `TeampilotWidgetsFlutterBinding.ensureInitialized()` call, binding type print, `expectBypass` calculation, messenger type guard, and `SystemChannels.platform` self-check through the end of that bypass block. Keep `preserveBootSplash(binding);` and all later startup code unchanged.

- [ ] **Step 2: Remove imports used only by the bypass**

Delete these imports from `client/lib/main.dart`:

```dart
import 'app/teampilot_widgets_flutter_binding.dart';
import 'services/app/desktop_text_input_probe_bypass.dart';
import 'package:flutter/services.dart';
```

Only remove the Flutter services import if no other reference remains in `main.dart` after Step 1.

- [ ] **Step 3: Format and inspect the focused diff**

Run:

```bash
cd client
dart format lib/main.dart
git diff -- lib/main.dart
```

Expected: only the binding setup and bypass-only imports change in `main.dart`; unrelated startup code is unchanged.

### Task 2: Delete the self-contained implementation and tests

**Files:**
- Delete: `client/lib/app/teampilot_widgets_flutter_binding.dart`
- Delete: `client/lib/services/app/desktop_text_input_probe_bypass.dart`
- Delete: `client/test/services/app/desktop_text_input_probe_bypass_test.dart`

**Interfaces:**
- Consumes: The removed references from Task 1.
- Produces: No TeamPilot-owned implementation or test of the desktop text-input probe bypass.

- [ ] **Step 1: Confirm feature-local references before deletion**

Run:

```bash
rg -n 'TeampilotWidgetsFlutterBinding|DesktopTextInputProbeBypass|shouldInstallDesktopTextInputProbeBypass|bypassHitCount|bypassMissCount' client --glob '*.dart'
```

Expected: matches are limited to the three feature files and the `main.dart` references being removed in Task 1.

- [ ] **Step 2: Delete exactly the three feature files**

Remove the three paths listed in this task. Do not remove unrelated terminal or integration-test probe utilities.

- [ ] **Step 3: Confirm no stale feature references remain**

Run:

```bash
rg -n -S 'DesktopTextInputProbeBypass|TeampilotWidgetsFlutterBinding|Teampilot probe bypass' client/lib client/test
```

Expected: no output.

### Task 3: Verify the removal

**Files:**
- Verify: `client/lib/main.dart` and the three deleted feature paths

**Interfaces:**
- Consumes: The source and test deletion from Tasks 1-2.
- Produces: Evidence that the app still analyzes and the relevant non-integration tests pass with the default Flutter binding.

- [ ] **Step 1: Run remaining app-service tests**

Run:

```bash
cd client
flutter test test/services/app --exclude-tags integration
```

Expected: exit code 0. The deleted dedicated bypass test is intentionally absent.

- [ ] **Step 2: Run repository-standard static analysis**

Run:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: exit code 0 with no new errors from the removal.

- [ ] **Step 3: Inspect final scope and whitespace**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Expected: only `main.dart`, the three feature-file deletions, and the design/plan documents are attributable to this task; pre-existing unrelated modifications remain untouched.
