# Failed Message History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the existing optimistic outgoing bubble from the moment of submission and restore it as a retryable failed message after restart.

**Architecture:** Add a session-local failed-message store and a small message-state model. The existing session history seat owns the optimistic bubble, writes its `sending` state before delivery, updates it to `sent` or `failed`, and reloads failed records when the session opens. Retry and edit-and-retry actions call the existing compose delivery path without creating duplicate bubbles.

**Tech Stack:** Flutter/Dart, `Filesystem`, `AppStorage`, `flutter_bloc`, `flutter_test`.

## Global Constraints

- Persist the existing optimistic bubble immediately on submit; do not render a duplicate record.
- Failed records are session-local and never written to a CLI transcript.
- Failed delivery leaves the compose field empty and exposes retry/edit actions.
- Successful delivery finalizes/removes the pending marker; failed delivery preserves the original text.
- Restore failed records after app restart and isolate records between sessions.

---

### Task 1: Message record model and session store

**Files:**
- Create: `client/lib/models/failed_message_record.dart`
- Create: `client/lib/services/session/failed_message_store.dart`
- Modify: `client/lib/services/storage/workspace_layout.dart`
- Test: `client/test/services/session/failed_message_store_test.dart`

- [ ] Write failing tests for JSON round-trip, status transitions, session isolation, and fresh-store reload.
- [ ] Run `cd client && flutter test test/services/session/failed_message_store_test.dart` and observe RED.
- [ ] Implement the model and session-directory JSON store using injected `Filesystem` and `atomicWrite`.
- [ ] Run the focused test and observe GREEN.
- [ ] Commit with `feat: persist failed session messages`.

### Task 2: Persist and restore the existing optimistic bubble

**Files:**
- Modify: `client/lib/cubits/chat/chat_tab_store.dart` or the owning history-seat state.
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/pages/chat/session_history_review_messages.dart`
- Test: `client/test/pages/chat/session_chat_view_failed_message_test.dart`

- [ ] Write failing widget/state tests for submit-to-sending persistence, failed restoration after a fresh state instance, and session isolation.
- [ ] Run the focused test and observe RED.
- [ ] Persist the record before clearing the compose field, hydrate failed records on session bind, and render the existing bubble with sending/failed status without a second bubble.
- [ ] Run the focused test and observe GREEN.
- [ ] Commit with `feat: restore failed messages in session history`.

### Task 3: Retry and edit-and-retry actions

**Files:**
- Modify: `client/lib/pages/chat/session_history_review_messages.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Test: `client/test/pages/chat/session_chat_view_failed_message_test.dart`

- [ ] Write failing tests for retry success, retry failure, and edit-and-retry loading the original text.
- [ ] Run the focused test and observe RED.
- [ ] Wire retry actions to the existing delivery callback; update the persisted record status and avoid duplicate optimistic bubbles.
- [ ] Run the focused test and observe GREEN.
- [ ] Commit with `feat: retry failed session messages`.

### Task 4: New Chat failure behavior and regression coverage

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Test: `client/test/pages/home_workspace/workspace/workspace_chat_pane_submit_test.dart`

- [ ] Write a failing test proving session-creation failure leaves the landing text visible and does not create a session-owned record.
- [ ] Run the focused test and observe RED.
- [ ] Keep the landing compose text visible until session creation succeeds, then hand ownership to the session record at the first sending state.
- [ ] Run the focused test and observe GREEN.
- [ ] Commit with `fix: preserve new chat text on launch failure`.

### Task 5: Verification

- [ ] Run `dart format` on all changed Dart files.
- [ ] Run targeted store and session message tests.
- [ ] Run `flutter analyze --no-fatal-infos --no-fatal-warnings`.
- [ ] Run `dart run tool/run_tests.dart` and record unrelated baseline failures separately.
