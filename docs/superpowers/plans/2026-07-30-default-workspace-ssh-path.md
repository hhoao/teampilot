# Default workspace SSH/WSL path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seed the built-in Default workspace at `$HOME/TeamPilot` on the home machine when home is SSH/WSL, instead of the device Documents path.

**Architecture:** Extend `DefaultWorkspaceService.resolvePrimaryPath` to branch on `RuntimeTarget.kind`. Local keeps `DefaultWorkspaceDirectory`; SSH/WSL joins `AppStorage.home` + `TeamPilot` via posix path context and `AppStorage.fs.ensureDir`. Pass `home` through `ensureDefault` / `seed` / onboarding lookup.

**Tech Stack:** Flutter/Dart, existing `AppStorage` / `Filesystem.ensureDir`, unit tests in `default_workspace_service_test.dart`.

**Spec:** `docs/superpowers/specs/2026-07-30-default-workspace-ssh-path-design.md`

---

### Task 1: Failing test — SSH home seeds remote TeamPilot path

**Files:**
- Modify: `client/test/services/team/default_workspace_service_test.dart`

- [x] **Step 1: Write the failing test**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement `resolvePrimaryPath` + wire callers**
- [x] **Step 4: Run tests**
- [x] **Step 5: Broader verify (optional)**