# Unified Chat Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Chat the single primary workbench surface (unbound new-chat + bound transcript), keep Terminal secondary, and default all Chat submits / silent creates to stay on Chat.

**Architecture:** Breaking renames (`history`→`chat`, `composeActive`→`newChatActive`, remove `historySubmitSwitchesToTerminal`). Thread `preserveWorkbenchView` through create/open so unbound submit and silent create land on Chat. Bound continue uses the same `chatSubmitSwitchesToTerminal` gate. Keep the unbound IDE short-circuit (avoid mounting full `ChatPage` for new-chat) for performance; unify product naming and shared submit gate rather than one mega-widget.

**Tech Stack:** Flutter / Dart, `SessionPreferences`, `SessionCreateRequest` / `SessionOpenRequest`, existing Chat workbench overlay.

**Spec:** `docs/superpowers/specs/2026-07-21-unified-chat-surface-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/session_preferences.dart` | Replace `historySubmitSwitchesToTerminal` with `chatSubmitSwitchesToTerminal` |
| `client/lib/cubits/session_preferences_cubit.dart` | Setter rename |
| `client/lib/pages/chat/session_history_review_submit.dart` | Gate helper rename → Chat submit |
| `client/lib/cubits/chat/model/session_workbench_view.dart` | `history` → `chat` |
| `client/lib/pages/chat/chat_workbench_overlay.dart` | Overlay `history` → `chat` |
| `client/lib/cubits/chat/model/chat_state.dart` + `chat_tab_store.dart` + `chat_cubit.dart` | `composeActive` → `newChatActive`; `enterComposeMode` → `enterNewChat` |
| `client/lib/utils/workspace/workspace_compose_active.dart` | Rename helper → `workspaceNewChatActive` |
| `client/lib/cubits/chat/model/session_create_request.dart` | Add `preserveWorkbenchView` |
| `client/lib/services/launch/session_launch_pipeline.dart` | Pass flag into `SessionOpenRequest` on create |
| `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` | Unbound submit + silent create Chat landing |
| `client/lib/pages/chat_workbench.dart` | Bound continue reads new pref |
| `client/lib/pages/config/session_config_section.dart` | Settings row |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | Copy + toggle tooltips |
| `client/lib/pages/home_workspace/workspace/workspace_compose_landing_pane.dart` | Rename to `workspace_chat_pane.dart` / `WorkspaceChatPane` |
| `client/lib/pages/chat/session_history_review.dart` | Rename type/file toward bound Chat (`SessionChatView`) |
| Tests listed per task | Preference, gate, overlay, create preserve, continue |

---

### Task 1: Preference + submit gate (TDD)

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Modify: `client/lib/pages/chat/session_history_review_submit.dart`
- Modify: `client/test/models/session_preferences_test.dart`
- Modify: `client/test/pages/chat/session_history_submit_gate_test.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`

- [ ] **Step 1: Write failing tests**

In `session_preferences_test.dart`, replace history preference tests:

```dart
test('chatSubmitSwitchesToTerminal defaults false', () {
  expect(SessionPreferences().chatSubmitSwitchesToTerminal, isFalse);
});

test('chatSubmitSwitchesToTerminal JSON round-trip', () {
  final prefs = SessionPreferences(chatSubmitSwitchesToTerminal: true);
  final again = SessionPreferences.fromJson(prefs.toJson());
  expect(again.chatSubmitSwitchesToTerminal, isTrue);
});

test('absent chatSubmitSwitchesToTerminal key defaults false', () {
  expect(
    SessionPreferences.fromJson(const {}).chatSubmitSwitchesToTerminal,
    isFalse,
  );
});
```

In `session_history_submit_gate_test.dart` (rename file to `session_chat_submit_gate_test.dart` when convenient):

