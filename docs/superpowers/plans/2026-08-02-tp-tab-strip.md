# Tp Tab Strip + Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship presentation-only `TpTabChip` + `TpTabStrip` in `shared_ui` with optional drag-reorder, migrate floating / workbench strip / run panel onto them, and delete `WorkspaceShellTabChip`.

**Architecture:** `shared_ui` owns chrome + horizontal scroll/reorder layout. App hosts pass plain props and wire `onReorder` to `FloatingWorkspaceCubit.reorderTabs`, `WorkbenchCubit.reorderTabs`, or run-panel display-order merge. No domain types in shared_ui; no backward-compat shims.

**Tech Stack:** Flutter / Dart, `shared_ui` (`TpTheme`, `TpTextStyles`, `TpIconButton`), `flutter_bloc`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-02-tp-tab-strip-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/shared_ui/lib/src/components/tab/reorder_list_items.dart` | Pure `reorderListItems` helper |
| `client/packages/shared_ui/lib/src/components/tab/tp_tab_strip_metrics.dart` | `shell` (40) / `compact` (36) metrics |
| `client/packages/shared_ui/lib/src/components/tab/tp_tab_chip.dart` | Presentation chip |
| `client/packages/shared_ui/lib/src/components/tab/tp_tab_strip.dart` | Scroll + optional reorder strip |
| `client/packages/shared_ui/lib/shared_ui.dart` | Export new tab APIs |
| `client/packages/shared_ui/test/components/tab/` | Unit + widget tests |
| `client/lib/cubits/floating_workspace/floating_workspace_cubit.dart` | `reorderTabs` |
| `client/lib/cubits/workbench/workbench_cubit.dart` | `reorderTabs` |
| `client/lib/pages/floating_workspace/floating_workspace_tab_bar.dart` | Use `TpTabStrip` |
| `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | Delete chip; row → strip |
| `client/lib/pages/workspace_shell/workspace_shell.dart` (+ host) | Wire workbench `onReorder` |
| `client/lib/widgets/run/run_panel.dart` | Strip + display-order ids |
| App tests under `client/test/` | Cubit + migration coverage |

---

### Task 1: `reorderListItems` helper

**Files:**
- Create: `client/packages/shared_ui/lib/src/components/tab/reorder_list_items.dart`
- Test: `client/packages/shared_ui/test/components/tab/reorder_list_items_test.dart`

- [x] **Step 1–4:** `reorderListItems` + tests

### Task 2: `TpTabChip`

- [x] Port + tests + export

### Task 3: `TpTabStrip`

- [x] Scroll / reorder / `fillWidth` / trailing slots + tests

### Task 4: Cubit reorder APIs

- [x] `FloatingWorkspaceCubit.reorderTabs` + `WorkbenchCubit.reorderTabs` + tests

### Task 5–7: Migrate call sites

- [x] Floating / `WorkspaceShellTabRow` / run panel
- [x] `WorkbenchStripTabChip` host wrapper; `WorkspaceShellTabChip` deleted

### Task 8: Cleanup + verification

- [x] Code references cleared (docs may still mention old name)
- [x] Targeted tests + analyze on touched paths

**Commit:** only when user asks (shared_ui submodule first, then teampilot).
