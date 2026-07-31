# Progress Activity System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a unified `ProgressActivityCubit` with notification-center ongoing rows, desktop status-bar segment, and dismissible detail dialog; wire file-tree import, app update, hub clone, pack acquire, and CLI provision adapters.

**Architecture:** In-memory activity bus is the sole runtime truth; notification history is written only on terminal outcomes; UI merges ongoing + history. Producers report via adapters with cancel hooks registered at `start`. No backward-compat shims for old modal-only import progress.

**Tech Stack:** Flutter / `flutter_bloc`; existing `NotificationCubit` / `WorkspaceStatusBar`; l10n ARBs; `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-30-progress-activity-system-design.md`

## Global Constraints

- Prefer best architecture; **no** backward compatibility for duplicate progress chrome.
- Ongoing activities never hit `notifications.json`; history does.
- Bulk clear / mark-all-read = **history only**.
- Status bar `progress-activities` = **desktop only** (`!isMobile`).
- Artifact transfer progress = out of scope.
- File-tree **conflict** dialogs stay; import **progress** migrates to this system.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and focused tests listed in the final task.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/progress_activity.dart` | `ProgressActivity`, kinds, phases, copyWith |
| `client/lib/services/progress_activity/progress_fraction.dart` | Display fraction helper |
| `client/lib/cubits/progress_activity_cubit.dart` | Runtime bus + cancel hooks + history emit |
| `client/lib/widgets/notification/notification_center_panel.dart` | Extracted / updated panel: Ongoing + History (may live in bell button file if small; prefer extract if `notification_bell_button.dart` grows) |
| `client/lib/widgets/notification/progress_activity_tile.dart` | Ongoing row UI |
| `client/lib/widgets/progress_activity/progress_activity_detail_dialog.dart` | Dismissible detail dialog |
| `client/lib/widgets/workspace_status_bar/progress_activities_status_item.dart` | Status bar segment |
| `client/lib/services/progress_activity/file_tree_import_activity_adapter.dart` | Import → activity |
| `client/lib/services/progress_activity/app_update_activity_adapter.dart` | Update download → activity |
| `client/lib/services/progress_activity/hub_clone_activity_adapter.dart` | Hub clone → activity |
| `client/lib/services/progress_activity/pack_acquire_activity_adapter.dart` | Skill/plugin/extension → activity |
| `client/lib/services/progress_activity/cli_provision_activity_adapter.dart` | CLI provision → activity |
| Modify: `app_shell.dart` | Provide `ProgressActivityCubit` |
| Modify: `notification_bell_button.dart` | Merge ongoing + history UI |
| Modify: `global_resource_manager_host.dart` | Register status item |
| Modify: `file_tree_drop_region.dart` / import dialogs | Use activity system; remove modal-only progress ownership |
| Modify: `app_update_cubit.dart`, hub clone call sites, pack/CLI install paths | Report via adapters |
| l10n: `app_en.arb` / `app_zh.arb` | Ongoing / status / detail strings |
| Tests under `client/test/cubits/`, `client/test/services/progress_activity/`, `client/test/widgets/...` |

---

### Task 1: Models + fraction helper

**Files:**
- Create: `client/lib/models/progress_activity.dart`
- Create: `client/lib/services/progress_activity/progress_fraction.dart`
- Test: `client/test/services/progress_activity/progress_fraction_test.dart`

**Interfaces:** Match spec `ProgressActivity` / enums exactly (include `workspaceId`).

```dart
double? resolveProgressFraction(ProgressActivity a);
// fraction ?? items ?? bytes ?? null
```

- [ ] **Step 1: Write failing fraction tests** (fraction wins; items; bytes; indeterminate null)

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/progress_activity/progress_fraction_test.dart
```

- [ ] **Step 3: Implement models + helper**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/progress_activity.dart \
  client/lib/services/progress_activity/progress_fraction.dart \
  client/test/services/progress_activity/progress_fraction_test.dart
git commit -m "feat(progress): add ProgressActivity model and fraction helper"
```

---

### Task 2: `ProgressActivityCubit`

**Files:**
- Create: `client/lib/cubits/progress_activity_cubit.dart`
- Test: `client/test/cubits/progress_activity_cubit_test.dart`

**Interfaces:**

```dart
class ProgressActivityState {
  const ProgressActivityState({this.activities = const []});
  final List<ProgressActivity> activities;
  List<ProgressActivity> forWorkspace(String? workspaceId); // null-scoped + match
}

class ProgressActivityCubit extends Cubit<ProgressActivityState> {
  ProgressActivityCubit({required NotificationRecorder historyRecorder});

