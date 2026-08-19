# Test Runtime Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with verification checkpoints.

**Goal:** Reduce Flutter test startup and waiting overhead while making the managed-provider widget suite fail fast and cleanly.

**Architecture:** Keep `flutter_test_config.dart` limited to process-independent test cleanup. Load Alacritty Rust only from test files that exercise the native terminal layer. Make managed-provider page tests explicitly await Cubit readiness and coordinator shutdown, then replace only risky unbounded settling with bounded frame pumping.

**Tech Stack:** Flutter 3.47, Dart test/flutter_test, flutter_bloc, flutter_alacritty Rust bridge, existing `post_frame_test_harness.dart` helpers.

## Global Constraints

- Preserve all existing user modifications and submodule states.
- Keep `dart run tool/run_tests.dart` as the default unit/widget test entry point; it excludes `integration` by default.
- Do not change product behavior or integration-test tags.
- Use `apply_patch` for source edits.
- Run focused verification after each task and full relevant verification before completion.

---

### Task 1: Make managed-provider page tests deterministic and leak-free

**Files:**
- Modify: `client/test/pages/managed_providers/managed_provider_management_page_test.dart:88-148`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart`

**Interfaces:**
- Consumes: `ManagedProviderCubit.load()`, `ManagedProviderUsageCubit.load()`, `ManagedProviderUsageCoordinator.close()`.
- Produces: `pumpPage()` that waits for the page’s post-frame startup and both Cubit loads before assertions; teardown that closes all test-owned resources.

- [ ] **Step 1: Confirm the existing regression is red**

Run:

```bash
cd client
flutter test --no-test-assets test/pages/managed_providers/managed_provider_management_page_test.dart --plain-name="renders cached usage without starting a network query" --reporter expanded
```

Expected: the test fails at the cached measure assertion and/or does not exit promptly, reproducing the observed lifecycle problem.

- [ ] **Step 2: Add explicit coordinator ownership and readiness waiting**

In `main()`, add a `late ManagedProviderUsageCoordinator coordinator;` variable. Assign the coordinator in `setUp`, and construct `usageCubit` from that variable. In `tearDown`, close `providerCubit`, `usageCubit`, and `coordinator`.

Replace the end of `pumpPage` with:

```dart
    await tester.pump();
    await Future.wait<void>([
      providerCubit.load(),
      usageCubit.load(),
    ]);
    await tester.pump();
```

This first runs the page’s post-frame callback, then awaits the exact async work that the test owns, and finally paints the loaded state without waiting for unrelated frames.

- [ ] **Step 3: Run the regression test and the complete page file**

Run:

```bash
cd client
flutter test --no-test-assets test/pages/managed_providers/managed_provider_management_page_test.dart --plain-name="renders cached usage without starting a network query" --reporter expanded
flutter test --no-test-assets test/pages/managed_providers/managed_provider_management_page_test.dart --reporter failures-only
```

Expected: the cached test and the full page file pass, and the process exits without the 40–45 second timeout.

### Task 2: Remove unconditional Rust startup from the global test config

**Files:**
- Modify: `client/test/flutter_test_config.dart:1-17`
- Modify: `client/test/support/rust_lib_test_init.dart:11-17`
- Test: `client/test/services/ai_history/edit_codecs/tool_args_test.dart`

**Interfaces:**
- Consumes: existing `initRustLibForTests()` and the global debounce/throttle cleanup.
- Produces: idempotent explicit Rust initialization for native-terminal tests; pure tests no longer load Alacritty through `testExecutable`.

- [ ] **Step 1: Record the baseline startup behavior**

Run:

```bash
cd client
/usr/bin/time -f 'elapsed=%E' flutter test --no-test-assets test/services/ai_history/edit_codecs/tool_args_test.dart --reporter silent
```

Record the elapsed time and confirm the test passes before changing bootstrap code.

- [ ] **Step 2: Add a cached initialization future**

In `rust_lib_test_init.dart`, add a private `Future<void>?` field and make `initRustLibForTests()` return the existing future when present. Keep path resolution and `RustLib.init` inside the one initialization future.

The resulting public signature remains:

```dart
Future<void> initRustLibForTests()
```

- [ ] **Step 3: Remove Rust initialization from `testExecutable`**

Delete the `rust_lib_test_init.dart` import and `await initRustLibForTests();` from `flutter_test_config.dart`. Keep the existing `tearDown` that cancels `Throttles` and `Debounces`.

- [ ] **Step 4: Verify pure test bootstrap and timer cleanup**

Run:

```bash
cd client
flutter test --no-test-assets test/services/ai_history/edit_codecs/tool_args_test.dart --reporter failures-only
flutter test --no-test-assets test/utils/throttles_test.dart --reporter failures-only
```

Expected: both pass without requiring Alacritty Rust initialization.

### Task 3: Opt native-terminal tests into Rust initialization

**Files:**
- Modify: every test file under `client/test` that directly imports `flutter_alacritty` or calls a native terminal engine API.
- Modify: `client/test/cubits/content_search/content_search_cubit_test.dart`, `client/test/services/search/content_search_runner_test.dart`, `client/test/services/search/content_replacer_test.dart`, and `client/test/services/file_tree/workspace_content_search_service_test.dart` only if their native search setup requires a separate existing bootstrap.
- Test: the affected terminal and search test files.

**Interfaces:**
- Consumes: `initRustLibForTests()` from `test/support/rust_lib_test_init.dart`.
- Produces: each native-terminal test suite explicitly initializes the library once via `setUpAll`.

- [ ] **Step 1: Build the opt-in list from imports and native API usage**

Run:

```bash
rg -l "package:flutter_alacritty|RustLib\.instance|TerminalEngine|Alacritty" client/test -g '*_test.dart' | sort
```

For each listed test that executes Alacritty Rust APIs, add:

```dart
import '../../support/rust_lib_test_init.dart';

