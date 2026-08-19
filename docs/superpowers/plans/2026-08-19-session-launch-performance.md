# Session Launch Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make session startup responsive by replacing repeated Codex plugin tree copies with a shared, fingerprinted native-plugin source and by terminating orphaned materializer waits.

**Architecture:** Codex plugin preparation becomes a fingerprinted, per-session TeamPilot marketplace source. The source contains only a small manifest plus links to the already reconciled session plugin pool; it never copies the plugin payload on the normal path. A source stamp records the desired plugin set and source fingerprint, while Codex's own marketplace list remains authoritative for native registration and repair. Launch timing is logged per stage. `TabMemberMaterializer` treats a missing tab as terminal for that wait.

**Tech Stack:** Dart, Flutter, `Filesystem`, `LaunchManifest`, `HostOneShotRunner`, Flutter widget/unit tests.

## Global Constraints

- Preserve all unrelated uncommitted changes in the working tree.
- Codex native plugin storage remains owned by Codex; TeamPilot owns only the source layer and launch stamp.
- No full plugin tree copy is allowed on the normal local/WSL/SSH path when a source link can be created.
- Do not use `print`; use `AppLogger` for diagnostics.
- New behavior must be covered by tests before production implementation.

### Task 1: Define and test the Codex native source layer

**Files:**
- Create: `client/lib/services/cli/codex/capabilities/codex_native_plugin_source.dart`
- Modify: `client/test/services/cli/registry/plugin_provisioners/codex_plugin_provisioner_test.dart`

**Interfaces:**
- Consumes: `Filesystem`, `Plugin`, `PluginManifestPaths`, `RuntimeLayout` paths.
- Produces: `CodexNativePluginSource.prepare(...)` returning a source descriptor with marketplace root, desired plugin specs, and fingerprint.

- [ ] **Step 1: Write the failing source-layer tests**

  Add tests that seed two plugin bundles in an in-memory filesystem and assert:

  1. preparation creates a marketplace manifest and one link per plugin;
  2. the marketplace manifest names the TeamPilot marketplace and points to `./plugins/<name>`;
  3. the second preparation with the same plugin versions reports `changed == false` and does not issue another tree copy;
  4. changing one plugin version changes the fingerprint and rebuilds only the source metadata.

- [ ] **Step 2: Run the focused tests and verify the expected failure**

  Run:

  ```bash
  cd client && flutter test test/services/cli/registry/plugin_provisioners/codex_plugin_provisioner_test.dart
  ```

  Expected: FAIL because `CodexNativePluginSource` does not exist and no source fingerprint is produced.

- [ ] **Step 3: Implement the source layer**

  Implement a focused service that:

  - derives a deterministic fingerprint from sorted `(plugin name, version, directory)` tuples;
  - stores only the marketplace metadata and links under the session's TeamPilot-owned config area, not under Codex's managed plugin store;
  - creates marketplace plugin entries as links to the already reconciled plugin pool;
  - writes `.agents/plugins/marketplace.json` and a stamp containing fingerprint/specs;
  - invalidates stale source entries when the fingerprint or metadata is no longer current;
  - returns `changed`, `marketplaceRoot`, `fingerprint`, and desired specs to the native installer.

- [ ] **Step 4: Run the focused tests and verify they pass**

  Run the same Flutter test command. Expected: PASS with no full-tree copy recorded for the unchanged linked path.

- [ ] **Step 5: Commit the isolated source-layer change**

  ```bash
  git add client/lib/services/cli/codex/capabilities/codex_native_plugin_source.dart client/test/services/cli/registry/plugin_provisioners/codex_plugin_provisioner_test.dart
  git commit -m "refactor: add fingerprinted Codex plugin source layer"
  ```

### Task 2: Make Codex provisioning idempotent and link-based

**Files:**
- Modify: `client/lib/services/cli/codex/capabilities/plugin.dart`
- Modify: `client/lib/services/cli/registry/capabilities/plugin_capability.dart`
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Modify: `client/lib/services/launch/session_connect_orchestrator.dart`
- Modify: `client/test/services/cli/registry/plugin_provisioners/codex_plugin_provisioner_test.dart`

**Interfaces:**
- Consumes: `CodexNativePluginSource.prepare(...)` from Task 1.
- Produces: `PluginProvisionResult` with source fingerprint, native commands run, and elapsed stage timings.

- [ ] **Step 1: Add failing command/idempotency tests**

  Extend the Codex provisioner tests to assert:

  - the marketplace-add command is skipped when the source fingerprint stamp is current;
  - `plugin list` still repairs a missing or version-mismatched native plugin;
  - stale TeamPilot native plugins are removed;
  - a fresh source uses links and never records `ManifestCopyTree` for the plugin payload;
  - the configured executable, `CODEX_HOME`, and PATH prepend remain present on every native command.

