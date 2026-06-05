# Right Tools VSCode Tabs · Mailbox View · Parked-Send Terminal Overlay

Date: 2026-06-05
Status: Approved (design)

## Background / Motivation

In `mixed` team-bus mode, when a member's CLI is parked on `wait_for_message`, the
user's keystrokes are routed to the bus instead of the PTY. On Enter,
`BusUserLineCapture` submits the line to `TeamBus.deliverUserCommand` and sends
`Ctrl-U` to wipe the CLI input box (so the CLI does not double-submit). The net
effect: **the line the user just sent vanishes from the screen with no
confirmation** — it feels like the message was dropped.

Root cause confirmed in code:
- `lib/services/team_bus/bus_user_line_capture.dart:74` — on Enter, `_submit()`
  routes the line to the bus and returns `Ctrl-U` to clear the CLI input.
- `lib/services/team_bus/team_bus.dart:331` — `deliverUserCommand` builds
  `TeamMessage(from: user, to: memberId)` into the member's inbox.

This spec delivers three changes (all approved):

- **A. Default the right tools panel to the tabbed (icon-switcher) layout.**
- **B. Parked-send terminal overlay** — a banner over the terminal confirming
  "已发送，等待接收：<line>" that persists until the message is consumed by the
  receiving member (not a fixed timer).
- **C. Mailbox view** — a 4th right-tools view: a live, full-team chronological
  feed of team-bus messages, with click-to-jump to the relevant member.

Decision log: feedback is delivered via a Flutter overlay (not by writing into
the terminal buffer) because full-screen TUIs (e.g. Claude Code's Ink renderer)
repaint the viewport during the wait and would clobber injected text. The
overlay is fully under our control and TUI-independent.

## Non-Goals

- No change to the bus delivery hot path (`deliver` / `send` / receive loop).
- No persistence of overlay/mailbox UI state across restarts.
- No backward-compat shims for old layout-preference values (existing persisted
  `stacked` preferences keep working; only the *default* changes).
- No remote/SSH-specific handling beyond what already exists for terminals.

---

## A. Default tabbed layout

`lib/models/layout_preferences.dart`:
- Constructor default `toolsArrangement` `stacked → tabs` (≈ line 21).
- `fromJson` fallback `stacked → tabs` (≈ line 57).

Users who already persisted a `stacked` preference are unaffected; only new /
unset preferences pick up the tabbed default. The tabbed switcher is the
VSCode-style icon row already implemented in
`lib/widgets/right_tools/tabbed_panel.dart`.

---

## B. Parked-send terminal overlay

### Goal
On Enter during park, immediately show a banner confirming the send, and keep it
visible until the receiving member consumes (reads/takes) that exact message.

### Data flow

```
keystroke → TerminalSession input path → BusUserLineCapture.filter
   └─ on Enter: _submit() → routing.onUserLine(line) ─┐
                                                       ├─ bus.deliverUserCommand(memberId, line) → returns message id
                                                       └─ session emits PendingUserMessage{id, content} on stream
overlay widget:
   - on stream event: add pending entry, ensure 1s ticker running
   - ticker tick: for each pending, if !session.isUnread(id) → remove
   - render banner(s) for remaining pending entries
```

### Components / changes

1. **`TeamBus.deliverUserCommand` returns the message id** (`team_bus.dart:331`).
   Currently `void`. Change to `String` (the new `TeamMessage.id`). Sole caller
   is the routing factory below.

2. **`MemberInbox.containsUnread(String id) → bool`**
   (`lib/services/team_bus/member_inbox.dart`): true iff `_unread` contains a
   record whose `message.id == id`.

3. **`TeamBus.isUnread(String memberId, String id) → bool`**
   (`team_bus.dart`): forwards to the member node's `inbox.containsUnread(id)`;
   false if member unknown.

4. **`BusUserInputRouting`** (`bus_user_line_capture.dart`) gains:
   - `onUserLine` return type `void → String` (the delivered message id).
   - new field `bool Function(String id) isUnread`.
   `BusUserLineCapture._submit()` still calls `onUserLine(line)`; it may ignore
   the returned id (the *session* captures it via its wrapper — see below).

5. **`TabTeamBusCoordinator.busUserInputRouting`**
   (`tab_team_bus_coordinator.dart:117`): wire the new members:
   - `onUserLine: (line) => bus.deliverUserCommand(memberId, line)` (now returns id).
   - `isUnread: (id) => bus.isUnread(memberId, id)`.

6. **`TerminalSession`** (`lib/services/terminal/terminal_session.dart`):
   - Add `final _parkedSubmissions = StreamController<PendingUserMessage>.broadcast();`
     and getter `Stream<PendingUserMessage> get parkedUserSubmissions`.
   - When constructing the capture (≈ line 276), wrap the incoming routing so
     `onUserLine` records the returned id and pushes
     `PendingUserMessage(id, content)` onto the stream **before** returning the id.
   - Expose `bool isUnreadParkedMessage(String id)` delegating to the wrapped
     routing's `isUnread` (so the overlay can poll consumption without holding a
     bus reference).
   - Close the controller in `dispose`.
   - `PendingUserMessage` is a tiny value type (`{String id, String content}`),
     placed near `TerminalSession` or in a small model file.

