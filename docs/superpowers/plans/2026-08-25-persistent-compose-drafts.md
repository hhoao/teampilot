# Persistent Compose Drafts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve unsubmitted New Chat and existing-session messages across failed delivery and application restart.

**Architecture:** Add one workspace-scoped JSON store for the landing draft and session drafts. `ComposeDraftCache` stays the synchronous UI cache; compose hosts hydrate it from disk and write each text change directly to disk. Submission removes the draft only after delivery succeeds.

**Tech Stack:** Flutter/Dart, `Filesystem`, `AppStorage`, `flutter_test`, Mocktail.

## Global Constraints

- Landing drafts are keyed by workspace ID; session drafts by workspace and session IDs.
- No debounce, retry, fallback recovery, or other defensive behavior.
- Creation, connection, and terminal-delivery failures retain drafts across restart.
- User clearing or successful terminal delivery deletes the relevant draft.
- Drafts never enter chat history or cross workspace/session boundaries.

---

## File structure

- Create `client/lib/services/compose/compose_draft_store.dart`: JSON persistence.
- Modify `client/lib/services/storage/workspace_layout.dart`: workspace draft path.
- Modify `client/lib/services/compose/compose_draft_cache.dart`: cache plus async store façade.
- Modify compose hosts: landing `unbound_compose_body.dart`, existing session `session_chat_view.dart`.
- Modify submission paths: `workspace_chat_pane.dart`, `workspace_session_actions.dart`, `session_chat_view.dart`.
- Modify `chat_cubit.dart`: clear stored draft on session deletion.
- Test store, landing compose, session compose, and deletion lifecycle in their existing test files.

### Task 1: Persist workspace drafts

**Files:**
- Modify: `client/lib/services/storage/workspace_layout.dart`
- Create: `client/lib/services/compose/compose_draft_store.dart`
- Test: `client/test/services/compose/compose_draft_store_test.dart`

**Interfaces:**
- `WorkspaceLayout.composeDraftsFile(String workspaceId)`.
- `ComposeDraftStore.loadLanding/saveLanding`, `loadSession/saveSession`, and `clearSession`.

- [ ] **Step 1: Write failing store tests**

```dart
test('landing draft survives a fresh store instance', () async {
  await ComposeDraftStore(fs: fs, rootPath: root).saveLanding('w1', 'long prompt');
  expect(await ComposeDraftStore(fs: fs, rootPath: root).loadLanding('w1'), 'long prompt');
});

test('session drafts are isolated and cleared independently', () async {
  final store = ComposeDraftStore(fs: fs, rootPath: root);
  await store.saveSession('w1', 's1', 'retry me');
  await store.saveSession('w1', 's2', 'other');
  await store.clearSession('w1', 's1');
  expect(await store.loadSession('w1', 's1'), isNull);
  expect(await store.loadSession('w1', 's2'), 'other');
});
```

- [ ] **Step 2: Verify RED**

Run: `cd client && flutter test test/services/compose/compose_draft_store_test.dart`

Expected: FAIL because the store and layout path do not exist.

- [ ] **Step 3: Implement JSON persistence**

Use `workspace/workspaces/{workspaceId}/compose-drafts.json` with shape:

```json
{"landing":"...","sessions":{"session-id":"..."}}
```

Read/update/write this document through injected `Filesystem`, `ensureDir`, and `atomicWrite`. Empty text removes its entry.

- [ ] **Step 4: Verify GREEN**

Run: `cd client && flutter test test/services/compose/compose_draft_store_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/workspace_layout.dart client/lib/services/compose/compose_draft_store.dart client/test/services/compose/compose_draft_store_test.dart
git commit -m "feat: persist compose drafts per workspace"
```

### Task 2: Hydrate and save both compose surfaces

**Files:**
- Modify: `client/lib/services/compose/compose_draft_cache.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Test: `client/test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart`
- Test: `client/test/pages/chat/session_chat_view_draft_cache_test.dart`

**Interfaces:**
- `ComposeDraftCache.hydrateLanding(String workspaceId)`.
- `ComposeDraftCache.hydrateSession(String workspaceId, String sessionId)`.
- Async `saveLanding/saveSession` and `clearLandingPersistent/clearSessionPersistent` operations.

- [ ] **Step 1: Write failing restart-style widget tests**

```dart
testWidgets('landing restores persisted draft after cache reset', (tester) async {
  await ComposeDraftStore().saveLanding('workspace-1', 'survive restart');
  composeDraftCache.clear();
  await tester.pumpWidget(_landing(initialText: null));
  await tester.pumpAndSettle();
  expect(_composeField(tester).controller!.text, 'survive restart');
});