```dart
group('shouldSwitchToTerminalAfterChatSubmit', () {
  test('false keeps Chat', () {
    expect(shouldSwitchToTerminalAfterChatSubmit(false), isFalse);
  });
  test('true switches to Terminal', () {
    expect(shouldSwitchToTerminalAfterChatSubmit(true), isTrue);
  });
});
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/models/session_preferences_test.dart test/pages/chat/session_history_submit_gate_test.dart
```

- [ ] **Step 3: Implement**

- Remove `historySubmitSwitchesToTerminal` from model / `fromJson` / `copyWith` / `toJson`.
- Add `chatSubmitSwitchesToTerminal` (default `false`). Do **not** read the old JSON key.
- Cubit: `setChatSubmitSwitchesToTerminal`.
- Replace helper:

```dart
bool shouldSwitchToTerminalAfterChatSubmit(
  bool chatSubmitSwitchesToTerminal,
) => chatSubmitSwitchesToTerminal;
```

- AppKeys: `chatSubmitSwitchesToTerminalSwitch`.

**Compile-critical call sites in this task** (so Tasks 2–5 can run `flutter test`):

- `client/lib/pages/chat_workbench.dart`: read `chatSubmitSwitchesToTerminal` + `shouldSwitchToTerminalAfterChatSubmit`.
- `client/lib/pages/config/session_config_section.dart`: snapshot field + switch wired to new pref/key; **temporary** titles may still use old l10n getters until Task 6 replaces ARB — if that fails analyze, use hard-coded English strings for the row title/subtitle until Task 6, or do Task 6 ARB keys in the same commit as this row.

Do not leave `historySubmitSwitchesToTerminal` symbols anywhere under `client/lib`. Bound continue is fully switched to the new gate in this task.

- [ ] **Step 4: Run tests — expect PASS**

Also confirm package analyzes enough to compile:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/models/session_preferences.dart lib/pages/chat_workbench.dart lib/pages/config/session_config_section.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_preferences.dart \
  client/lib/cubits/session_preferences_cubit.dart \
  client/lib/pages/chat/session_history_review_submit.dart \
  client/lib/pages/chat_workbench.dart \
  client/lib/pages/config/session_config_section.dart \
  client/lib/utils/ui/app_keys.dart \
  client/test/models/session_preferences_test.dart \
  client/test/pages/chat/session_history_submit_gate_test.dart \
  client/test/pages/chat/session_chat_submit_gate_test.dart
git commit -m "$(cat <<'EOF'
feat(prefs): replace history submit terminal gate with chatSubmitSwitchesToTerminal

EOF
)"
```

---

### Task 2: `SessionWorkbenchView.history` → `chat`

**Files:**
- Modify: `client/lib/cubits/chat/model/session_workbench_view.dart`
- Mechanical sweep: all `SessionWorkbenchView.history` → `.chat` under `client/lib` and `client/test` (grep before/after)
- Update comments that say “History” for the workbench view

- [ ] **Step 1: Rename enum value**

```dart
/// Center-pane mode for a session workbench tab.
///
/// Independent of PTY [ChatTab.isRunning]: a running session may show
/// [chat] while the terminal stays mounted offstage.
enum SessionWorkbenchView { chat, terminal }
```

- [ ] **Step 2: Sweep references**

```bash
cd client && rg -n 'SessionWorkbenchView\.history' lib test
```

Replace every hit with `.chat`. Fix defaults on `ChatTab` and any `?? SessionWorkbenchView.history`.

- [ ] **Step 3: Run focused tests**

```bash
cd client && flutter test \
  test/pages/chat/chat_workbench_overlay_test.dart \
  test/services/launch/session_tab_surface_coordinator_test.dart \
  test/pages/chat/agent_permission_attention_banner_test.dart \
  test/widgets/sidebar_session_tile_test.dart
```

- [ ] **Step 4: Commit**

```bash
git commit -am "$(cat <<'EOF'
refactor: rename SessionWorkbenchView.history to chat

EOF
)"
```

---

### Task 3: `ChatWorkbenchOverlay.history` → `chat`

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench_overlay.dart`
- Modify: `client/test/pages/chat/chat_workbench_overlay_test.dart`
- Modify call sites that switch on `ChatWorkbenchOverlay.history`