  void start(
    ProgressActivity activity, {
    FutureOr<void> Function()? onCancelRequested,
  });
  void update(String id, { ... optional fields ... });
  void requestCancel(String id);
  void setDetailOpen(String id, bool open);
  void complete(
    String id, {
    required ProgressActivityPhase outcome, // succeeded|failed|cancelled
    String? errorMessage,
    String? historyTitle,
    String? historyMessage,
  });
}
```

Behaviors to test:

- FIFO by `createdAt`; same id replace in place
- `requestCancel` → `cancelling` + invokes hook once (idempotent)
- `cancellable: true` without hook → assert/debug; release treats non-cancellable
- `complete` removes activity and calls `historyRecorder.record` with mapped variant
- `setDetailOpen` does not cancel

Use a fake `NotificationRecorder` in tests.

- [ ] **Step 1: Write failing cubit tests**

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement cubit**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/progress_activity_cubit.dart \
  client/test/cubits/progress_activity_cubit_test.dart
git commit -m "feat(progress): add ProgressActivityCubit runtime bus"
```

---

### Task 3: Provide cubit in app shell

**Files:**
- Modify: `client/lib/app/app_shell.dart` (construct + provide as existing pattern)
- Modify: `client/lib/main.dart` (`MultiBlocProvider` / shell args — mirror `NotificationCubit`)
- Modify: any `TeamPilotServices` / DI holder if notifications are injected that way

Wire `ProgressActivityCubit(historyRecorder: notificationCubit)` next to `NotificationCubit`. Ensure dispose on shell teardown.

- [ ] **Step 1: Locate how `NotificationCubit` is provided in `app_shell.dart` + `main.dart`; mirror for progress cubit**

- [ ] **Step 2: Implement wiring**

- [ ] **Step 3: `flutter analyze` on touched files — no new errors**

- [ ] **Step 4: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "feat(progress): provide ProgressActivityCubit in app shell"
```

---

### Task 4: Notification center Ongoing + History UI

**Files:**
- Modify: `client/lib/widgets/notification/notification_bell_button.dart`
- Create: `client/lib/widgets/notification/progress_activity_tile.dart`
- Optionally extract panel widget if file exceeds soft size
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Test: `client/test/widgets/notification/progress_activity_tile_test.dart` (and/or bell panel test)

**UI rules:**

- Panel sections: **Ongoing** (from `ProgressActivityCubit`) then **History** (from `NotificationCubit`)
- Ongoing tile: title, subtitle, `LinearProgressIndicator` or indeterminate, Cancel button
- Clear all / mark all read: history only — disable or no-op when only ongoing exist; never cancel
- Badge: unread history + ongoing count (distinct if easy; at least include ongoing in count)

- [ ] **Step 1: Add ARB keys + failing widget test** (tile shows Cancel; clear-all does not remove ongoing)

- [ ] **Step 2–4: Implement UI**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/notification/ client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/test/widgets/notification/
git commit -m "feat(progress): show ongoing activities in notification center"
```

---

### Task 5: Detail dialog

**Files:**
- Create: `client/lib/widgets/progress_activity/progress_activity_detail_dialog.dart`
- Test: `client/test/widgets/progress_activity/progress_activity_detail_dialog_test.dart`
- Modify: notification tile / status list to open via `setDetailOpen(true)` + `showProgressActivityDetailDialog`

**Behavior:**

- Listens to cubit for that `id`
- Close → `setDetailOpen(false)` + pop; activity remains
- Cancel → `requestCancel(id)`
- When activity completes, dialog auto-pops

- [ ] **Step 1: Failing tests** (close keeps activity in cubit; cancel calls requestCancel)

- [ ] **Step 2–4: Implement**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/progress_activity/ \
  client/test/widgets/progress_activity/
git commit -m "feat(progress): add dismissible progress activity detail dialog"
```

---

### Task 6: Status bar segment

**Files:**
- Create: `client/lib/widgets/workspace_status_bar/progress_activities_status_item.dart`
- Modify: `client/lib/pages/home_workspace/global_resource_manager_host.dart` (register item when `!isMobile`)
- Test: `client/test/widgets/workspace_status_bar/progress_activities_status_item_test.dart`

**Behavior:**

- Segment `id => 'progress-activities'` (same convention as `resource-usage` / `ssh-hosts`)
- Resolve `workspaceId` from the active workspace in the host (e.g. active tab /
  `ChatCubit` / layout active workspace — match how other workspace-scoped
  status items obtain it). Filter with `state.forWorkspace(workspaceId)`.
- 1 activity: short label + percent/spinner
- N: `progressActivitiesMany(n)` l10n → open popover list (reuse tile)
- Click opens detail or list

- [ ] **Step 1: Failing tests** for single vs multi label

- [ ] **Step 2–4: Implement + register**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/workspace_status_bar/progress_activities_status_item.dart \
  client/lib/pages/home_workspace/global_resource_manager_host.dart \
  client/test/widgets/workspace_status_bar/progress_activities_status_item_test.dart
git commit -m "feat(progress): add desktop status bar activities segment"
```

---

### Task 7: Adapter — file tree import

