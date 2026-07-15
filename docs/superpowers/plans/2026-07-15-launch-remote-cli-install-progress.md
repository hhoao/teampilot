# Launch remote CLI install progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show live remote CLI install progress on the member terminal pane during launch-time workspace provision.

**Architecture:** Plumb `CliInstallProgress` from `WorkspaceProvisioner` through `WorkspaceProvisionCoordinator.ensureReady` into per-member state on `ChatTab`; overlay `CliInstallProgressPanel` in `ChatWorkbench` when the selected member is provisioning.

**Tech Stack:** Flutter, flutter_bloc, existing `CliInstallProgressPanel` / `CliInstallPhase`

---

### Task 1: Progress model + provisioner callback

**Files:**
- Create: `client/lib/models/member_remote_provision_progress.dart`
- Modify: `client/lib/services/launch/workspace_provisioner.dart`
- Modify: `client/lib/services/launch/workspace_provision_coordinator.dart`
- Modify: `client/lib/services/cli/remote_cli_installer.dart` / `remote_preflight_cli_install.dart` as needed
- Test: `client/test/services/launch/workspace_provision_progress_test.dart`

- [ ] Add `MemberRemoteProvisionProgress` (memberId, phase, detail, hostLabel, error)
- [ ] `ensureReady` / `provision` accept `onProgress`
- [ ] Unit test: progress callbacks fire for ensure-cli phases (mock)

### Task 2: Wire connect path → ChatTab

**Files:**
- Modify: `client/lib/cubits/chat/model/chat_tab.dart`
- Modify: `client/lib/services/launch/session_connect_orchestrator.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart` (pass memberId)
- Modify: `client/lib/cubits/chat/session_launch_host.dart` if notify helper needed
- Test: orchestrator or host unit test with fake provisioner

- [ ] Store progress map on `ChatTab`; clear on done/fail
- [ ] Notify UI via existing applyState / tab bump

### Task 3: Workbench overlay + l10n

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench.dart`
- Modify: `client/lib/pages/chat/chat_workbench_placeholders.dart` or small new widget
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Test: widget/slice test if feasible

- [ ] Overlay panel when selected member has progress
- [ ] Title includes member + host
- [ ] Error state with message

### Task 4: Verify

- [ ] `flutter test` for new/touched tests
- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` on touched files