void main() {
  setUpAll(initRustLibForTests);
  // existing tests
}
```

Use the file’s existing relative import depth and preserve any existing `main()` setup.

- [ ] **Step 2: Run representative native suites**

Run:

```bash
cd client
flutter test --no-test-assets test/services/terminal/terminal_session_test.dart --reporter failures-only
flutter test --no-test-assets test/services/terminal/workspace_terminal_session_ops_test.dart --reporter failures-only
flutter test --no-test-assets test/cubits/chat_cubit_ask_user_answer_test.dart --reporter failures-only
```

Expected: native tests pass after explicit initialization.

- [ ] **Step 3: Run representative pure suites again**

Run:

```bash
cd client
flutter test --no-test-assets test/services/ai_history/edit_codecs/tool_args_test.dart --reporter failures-only
flutter test --no-test-assets test/services/provider_usage/managed_provider_usage_coordinator_test.dart --reporter failures-only
```

Expected: pure suites pass without native-terminal setup.

### Task 4: Add bounded waiting to the highest-risk widget tests

**Files:**
- Modify: `client/test/support/post_frame_test_harness.dart`
- Modify: `client/test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart`
- Modify: `client/test/pages/expert_hub/expert_editor_dialog_test.dart` only for waits proven to require animation completion.
- Test: the modified widget suites.

**Interfaces:**
- Consumes: `WidgetTester.pump`, existing `pumpPhaseTransitions`, and test-owned readiness predicates.
- Produces: a bounded `pumpUntil` helper with a descriptive timeout, used instead of unbounded settling in targeted tests.

- [ ] **Step 1: Write a failing timeout-behavior test for the helper**

Add a focused test in `client/test/support/pump_until_test.dart` that mounts a widget which never satisfies a predicate, calls `pumpUntil` with a short timeout, and expects a `TestFailure` containing the supplied description.

- [ ] **Step 2: Run the helper test to verify it fails**

Run:

```bash
cd client
flutter test --no-test-assets test/support/pump_until_test.dart --reporter expanded
```

Expected: failure because `pumpUntil` does not exist.

- [ ] **Step 3: Implement the minimal bounded helper**

Add to `post_frame_test_harness.dart`:

```dart
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  String description = 'widget condition',
  Duration timeout = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 16),
}) async {
  var elapsed = Duration.zero;
  while (!predicate()) {
    if (elapsed >= timeout) {
      throw TestFailure('Timed out waiting for $description');
    }
    await tester.pump(step);
    elapsed += step;
  }
}
```

- [ ] **Step 4: Run the helper test to verify it passes**

Run:

```bash
cd client
flutter test --no-test-assets test/support/pump_until_test.dart --reporter failures-only
```

Expected: pass.

- [ ] **Step 5: Replace only targeted high-risk settles**

In the IDE shell and expert editor tests, replace waits whose purpose is “wait for a known widget/state” with `pumpUntil` and a precise predicate. Keep `pumpAndSettle` where the test specifically verifies animation completion and no continuous-frame source exists.

- [ ] **Step 6: Run targeted widget verification**

Run:

```bash
cd client
flutter test --no-test-assets test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart --reporter failures-only
flutter test --no-test-assets test/pages/expert_hub/expert_editor_dialog_test.dart --reporter failures-only
```

Expected: both pass without an unbounded settle timeout.

### Task 5: Verify the optimized test boundary

**Files:**
- Modify: none unless verification exposes a regression.
- Test: affected unit/widget suites and static analysis.

- [ ] **Step 1: Run the affected changed-test set with controlled concurrency**

Run:

```bash
cd client
flutter test --no-test-assets --concurrency=4 \
  test/cubits/managed_provider_usage_cubit_test.dart \
  test/pages/managed_providers/managed_provider_management_page_test.dart \
  test/services/cli/registry/mcp_writers/mcp_config_writers_test.dart \
  test/services/provider/codex/codex_home_provisioner_test.dart \
  test/services/provider/codex/codex_toml_parser_test.dart \
  test/services/provider/config_profile_service_test.dart \
  test/services/provider_usage/managed_provider_usage_coordinator_test.dart \
  test/services/resource/cli_resource_provisioner_test.dart \
  --reporter failures-only
```

- [ ] **Step 2: Run static analysis**

Run:

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Run the default non-integration suite**

Run:

```bash
cd client
dart run tool/run_tests.dart --reporter failures-only
```

Expected: exit code 0, with no integration tests included. If the full suite exceeds the execution window, record the last completed count and use the documented sharding command rather than claiming completion.
