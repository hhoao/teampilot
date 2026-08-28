# Widget Rebuild Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop high-frequency ChatCubit / presence / compose / layout events from rebuilding whole chat threads, keep-alive session hosts, and right-tools subtrees.

**Architecture:** Leaf-only `context.select` (bool / identity snapshots), keep-alive skip-layout for hidden terminals, and compose `ListenableBuilder` so typing never `setState`s `SessionChatView`. Follow existing `SessionListStructure` / `SessionRowContent` / `ChatPageStructuralSignal` patterns.

**Tech Stack:** Flutter, flutter_bloc, existing rebuild probes (`SidebarRebuildProbe`, `ChatPageStructuralBodyProbe`).

## Global Constraints

- Do not put `workingSessionIds` or title-bearing `sessions` in page-shell `buildWhen`.
- Keep-alive inactive hosts must not rebuild on other sessions' working/presence bits.
- Compose keystrokes must not rebuild the history thread.
- `TpKeepAliveLayer` skips layout; `Offstage` does not — hidden Alacritty must use the former.
- Tests: mock subprocess/filesystem via injection; cubits touching `AppStorage` use `setUpTestAppStorage()`.
- Do not commit unless the user asks.
- Generic UI stays in `shared_ui` (`Tp*`); product chrome stays in `client/lib`.

---

### Task 1: Per-seat working / presence selects

**Files:**
- Create: `client/lib/pages/chat/session_seat_working.dart`
- Create: `client/test/pages/chat/session_seat_working_test.dart`
- Modify: `session_chat_view.dart`, `session_chat_compose_section.dart`, `terminal_follow_up_compose.dart`

**Produces:** `void watchSessionSeatWorking(BuildContext context, {required String workspaceId, required String sessionId, required String memberId})`

Selects `centerActiveId`, `workingSessionIds.contains(sessionId)`, and `presence[memberId]` (null-safe when memberId is empty). Does not select the full Set/Map.

---

### Task 2: SessionChatIdentity

**Files:**
- Create: `client/lib/utils/session/session_chat_identity.dart`
- Create: `client/test/utils/session/session_chat_identity_test.dart`
- Modify: `session_chat_view.dart` `_watchDisplaySession`

Ignores `display` / `updatedAt` / `createdAt` / `pinned` / `sortOrder` so first-message title capture does not rebuild markdown.

---

### Task 3: Compose typing isolation

**Files:**
- Modify: `session_chat_view.dart` (`_onComposeChanged`, drop parent `setState` on text)
- Modify: `session_chat_compose_section.dart` (ListenableBuilder on controller + clip + voice; stop calling parent `onComposeChanged` from `onChanged`)

---

### Task 4: Markdown theme width

**Files:**
- Modify: `session_chat_view.dart` — `buildAppMarkdownTokens(width: columnWidth)` not `MediaQuery.sizeOf(context).width`

---

### Task 5: Hidden terminal skip-layout

**Files:**
- Modify: `client/lib/pages/chat_workbench.dart` — replace `Offstage` wrappers with `TpKeepAliveLayer` + `TickerMode`

---

### Task 6: Session group membership snapshot

**Files:**
- Create: `client/lib/utils/session/session_group_membership.dart`
- Modify: `session_group_section.dart` — `context.select` membership ids, not `watch<ChatCubit>()`
- Test: extend `session_group_section_test.dart`

---

### Task 7: Right-tools / shortcuts / landing watches

**Files:**
- `workspace_split_pane.dart` — select `RightToolsToolPreferences` + effective right visibility, not full `LayoutCubit`
- `teampilot_alacritty_terminal.dart` — `select<ShortcutCubit, ShortcutState>`
- `mailbox_panel.dart` / `board_panel.dart` / `members_panel.dart` — select listed fields
- `unbound_compose_body.dart` — select presets/teams/installed lists
- `chat_page_shell.dart` — use `pinnedBySessionId` from structural signal

---
