# Landing remote CLI gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Machines panel probes remote CLIs and offers Install; Landing blocks submit when any required remote CLI is missing; connect never auto-installs.

**Architecture:** Shared `RemoteCliReadinessService` for locate/install. Machines UI binds readiness. `WorkspaceLandingLaunchGate` async block. `WorkspaceProvisioner._ensureCli` locate-only.

**Tech Stack:** Flutter, existing `RemoteCliLocator` / `RemoteCliInstaller` / `CliInstallProgressPanel`

---

### Task 1: Readiness model + service

**Files:**
- Create: `client/lib/services/remote/remote_cli_readiness.dart`
- Create: `client/test/services/remote/remote_cli_readiness_test.dart`

- [ ] Sealed status: probing / ready / missing / installing / failed
- [ ] `probe(target, cli)` locate with override
- [ ] `install(target, cli, onProgress)` user-driven install + remember path

### Task 2: Disable connect auto-install

**Files:**
- Modify: `client/lib/services/launch/workspace_provisioner.dart`
- Modify: `client/lib/services/cli/remote_cli_installer.dart` (optional: split locate vs install callers)
- Test: provisioner / readiness tests

- [ ] `_ensureCli` never calls install; throws clear missing error
- [ ] Remove install-progress path from connect hot path (or no-op progress for install phases)

### Task 3: Landing launch gate

**Files:**
- Modify: `client/lib/services/launch/workspace_landing_launch_gate.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_launch_feedback.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Test: gate unit tests

- [ ] `RemoteCliMissingLaunchBlock`
- [ ] Async evaluate for SSH-placed members
- [ ] Block submit + l10n tooltip

### Task 4: Machines panel UI

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart` (pass team/presets)
- Create: `client/lib/pages/home_workspace/workspace/remote_cli_machine_status_section.dart` (if split)
- l10n arb

- [ ] Per selected SSH target: required CLIs + status + Install
- [ ] Progress panel while installing

### Task 5: Cleanup + verify

- [ ] Remove obsolete connect auto-install UX where it only existed for install
- [ ] Update prior design doc note
- [ ] `flutter analyze` + targeted tests