7. **`ChatWorkbenchRunningTerminal`** (`lib/pages/chat/chat_workbench_terminal.dart`):
   StatelessWidget → StatefulWidget.
   - Subscribe to `session.parkedUserSubmissions`; on event add a pending entry
     and start a periodic `Timer` (1s) if not running.
   - Each tick: drop entries where `!session.isUnreadParkedMessage(id)`; stop the
     timer when the list is empty.
   - Render banner(s) inside the **existing `Stack`** (≈ line 61), e.g. top-center
     `Positioned`, dim/info styling, text "已发送，等待接收：<content>", with a
     manual `×` dismiss as an escape hatch (member dead → never consumed).
   - Reset subscription/timer on `session` change and in `dispose`.

### Edge cases
- Immediate consumption → banner flashes briefly (acceptable); optional short
  fade-out animation.
- Multiple unconsumed sends → stacked banners (or a compact "+N" if many).
- Non-parked sends never enter this path (`shouldIntercept()` gates `_submit`).
- Tab/session close disposes session → controller closed, overlay gone.

---

## C. Mailbox view (full-team message feed)

### Data source
The active tab's `TeamBus` (`chatCubit.activeTab?.teamBus`,
`lib/cubits/chat_cubit.dart:99`). Only present for `mixed`-mode team sessions;
otherwise the view is hidden.

### Components / changes

1. **`BusFeedEntry`** model (`lib/services/team_bus/bus_feed_entry.dart`):
   `{String from, String to, String content, int createdAt, bool isUnread}`.