**Files:**
- Create: `client/lib/services/progress_activity/file_tree_import_activity_adapter.dart`
- Modify: `client/lib/widgets/file_tree/file_tree_drop_region.dart`
- Modify: `client/lib/widgets/file_tree/file_tree_import_dialogs.dart` (progress dialog becomes detail dialog or thin wrapper; remove barrier that forces cancel-only dismiss)
- Update: `docs/superpowers/specs/2026-07-30-file-tree-external-drop-import-design.md` UI integration table (progress → activity system)
- Test: `client/test/services/progress_activity/file_tree_import_activity_adapter_test.dart`

**Flow:**

1. After `prepareAt`, if `shouldShowImportProgress` (or always for remote): `cubit.start(...)` with cancel → set import cancel flag
2. Subscribe to `importService.progress` → `cubit.update`
3. Optionally `setDetailOpen(true)` + show detail dialog
4. On summary: `complete` with succeeded/failed/cancelled
5. Keep conflict dialogs unchanged
6. Delete ownership of progress from old `showFileTreeImportProgressDialog` or repoint it to detail dialog API

- [ ] **Step 1: Adapter unit test with fake cubit / service**

- [ ] **Step 2–4: Wire drop region**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/progress_activity/file_tree_import_activity_adapter.dart \
  client/lib/widgets/file_tree/ \
  client/test/services/progress_activity/file_tree_import_activity_adapter_test.dart \
  docs/superpowers/specs/2026-07-30-file-tree-external-drop-import-design.md
git commit -m "feat(progress): wire file-tree import into ProgressActivityCubit"
```

---

### Task 8: Adapter — app update

**Files:**
- Create: `client/lib/services/progress_activity/app_update_activity_adapter.dart`
- Modify: `client/lib/cubits/app_update_cubit.dart` (emit through adapter; remove UI-only progress ownership if duplicated)
- Test: `client/test/services/progress_activity/app_update_activity_adapter_test.dart`

Map `downloading` → fraction updates; `installing` → indeterminate, `cancellable: false`. Cancel download only if service supports it.

- [ ] **Steps: TDD adapter + wire + commit**

```bash
git commit -m "feat(progress): wire app update download into ProgressActivityCubit"
```

---

### Task 9: Adapter — hub clone

**Files:**
- Create: `client/lib/services/progress_activity/hub_clone_activity_adapter.dart`
- Modify: team hub / expert hub clone call sites (`team_hub_page.dart`, `expert_hub_*`, clone services)
- Test: adapter unit test

v1: if no cancel API, `cancellable: false`, use `CloneProgress` items/fraction when available else indeterminate.

- [ ] **Steps: TDD + wire + commit**

```bash
git commit -m "feat(progress): wire hub clone into ProgressActivityCubit"
```

---

### Task 10: Adapter — pack acquire (skill / plugin / extension)

**Files:**
- Create: `client/lib/services/progress_activity/pack_acquire_activity_adapter.dart`
- Modify: skill/plugin/extension install/acquire entry points (search `ExtensionAcquisitionEngine`, skill install, plugin git clone UI)
- Test: adapter unit test with fake steps

Prefer one `kind: packAcquire` with title distinguishing skill vs plugin vs extension.

- [ ] **Steps: TDD + wire + commit**

```bash
git commit -m "feat(progress): wire pack acquire into ProgressActivityCubit"
```

---

### Task 11: Adapter — CLI provision

**Files:**
- Create: `client/lib/services/progress_activity/cli_provision_activity_adapter.dart`
- Modify: `workspace_provisioner.dart` / `workspace_provision_coordinator.dart` / remote CLI install call sites that already take `onProgress`
- Test: adapter unit test

- [ ] **Steps: TDD + wire + commit**

```bash
git commit -m "feat(progress): wire CLI provision into ProgressActivityCubit"
```

---

### Task 12: Verification

- [ ] **Step 1: Focused tests**

```bash
cd client && flutter test \
  test/cubits/progress_activity_cubit_test.dart \
  test/services/progress_activity \
  test/widgets/progress_activity \
  test/widgets/notification \
  test/widgets/workspace_status_bar/progress_activities_status_item_test.dart \
  test/services/file_tree_import \
  test/widgets/file_tree
```

Expected: PASS

- [ ] **Step 2: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Manual smoke checklist (human)**

1. Import large/remote folder → ongoing in bell + status pill; close detail → still runs; cancel works  
2. App update download progress in bell/status  
3. Hub clone shows activity  
4. Skill/plugin/extension acquire shows activity  
5. CLI provision shows activity  
6. Clear-all history does not cancel ongoing  
7. Mobile: no status pill; bell ongoing still works  

- [ ] **Step 4: Commit leftover polish if any**

```bash
git commit -m "fix(progress): polish progress activity system after verification"
```

---

## Execution notes

- Implement adapters after shell UI so each adapter immediately has a visible surface.
- Prefer injecting `ProgressActivityCubit` into adapters via constructor for tests.
- Keep new files under soft line limits; split notification panel if needed.
- Run `dart run tool/gen_warmup_glyphs.dart` after ARB glyph changes.