- [ ] **Step 1: Update overlay enum + resolver**

```dart
enum ChatWorkbenchOverlay {
  remoteProvision,
  chat,
  sessionStarting,
  none,
}

ChatWorkbenchOverlay resolveChatWorkbenchOverlay({
  required SessionWorkbenchView workbenchView,
  required bool sessionConnectInProgress,
  required bool showRemoteProvision,
}) {
  if (showRemoteProvision) return ChatWorkbenchOverlay.remoteProvision;
  if (workbenchView == SessionWorkbenchView.chat) {
    return ChatWorkbenchOverlay.chat;
  }
  if (sessionConnectInProgress) return ChatWorkbenchOverlay.sessionStarting;
  return ChatWorkbenchOverlay.none;
}
```

- [ ] **Step 2: Update tests + UI switches** that map overlay → History widget to use `.chat`

- [ ] **Step 3: Run**

```bash
cd client && flutter test test/pages/chat/chat_workbench_overlay_test.dart
```

- [ ] **Step 4: Commit**

```bash
git commit -am "$(cat <<'EOF'
refactor: rename ChatWorkbenchOverlay.history to chat

EOF
)"
```

---

### Task 4: `composeActive` → `newChatActive`

**Files:**
- Modify: `client/lib/cubits/chat/model/chat_state.dart`
- Modify: `client/lib/cubits/chat/chat_tab_store.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (`enterComposeMode` → `enterNewChat`, clear helpers)
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart`
- Modify: `client/lib/widgets/workbench/workbench_session_sync.dart`
- Modify: `client/lib/app/app_shell.dart` (and any other `rg` hits)
- Modify: `client/lib/utils/workspace/workspace_compose_active.dart` → rename file to `workspace_new_chat_active.dart`:

```dart
bool workspaceNewChatActive(ChatCubit cubit, String tabScopeId) {
  final store = cubit.tabStore;
  if (store.activeWorkspaceId == tabScopeId) {
    return cubit.state.newChatActive;
  }
  return store.isNewChatActive(tabScopeId);
}
```

- Sweep: `composeActive`, `isComposeActive`, `enterComposeMode`, `workspaceComposeActive`, test descriptions

- [ ] **Step 1: Rename fields/APIs** (no aliases)

- [ ] **Step 2: Fix compile**

```bash
cd client && rg -n 'composeActive|enterComposeMode|isComposeActive|workspaceComposeActive' lib test
```

- [ ] **Step 3: Run**

```bash
cd client && flutter test \
  test/cubits/chat_cubit_test.dart \
  test/cubits/chat_cubit_session_shortcut_test.dart \
  test/cubits/workbench_cubit_test.dart \
  test/pages/chat/chat_workbench_slice_test.dart
```

- [ ] **Step 4: Commit**

```bash
git commit -am "$(cat <<'EOF'
refactor: rename composeActive to newChatActive

EOF
)"
```

---

### Task 5: Create path stays on Chat (silent + unbound submit)

**Files:**
- Modify: `client/lib/cubits/chat/model/session_create_request.dart`
- Modify: `client/lib/services/launch/session_launch_pipeline.dart` (`_runCreate`)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify/Create: `client/test/services/launch/session_tab_surface_coordinator_test.dart` (already covers `preserveWorkbenchView`)
- Add/extend tests for create request threading if missing

- [ ] **Step 1: Extend `SessionCreateRequest`**

```dart
const SessionCreateRequest({
  // ...existing...
  this.preserveWorkbenchView = false,
});

final bool preserveWorkbenchView;
```

In `_runCreate`, pass into `SessionOpenRequest`:

```dart
SessionOpenRequest(
  // ...existing...
  preserveWorkbenchView: request.preserveWorkbenchView,
)
```

- [ ] **Step 2: Silent create (`createAndOpenWorkspaceConversation` / `_requestCreateWorkspaceConversation`)**