2. **`TeamBus.messagesSnapshot() → List<BusFeedEntry>`** (`team_bus.dart`):
   read-only aggregation that unions every member inbox's logged messages and
   sorts by `createdAt` ascending. Uses existing per-member logs
   (`MemberInbox` records carry `seq`/`createdAt`/`isUnread`). Read-only; does not
   mutate inbox state or touch the deliver path. (A user→member message lives in
   `member`'s inbox; `from == user` for human-submitted lines.)

3. **`MailboxCubit`** (`lib/cubits/mailbox_cubit.dart`), modeled on
   `MemberPresenceCubit`:
   - Injected resolver `TeamBus? Function() activeBus` (wired in `app_shell` to
     `() => chatCubit.activeTab?.teamBus`).
   - `attach()` / `detach()` gate a periodic poll (~1.5s) that calls
     `messagesSnapshot()` and emits `MailboxState{entries, totalUnread}`.
   - No-op / empty state when the resolver returns null.
   - Stops polling when detached or closed.

4. **`MailboxPanel`** (`lib/widgets/right_tools/mailbox_panel.dart`):
   - Watches `MailboxCubit`; renders the feed as rows `from → to：content`
     (chronological; newest emphasized). Unread entries visually distinguished.
   - Tap a row → jump to the relevant member's chat tab via
     `chatCubit.openMemberTab(team, member, workspaceCwd: cwd)`. Target rule:
     if `from == user` jump to `to`, else jump to `from`. Ignore taps for
     `user`/unknown ids.
   - Empty state when no messages.

5. **Right-tools switcher refactor + integration**
   (`lib/widgets/right_tools/{right_tools_panel,tabbed_panel,stacked_panel}.dart`):
   - Introduce `ToolView { IconData icon, String label, Widget child }`
     (`lib/widgets/right_tools/tool_view.dart`).
   - `RightToolsPanel` builds a single `List<ToolView>` (members / file tree /
     git / mailbox) and passes it to `TabbedPanel` / `StackedPanel`. This removes
     the current fragile index-alignment between a `panels` list and a separately
     rebuilt icon/label list, and lets a *conditional* view (mailbox, which
     depends on team mode — something `TabbedPanel` can't evaluate) be added
     cleanly.
   - Mailbox `ToolView` is appended **only when** `team.teamMode == TeamMode.mixed`
     and `tab.teamBus != null`. Icon `Icons.mail_outline`, with an unread-count
     badge driven by `MailboxState.totalUnread`.
   - `TabbedPanel` renders `view.icon` (tooltip `view.label`); `StackedPanel`
     stacks `view.child`.

6. **DI wiring** (`lib/app/app_shell.dart`): register `MailboxCubit` with the
   active-bus resolver alongside the other cubits; provide it where the right
   tools panel is mounted.

---

## Testing

- **A:** unit-assert `LayoutPreferences()` and `fromJson({})` default to `tabs`;
  `fromJson({'toolsArrangement': 'stacked'})` still yields `stacked`.
- **B (bus):** `deliverUserCommand` returns a non-empty id; `isUnread` true right
  after deliver, false after the member takes/confirms the message
  (`waitAndTake` + `confirmRead`). `MemberInbox.containsUnread` covered.
- **B (overlay):** widget test pumps a fake `TerminalSession` exposing a
  controllable `parkedUserSubmissions` stream + scripted `isUnreadParkedMessage`;
  assert banner appears on event and disappears once `isUnread` flips false;
  manual `×` removes it.
- **C (bus):** `messagesSnapshot()` merges multiple members' logs sorted by
  `createdAt`, with correct `isUnread`/`from`/`to`; empty when no bus.
- **C (cubit):** with an injected resolver returning a fake bus, `attach()`
  polls and emits entries + `totalUnread`; `detach()` stops polling; null bus →
  empty.
- **C (panel):** mailbox `ToolView` present only in mixed mode with a bus;
  tap-to-jump resolves the correct member per the target rule.
- Mock subprocess/filesystem via constructor injection; cubit tests touching
  `AppStorage` use `setUpTestAppStorage()` / `tearDownTestAppStorage()`.
- Gate: `flutter analyze --no-fatal-infos --no-fatal-warnings` and
  `flutter test --exclude-tags integration` clean.

## File summary

| Change | File |
|---|---|
| Default tabs | `lib/models/layout_preferences.dart` |
| Overlay: bus id + unread query | `lib/services/team_bus/team_bus.dart`, `member_inbox.dart` |
| Overlay: routing fields | `lib/services/team_bus/bus_user_line_capture.dart` |
| Overlay: routing wiring | `lib/cubits/chat/tab_team_bus_coordinator.dart` |
| Overlay: session stream + query | `lib/services/terminal/terminal_session.dart` |
| Overlay: banner | `lib/pages/chat/chat_workbench_terminal.dart` |
| Mailbox: feed aggregation + model | `lib/services/team_bus/team_bus.dart`, `bus_feed_entry.dart` |
| Mailbox: cubit | `lib/cubits/mailbox_cubit.dart` |
| Mailbox: panel | `lib/widgets/right_tools/mailbox_panel.dart` |
| Switcher refactor + integration | `lib/widgets/right_tools/{tool_view,right_tools_panel,tabbed_panel,stacked_panel}.dart` |
| DI wiring | `lib/app/app_shell.dart` |
| l10n | `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb` |