- [ ] **Step 2: Run the focused tests and verify the expected failure**

  ```bash
  cd client && flutter test test/services/cli/registry/plugin_provisioners/codex_plugin_provisioner_test.dart
  ```

  Expected: FAIL on the new idempotency and no-copy assertions.

- [ ] **Step 3: Implement the new provisioning flow**

  Change `CodexPluginCapability.provision` to:

  - ask the source layer for the desired source;
  - run `plugin marketplace add` only when the source changed or Codex reports the marketplace absent;
  - always run one `plugin list --json` repair check;
  - remove stale TeamPilot entries and add only missing/version-mismatched entries;
  - keep source and native registration state separate so staging cannot suppress the first post-flush marketplace registration;
  - preserve failure details and never mark a failed native install current.

  Move source construction out of `ManifestFilesystem.copyTree`; the staging manifest should contain links and small metadata files only. Keep the existing PATH propagation from the user's uncommitted changes.

- [ ] **Step 4: Add stage-specific timing logs**

  Add separate `[session-launch]` timings for `manifest-flush`, `native-plugin-source`, and `native-plugin-install` in `SessionConnectOrchestrator`/`ConfigProfileService`. The existing aggregate log must no longer hide native CLI time inside `manifest-flush`.

- [ ] **Step 5: Run focused tests and verify they pass**

  ```bash
  cd client && flutter test test/services/cli/registry/plugin_provisioners/codex_plugin_provisioner_test.dart test/services/launch/manifest_filesystem_test.dart
  ```

- [ ] **Step 6: Commit the Codex provisioning change**

  ```bash
  git add client/lib/services/cli/codex/capabilities/plugin.dart client/lib/services/cli/registry/capabilities/plugin_capability.dart client/lib/services/provider/config_profile_service.dart client/lib/services/launch/session_connect_orchestrator.dart client/test/services/cli/registry/plugin_provisioners/codex_plugin_provisioner_test.dart
  git commit -m "perf: make Codex native plugin provisioning idempotent"
  ```

### Task 3: Stop orphaned member materializer waits

**Files:**
- Modify: `client/lib/cubits/chat/tab_member_materializer.dart`
- Modify or create: `client/test/cubits/tab_member_materializer_test.dart`

**Interfaces:**
- Consumes: `ChatTabStore.openTabBySessionId` and existing materializer lifecycle callbacks.
- Produces: terminal completion when the target session tab no longer exists.

- [ ] **Step 1: Write the failing no-tab regression test**

  Start `ensureMemberInputReady` for a session with no open tab, pump longer than one polling interval, close the returned future, and assert no repeated wait remains active. Keep the test independent of real PTY processes.

- [ ] **Step 2: Run the focused test and verify the expected failure**

  ```bash
  cd client && flutter test test/cubits/tab_member_materializer_test.dart
  ```

  Expected: FAIL because the current loop only exits when the entire cubit closes.

- [ ] **Step 3: Implement terminal no-tab handling**

  After `materializeMember` returns, check `openTabBySessionId(sessionId)`. If it is still absent, log one cancellation diagnostic and return. Also clear the corresponding `_memberReady` completer entry when the wait terminates.

- [ ] **Step 4: Run the focused test and verify it passes**

  ```bash
  cd client && flutter test test/cubits/tab_member_materializer_test.dart
  ```

- [ ] **Step 5: Commit the lifecycle fix**

  ```bash
  git add client/lib/cubits/chat/tab_member_materializer.dart client/test/cubits/tab_member_materializer_test.dart
  git commit -m "fix: stop materializer waits for missing tabs"
  ```

### Task 4: Full verification and performance evidence

**Files:**
- Modify only files required by failing verification.
- Do not stage or revert unrelated existing user changes.

- [ ] **Step 1: Run all focused regression tests**

  ```bash
  cd client && flutter test test/services/cli/registry/plugin_provisioners/codex_plugin_provisioner_test.dart test/services/launch/manifest_filesystem_test.dart test/cubits/tab_member_materializer_test.dart
  ```

- [ ] **Step 2: Run static analysis**

  ```bash
  cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
  ```

- [ ] **Step 3: Run the repository test suite excluding integration tests**

  ```bash
  cd client && flutter test --exclude-tags integration
  ```

- [ ] **Step 4: Inspect the final diff and launch logs**

  Confirm the diff does not include unrelated files, and confirm a representative launch shows no multi-megabyte `copyTree`, no repeated Codex marketplace rebuild when unchanged, and separate source/install timings.

- [ ] **Step 5: Request code review before claiming completion**

  Review the changed files against the plan, especially link semantics on Local/WSL/SSH filesystems, stamp invalidation, failure recovery, and concurrent native installs.
