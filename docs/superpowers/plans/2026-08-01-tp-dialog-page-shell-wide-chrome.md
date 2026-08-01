# TpDialogPageShell wide chrome Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore desktop card chrome/padding/shrink-wrap for Appendix A `TpDialogPageShell` dialogs while keeping narrow full-bleed page behavior.

**Architecture:** Make `TpDialogPageShell` adaptive on `mobileBreakpoint`. Narrow keeps mobile nav + Expanded. Wide uses `TpDialogHeader` + theme content padding; `fillBody` controls Expanded vs shrink-wrap. Teampilot hosts pass matching breakpoint/`fillBody` and strip duplicate wide `16` padding; new-team uses intrinsic scroll (`shrinkWrap: true` or `Column(min)`).

**Tech Stack:** Flutter, `shared_ui` (`TpDialog*` / `TpTheme`), teampilot hosts, widget tests.

**Spec:** `docs/superpowers/specs/2026-08-01-tp-dialog-page-shell-wide-chrome-design.md`

---

## File map

| File | Role |
|------|------|
| `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_page_shell.dart` | Adaptive chrome API + layout |
| `client/packages/shared_ui/test/components/tp_dialog_page_test.dart` | Wide/narrow/fillBody/header tests |
| `client/packages/shared_ui/README.md` | Document wide branch |
| Host dialogs under `client/lib/pages/**` + `client/lib/widgets/run/**` | Wire params + padding |
| `client/test/pages/automations/automations_dialog_page_test.dart` | Update wide expectations |
| `docs/superpowers/specs/2026-07-30-mobile-drawer-dialog-design.md` | Amended-by + hard rules |
| Spec status on `2026-08-01-tp-dialog-page-shell-wide-chrome-design.md` | Mark Approved |

---

### Task 1: shared_ui failing tests for adaptive PageShell

**Files:**
- Modify: `client/packages/shared_ui/test/components/tp_dialog_page_test.dart`

- [ ] **Step 1: Add failing tests**

Add cases (reuse `_wrap` / `_pumpSized`):

1. Narrow: finds mobile chevron / no `TpDialogHeader` (existing close path already taps chevron — strengthen with `find.byType` if mobile nav is findable, or assert no close_rounded-only desktop header pattern: prefer `find.byIcon(Icons.close_rounded)` absent on narrow vs present on wide).
2. Wide + `fillBody: false` + `Column(mainAxisSize: min, children: [SizedBox(height: 80, child: Text('short'))])`: finds `TpDialogHeader`; shell height `< 400` (≪ maxHeight 960).
3. Wide + `fillBody: true` + child `Column(children: [Expanded(child: Text('fill')), Text('footer')])`: pumps without assert; body present.
4. Wide header: title left edge ≥ dialog left + ~24 (content inset).

Keep existing page+narrow / page+wide / card tests; update page+wide if it assumed shell fills card height.

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client/packages/shared_ui && flutter test test/components/tp_dialog_page_test.dart
```

Expected: new wide chrome / shrink assertions fail.

- [ ] **Step 3: Commit** (only if user asked for commits; otherwise skip until end)

---

### Task 2: Implement adaptive `TpDialogPageShell`

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/dialog/tp_dialog_page_shell.dart`
- Modify: `client/packages/shared_ui/README.md` (Dialog / PageShell bullets)

- [ ] **Step 1: Implement API + layout per spec**

Params: `mobileBreakpoint` (768), `fillBody` (false), `titleAlignment` (`topLeft`).

Narrow branch: unchanged mobile nav + Expanded + SafeArea.

Wide branch: exact padding tree from spec (`h` / `vTop` / `vBottom` from `context.tpTheme.dialogTheme`; header gap 20; `showDividerBelow: false`; `horizontalInset: 0`).

- [ ] **Step 2: Run Task 1 tests — PASS**

```bash
cd client/packages/shared_ui && flutter test test/components/tp_dialog_page_test.dart
```

- [ ] **Step 3: Update README** — PageShell owns narrow + wide chrome; mention `fillBody` / breakpoint match.

---

### Task 3: Wire teampilot hosts (params + padding + new-team shrink)

**Files:**
- `client/lib/pages/home_workspace/home_workspace_new_team_dialog.dart`
- `client/lib/pages/mcp/mcp_oauth_connect_dialog.dart`
- `client/lib/pages/automations/automation_editor_dialog.dart`
- `client/lib/pages/automations/automations_dialog.dart`
- `client/lib/pages/expert_hub/expert_editor_dialog.dart`
- `client/lib/pages/ssh_profiles/ssh_profile_form_dialog.dart`
- `client/lib/widgets/run/run_config_editor_dialog.dart`
- `client/lib/widgets/run/run_configurations_dialog.dart`
- `client/lib/pages/home_workspace/workspace/workspace_search_dialog.dart`
- `client/test/pages/automations/automations_dialog_page_test.dart`
- Add (optional but preferred): `client/test/pages/home_workspace/home_workspace_new_team_dialog_page_test.dart`

Host table from spec:

| Dialog | fillBody | titleAlignment |
|--------|----------|----------------|
| new team | false | center |
| mcp oauth | false | topLeft |
| editors / lists / search | true | topLeft |

All pass `mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth`.

- [ ] **Step 1: New team** — PageShell params; `SingleChildScrollView(shrinkWrap: true)` **or** drop outer scroll for `Column(min)`; breakpoint-gate or remove outer `16` padding on wide (shell pads).
- [ ] **Step 2: Remaining hosts** — params + strip/gate duplicate `16` on wide.
- [ ] **Step 3: Tests** — update automations page test for wide desktop header if needed; add new-team wide smoke (no chevron, shell not near maxHeight).
- [ ] **Step 4: Run**

```bash
cd client && flutter test test/pages/automations/automations_dialog_page_test.dart
# plus new-team test if added
cd packages/shared_ui && flutter test test/components/tp_dialog_page_test.dart
```

---

### Task 4: Spec docs

**Files:**
- `docs/superpowers/specs/2026-07-30-mobile-drawer-dialog-design.md`
- `docs/superpowers/specs/2026-08-01-tp-dialog-page-shell-wide-chrome-design.md`

- [ ] **Step 1:** Paste Amended-by + replace PageShell / Wide+page hard rules from the 2026-08-01 spec.
- [ ] **Step 2:** Set 2026-08-01 status to **Approved**.

---

### Task 5: Verification

- [ ] **Step 1:**

```bash
cd client/packages/shared_ui && flutter test test/components/tp_dialog_page_test.dart
cd ../../ && flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration test/pages/automations/automations_dialog_page_test.dart
```

- [ ] **Step 2:** Manual checklist — 新建团队 desktop: card header, compact height, ~32 gutters; phone: mobile nav; automations list still fills.

---

## Execution note

User said「开始吧」after approving the spec → prefer **inline execution** in this session (executing-plans style), not waiting for a second approach choice.