Always pass `preserveWorkbenchView: true` so create+connect lands on Chat. Do **not** call `setSessionWorkbenchView(..., terminal)` after silent create.

- [ ] **Step 3: Unbound submit (`submitWorkspaceLandingMessage`)**

Add `preserveWorkbenchView` to `_requestCreateWorkspaceConversation`. Landing submit:

```dart
final switchToTerminal = shouldSwitchToTerminalAfterChatSubmit(
  context.read<SessionPreferencesCubit>().state.preferences.chatSubmitSwitchesToTerminal,
);

final status = await _requestCreateWorkspaceConversation(
  context,
  liveWorkspace,
  // ...existing args...
  preserveWorkbenchView: !switchToTerminal,
);
```

Silent create always passes `preserveWorkbenchView: true`. Rely on `SessionTabSurfaceCoordinator` for the workbench view — do **not** also `setSessionWorkbenchView` after create unless a call site still hardcodes Terminal (remove those hardcodes).

- [ ] **Step 4: Tests**

Extend `session_tab_surface_coordinator_test.dart`: cover **`surfaceNewTab`** with `preserveWorkbenchView: true` keeps `SessionWorkbenchView.chat` (silent create / unbound stay-on-Chat). Existing existing-tab continue case should already cover preserve.

```bash
cd client && flutter test test/services/launch/session_tab_surface_coordinator_test.dart
```

- [ ] **Step 5: Commit**

```bash
git commit -am "$(cat <<'EOF'
feat(chat): keep Chat view after create and unbound submit by default

EOF
)"
```

---

### Task 6: Settings UI + l10n

**Files:**
- Modify: `client/lib/pages/config/session_config_section.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/pages/chat/session_workbench_view_toggle.dart` (tooltips)
- After ARB: regenerate localizations (project’s usual `flutter gen-l10n` / build_runner flow used by this repo)

- [ ] **Step 1: ARB keys**

Remove `historySubmitSwitchesToTerminalTitle` / `Description`. Add:

```json
"chatSubmitSwitchesToTerminalTitle": "Switch to Terminal after Chat send",
"chatSubmitSwitchesToTerminalDescription": "When off (default), sending from Chat (new conversation or continue) stays on the Chat view while the terminal runs in the background. When on, switch to the Terminal after send.",
"sessionWorkbenchShowChat": "Show Chat",
"sessionWorkbenchShowTerminal": "Show Terminal"
```

Chinese (`app_zh.arb`):

```json
"chatSubmitSwitchesToTerminalTitle": "发送后切换到终端",
"chatSubmitSwitchesToTerminalDescription": "关闭（默认）时，在聊天页发送（新建或继续）后仍留在聊天视图，终端在后台运行。开启后，发送后切换到终端。",
"sessionWorkbenchShowChat": "显示聊天",
"sessionWorkbenchShowTerminal": "显示终端"
```

Replace `sessionWorkbenchShowHistory` with `sessionWorkbenchShowChat` (remove old key). Keep `sessionWorkbenchShowTerminal` if already present; update wording only if needed.

- [ ] **Step 2: Settings row**

Wire `TpPreferenceRow` to `snapshot.chatSubmitSwitchesToTerminal` / `cubit.setChatSubmitSwitchesToTerminal` / `AppKeys.chatSubmitSwitchesToTerminalSwitch`. Update `_SessionControlsSnapshot`.

- [ ] **Step 3: Toggle tooltips** use Show Chat / Show Terminal

- [ ] **Step 4: Gen l10n + warmup glyphs + analyze**

```bash
cd client && flutter gen-l10n
cd client && dart run tool/gen_warmup_glyphs.dart
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 5: Commit**

```bash
git commit -am "$(cat <<'EOF'
feat(ui): Chat submit terminal preference and workbench toggle copy