testWidgets('session restores persisted draft after cache reset', (tester) async {
  await ComposeDraftStore().saveSession('ws-1', 's1', 'retry after restart');
  composeDraftCache.clear();
  await pumpSession(tester, session: session('s1'));
  await tester.pumpAndSettle();
  expect(_composeField(tester).controller!.text, 'retry after restart');
});
```

- [ ] **Step 2: Verify RED**

Run: `cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart test/pages/chat/session_chat_view_draft_cache_test.dart`

Expected: FAIL because a cleared memory cache has no persistent source.

- [ ] **Step 3: Implement hydrate and direct writes**

Restore memory cache synchronously, then invoke hydration. Assign hydrated text only if the controller is still empty. Change `_syncComposeDraft` and `_onComposeChanged` to invoke the matching async cache save on every input change; an empty field removes the cached and persisted entry.

- [ ] **Step 4: Verify GREEN**

Run: `cd client && flutter test test/services/compose/compose_draft_cache_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart test/pages/chat/session_chat_view_draft_cache_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/compose/compose_draft_cache.dart client/lib/pages/home_workspace/workspace/unbound_compose_body.dart client/lib/pages/chat/session_chat_view.dart client/test/services/compose/compose_draft_cache_test.dart client/test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart client/test/pages/chat/session_chat_view_draft_cache_test.dart
git commit -m "feat: restore persisted compose drafts"
```

### Task 3: Retain drafts until terminal delivery succeeds

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart`
- Test: `client/test/pages/chat/session_chat_view_draft_cache_test.dart`
- Test: `client/test/cubits/chat_cubit_test.dart`

**Interfaces:**
- `submitWorkspaceLandingMessage(...)` returns `Future<bool>`, true only after `deliverUserCommandToMember` completes successfully.

- [ ] **Step 1: Write failing submit lifecycle tests**

```dart
testWidgets('failed session delivery retains the persisted draft', (tester) async {
  await pumpSession(tester, session: session('s1'), onSubmit: (_) async => const HistoryContinueSubmitResult.failed());
  await tester.enterText(_composeField, 'do not lose this');
  await tester.tap(_submitButton);
  await tester.pumpAndSettle();
  expect(await ComposeDraftStore().loadSession('ws-1', 's1'), 'do not lose this');
});

testWidgets('successful session delivery removes the persisted draft', (tester) async {
  await pumpSession(tester, session: session('s1'), onSubmit: (_) async => const HistoryContinueSubmitResult(ok: true, channel: HistoryContinueChannel.pty));
  await tester.enterText(_composeField, 'delivered');
  await tester.tap(_submitButton);
  await tester.pumpAndSettle();
  expect(await ComposeDraftStore().loadSession('ws-1', 's1'), isNull);
});
```

Add landing coverage where false retains and true deletes; assert `ChatCubit.deleteSession` removes the stored session draft.

- [ ] **Step 2: Verify RED**

Run: `cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart test/pages/chat/session_chat_view_draft_cache_test.dart test/cubits/chat_cubit_test.dart`

Expected: FAIL because landing clears at `onSessionOpened` and the session submit path does not clear the persistent store after success.

- [ ] **Step 3: Delete only on success**

Remove `onSessionOpened: composeDraftCache.clearLandingDraft(...)`. Return `false` from every unsuccessful landing path and `true` only after terminal delivery. Let the pane clear the landing draft when that result is true. In session compose, clear persistent draft after `result.ok`; failed sends restore the text and leave persistence intact. Await persistent session-draft clearing from `deleteSession`.

- [ ] **Step 4: Verify GREEN**

Run: `cd client && flutter test test/services/compose/compose_draft_store_test.dart test/services/compose/compose_draft_cache_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart test/pages/chat/session_chat_view_draft_cache_test.dart test/cubits/chat_cubit_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart client/lib/pages/home_workspace/workspace/workspace_session_actions.dart client/lib/pages/chat/session_chat_view.dart client/lib/cubits/chat_cubit.dart client/test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart client/test/pages/chat/session_chat_view_draft_cache_test.dart client/test/cubits/chat_cubit_test.dart
git commit -m "fix: retain compose drafts until delivery succeeds"
```

### Task 4: Verify repository quality

**Files:** Verify only.

- [ ] **Step 1: Format modified Dart files**

Run: `cd client && dart format lib/services/storage/workspace_layout.dart lib/services/compose/compose_draft_store.dart lib/services/compose/compose_draft_cache.dart lib/pages/home_workspace/workspace/unbound_compose_body.dart lib/pages/home_workspace/workspace/workspace_chat_pane.dart lib/pages/home_workspace/workspace/workspace_session_actions.dart lib/pages/chat/session_chat_view.dart lib/cubits/chat_cubit.dart test/services/compose/compose_draft_store_test.dart test/services/compose/compose_draft_cache_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_draft_cache_test.dart test/pages/chat/session_chat_view_draft_cache_test.dart test/cubits/chat_cubit_test.dart`

- [ ] **Step 2: Run analysis**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: exit code 0.

- [ ] **Step 3: Run the repository test runner**

Run: `cd client && dart run tool/run_tests.dart`

Expected: exit code 0.

- [ ] **Step 4: Inspect final status**

Run: `git diff --check && git status --short`

Expected: no whitespace errors and only intended changes.
