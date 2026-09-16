# Remote Runtime Closure Implementation Plan

> **For the implementation agent:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task by task.

**Goal:** Make remote Codex launches transfer only the active session runtime closure, while making shared SSH storage connections resilient to concurrent disconnects.

**Architecture:** Keep control-plane repositories and caches local. The workspace materializer copies only small, reusable CLI configuration and excludes repository metadata and Codex's shared plugin cache. Session staging projects active plugin content into the remote manifest: symlinks within the remote work root remain links, while links to local control-plane paths become copy operations. Codex sessions own a real `.tmp/plugins` directory. The SSH storage pool tracks in-flight operations and drains an evicted client before closing it.

**Validation:** Every behavioral change gets a focused test first. Use `cd client && dart run tool/run_tests.dart <path>` for tests, then `flutter analyze --no-fatal-infos --no-fatal-warnings`, and finally the full test suite through `tool/run_tests.dart`.

### Task 1: Define and test the remote materialization projection

**Files:**
- Create: `client/lib/services/remote/runtime_materialization_policy.dart`
- Modify: `client/lib/services/remote/work_machine_materializer.dart`
- Modify: `client/lib/services/remote/remote_app_data_materializer.dart`
- Tests: `client/test/services/remote/work_machine_materializer_test.dart`

1. Add failing tests proving Codex `.tmp/plugins` and any `.git`, `.hg`, or
   `.svn` subtree is excluded, while normal CLI config remains materialized.
2. Add an explicit policy object and apply it while enumerating both app-tool
   and workspace-config trees.
3. Replace the fixed eight-writer pool with a bounded configurable scheduler,
   defaulting to a conservative remote-safe concurrency, and report copied
   file/byte totals.
4. Add cleanup for the old remote shared Codex cache so the new session-owned
   layout cannot inherit stale links.
5. Run the focused materializer tests and inspect the generated manifest.

### Task 2: Project external symlinks into the remote launch manifest

**Files:**
- Modify: `client/lib/services/launch/manifest_filesystem.dart`
- Modify: `client/lib/services/provider/config_profile_service.dart`
- Tests: `client/test/services/launch/manifest_filesystem_test.dart`
- Tests: `client/test/services/provider/config_profile_service_test.dart`

1. Add failing tests proving a symlink target inside the remote work root is
   retained as a symlink, while a target outside that root becomes a copy-tree
   manifest operation.
2. Give `ManifestFilesystem` an explicit projection root and make external
   links return the normal copy fallback without creating a broken link.
3. Configure staging filesystems with the target work root so plugin pools,
   skills, and generated runtime resources become self-contained remotely.
4. Verify active plugin content is represented in the manifest and that local
   control-plane paths never appear as remote symlink targets.

### Task 3: Make Codex plugin storage session-owned

**Files:**
- Modify: `client/lib/services/storage/runtime_layout.dart`
- Modify: `client/lib/services/cli/codex/capabilities/provider.dart`
- Modify: `docs/workspace-storage-layout.md`
- Tests: `client/test/services/storage/runtime_layout_test.dart`
- Tests: `client/test/services/cli/codex/capabilities/provider_test.dart`

1. Add failing tests proving a Codex session creates a real
   `runtime/.../codex/.tmp/plugins` directory and does not link to
   `cli-defaults/codex/.tmp/plugins`.
2. Replace the shared-cache inheritance helper with a session-owned cache
   helper and update the Codex launch capability.
3. Ensure the native plugin source populates that session cache from the active
   plugin closure only.
4. Update the storage-layout documentation to remove the old inheritance rule.

### Task 4: Make SSH storage teardown drain-safe and replay-safe

**Files:**
- Modify: `client/lib/services/ssh/ssh_client_factory.dart`
- Modify: `client/lib/services/remote/remote_file_store.dart`
- Modify: `client/lib/services/ssh/ssh_member_session.dart`
- Tests: `client/test/services/ssh/ssh_client_factory_pool_test.dart`
- Tests: `client/test/services/remote/remote_file_store_test.dart`

1. Add failing tests for eviction while an SFTP operation is in flight and for
   quiet member-session teardown.
2. Track in-flight storage operations by profile. Evict immediately for new
   callers, then close the old client only after drain or a bounded grace
   period.
3. Wrap SFTP data operations in one recovery boundary that retries safe
   operations once after a channel/transport closure; never replay arbitrary
   shell commands.
4. Consume expected asynchronous disconnect errors so dartssh2 teardown cannot
   surface as an unhandled error.
5. Run focused SSH tests under the repository test wrapper.

### Task 5: Integrate and verify the complete launch path

**Files:**
- Modify: relevant launch/session tests only as required by the new contract.

1. Run focused launch, Codex capability, materializer, manifest, and SSH tests.
2. Run `flutter analyze --no-fatal-infos --no-fatal-warnings`.
3. Run the full suite once with `cd client && dart run tool/run_tests.dart`.
4. Review the final diff for accidental changes to existing user work and
   confirm no raw `Directory.current`, `print`, or direct `flutter test` was
   introduced.