EOF
)"
```

---

### Task 7: Product shell rename (unbound + bound)

**Files:**
- Rename: `workspace_compose_landing_pane.dart` → `workspace_chat_pane.dart` (`WorkspaceChatPane`)
- Update: `workspace_ide_center.dart` to take `newChat` / build `WorkspaceChatPane`
- Rename: `session_history_review.dart` → `session_chat_view.dart` (`SessionChatView`); update imports / overlay builder in `chat_workbench.dart`
- Optionally rename `WorkspaceChatLanding` later in a follow-up if the diff is huge; acceptable to keep internal landing widget names for this task if `WorkspaceChatPane` is the public entry
- Update comments / test descriptions that say “compose landing” / “history review” for the product surface

- [ ] **Step 1: Rename unbound entry to `WorkspaceChatPane`**

Keep deferred mount / skeleton behavior. IDE center:

```dart
Widget buildWorkspaceIdeCenter({
  required bool newChat,
  required Workspace workspace,
  required Widget chatPage,
}) {
  if (newChat) {
    return WorkspaceChatPane(workspace: workspace);
  }
  return chatPage;
}
```

- [ ] **Step 2: Rename bound `SessionHistoryReview` → `SessionChatView`**

Same constructor/API; update workbench overlay branch that built History to build `SessionChatView`.

- [ ] **Step 3: Run broader tests**

```bash
cd client && flutter test \
  test/pages/chat/ \
  test/pages/home_workspace/ \
  test/cubits/chat_cubit_test.dart \
  test/models/session_preferences_test.dart
```

- [ ] **Step 4: Commit**

```bash
git commit -am "$(cat <<'EOF'
refactor(ui): rename landing/history entries to Chat pane and SessionChatView

EOF
)"
```

---

### Task 8: Verification

- [x] **Step 1: Full unit suite (exclude integration)**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && \
  flutter test --exclude-tags integration
```

Analyze: exit 0 (infos/warnings non-fatal). Unit suite: **3645 passed, 14 failed**. All 14 failures reproduce on `main` (not introduced by this branch):

| Failure cluster | Evidence |
|-----------------|----------|
| `cli_installer_service_test` (7) + `remote_preflight_cli_install_test` (1) | Same `Expected: true / Actual: false` on main |
| `codex_cli_tool_adapter_test` (2) | Extra `--dangerously-bypass-hook-trust` argv; same on main |
| `chat_page_*` (3) + `automation_editor_dialog_test` (1) | Missing `SessionPreferencesCubit` in harness; same on main; files not in branch diff |

- [x] **Step 2: Automated smoke proxies + manual checklist**

Automated checks covering the plan's smoke intent (all green on this branch):

1. Preference defaults / gate tests — `session_preferences_test`, `session_chat_submit_gate_test`
2. `surfaceNewTab` `preserveWorkbenchView` → Chat — `session_tab_surface_coordinator_test`
3. Bound continue uses `chatSubmitSwitchesToTerminal` — `chat_workbench.dart` wiring + gate helper
4. Settings/l10n keys present — `app_en.arb` / `app_zh.arb` (`chatSubmitSwitchesToTerminal*`, `openExistingSessionStartsTerminal*`)
5. `WorkspaceChatPane` / `SessionChatView` exist

Manual checklist for human (GUI not run by agent):

1. New chat send (preference off) → Chat stays, transcript updates
2. Preference on → new chat send goes Terminal
3. Continue from Chat (preference off) → stays Chat
4. Continue from Chat (preference on) → Terminal
5. Sidebar create without message → Chat + connected
6. Open existing with `openExistingSessionStartsTerminal` off → Chat
7. Workbench toggle Chat ↔ Terminal works

- [x] **Step 3: Final commit if any leftover cleanups**

```bash
git commit -am "$(cat <<'EOF'
chore: finish unified Chat surface renames and gates

EOF
)"
```

---

## Out of scope (do not do in this plan)

- Reading/migrating `historySubmitSwitchesToTerminal` from disk
- Merging unbound+bound into a single StatefulWidget that always mounts `ChatPage` (perf short-circuit stays)
- Automation dispatcher workbench changes
- Embedding Terminal in message bubbles
