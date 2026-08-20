# Managed Provider Body Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Keep Managed Provider create/edit interactions inside the HomeShell body instead of opening a full-window `MaterialPageRoute`.

**Architecture:** `ManagedProviderManagementPage` owns a small internal view state (`list` or `editor`). The existing `ManagedProviderEditorPage` remains the editor surface, but is rendered as an embedded body child with an explicit back callback. Provider cubits stay above both states, so save/delete/usage behavior and persistence are unchanged.

**Tech Stack:** Flutter, flutter_bloc, existing TeamPilot HomeShell embedded global sections, widget tests.

---

### Task 1: Replace full-screen editor navigation with body navigation

**Files:**
- Modify: `client/lib/pages/managed_providers/managed_provider_management_page.dart`
- Modify: `client/lib/pages/managed_providers/managed_provider_editor_page.dart`
- Test: `client/test/pages/managed_providers/managed_provider_management_page_test.dart`

- [ ] **Step 1: Write a failing widget test**

  Extend the management-page test so tapping `managed-provider-add` finds the editor inside the same test body, and tapping the editor back control returns to `managed-provider-management-page` without a route push.

- [ ] **Step 2: Run the focused test and verify it fails**

  Run `flutter test test/pages/managed_providers/managed_provider_management_page_test.dart` from `client/`.
  Expected: the editor is not found because the current implementation pushes a `MaterialPageRoute` and has no embedded back callback.

- [ ] **Step 3: Implement the minimal body-navigation change**

  Add an internal `ManagedProvider? _editingProvider` plus an `_isEditing` flag (or equivalent enum) to the management page. Render `ManagedProviderEditorPage` directly in the existing embedded content when editing, pass the existing provider, and provide an `onBack` callback. Replace `_openEditor`'s `Navigator.push` with `setState`; after save/delete/cancel, return to list state while keeping the shared cubits in place. Add a compact app-bar/back control to the editor only when it is embedded; preserve its standalone `Scaffold` behavior for any existing non-embedded callers.

- [ ] **Step 4: Run focused tests and analyzer**

  Run:
  `flutter test test/pages/managed_providers/managed_provider_management_page_test.dart`
  and
  `flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/managed_providers`
  Expected: focused tests pass and analyzer exits 0.

- [ ] **Step 5: Commit the implementation**

  Commit only the navigation files, test, and this plan document; leave the pre-existing `client/pubspec.lock` modification untouched.
