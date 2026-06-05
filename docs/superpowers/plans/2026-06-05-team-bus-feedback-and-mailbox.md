# Team-Bus Feedback & Mailbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user real-time confirmation that messages sent while a member is parked on `wait_for_message` are delivered (terminal overlay bound to consumption state), add a live full-team mailbox view to the right tools panel, and default that panel to the tabbed icon-switcher layout.

**Architecture:** Three slices over the existing `mixed`-mode team-bus stack. (A) flip a `LayoutPreferences` default. (B) `TeamBus.deliverUserCommand` returns the new message id; `TerminalSession` re-emits parked submissions on a broadcast stream; a self-contained `ParkedSendOverlay` widget shows a banner per pending message and removes it once `TeamBus.isUnread(memberId, id)` reports the receiving member took it. (C) a read-only `TeamBus.messagesSnapshot()` aggregates member inbox logs into `BusFeedEntry`s; a polling `MailboxCubit` (modeled on `MemberPresenceCubit`) feeds a `MailboxPanel`; the right-tools switcher is refactored to a uniform `List<ToolView>` so the conditional (mixed-mode-only) mailbox view slots in cleanly.

**Tech Stack:** Flutter, `flutter_bloc`, `equatable`, `flutter_alacritty` terminal engine, existing `team_bus` services.

**Spec:** `docs/superpowers/specs/2026-06-05-team-bus-feedback-and-mailbox-design.md`

**Branch:** `feat/team-bus-feedback-mailbox`

**Working dir for all commands:** `client/` (run `cd client` first).

**Verification gate (run before each commit unless noted):**
`flutter analyze --no-fatal-infos --no-fatal-warnings <changed files>` and the task's test command.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/models/layout_preferences.dart` | default arrangement | Modify |
| `lib/services/team_bus/member_inbox.dart` | `containsUnread`, `snapshotRecords` | Modify |
| `lib/services/team_bus/team_bus.dart` | `deliverUserCommand` returns id; `isUnread`; `messagesSnapshot` | Modify |
| `lib/services/team_bus/bus_feed_entry.dart` | feed DTO | Create |
| `lib/services/team_bus/bus_user_line_capture.dart` | routing gains `isUnread`; `onUserLine` returns id | Modify |
| `lib/cubits/chat/tab_team_bus_coordinator.dart` | wire new routing fields | Modify |
| `lib/services/terminal/pending_user_message.dart` | overlay DTO | Create |
| `lib/services/terminal/terminal_session.dart` | parked-submission stream + unread query | Modify |
| `lib/widgets/terminal/parked_send_overlay.dart` | banner overlay widget | Create |
| `lib/pages/chat/chat_workbench_terminal.dart` | mount overlay in Stack | Modify |
| `lib/cubits/mailbox_cubit.dart` | polling feed cubit | Create |
| `lib/widgets/right_tools/tool_view.dart` | `ToolView` value type | Create |
| `lib/widgets/right_tools/tabbed_panel.dart` | icon switcher over `List<ToolView>` | Modify (rewrite) |
| `lib/widgets/right_tools/stacked_panel.dart` | stacked over `List<ToolView>` | Modify |
| `lib/widgets/right_tools/mailbox_panel.dart` | mailbox feed UI | Create |
| `lib/widgets/right_tools/right_tools_panel.dart` | build `List<ToolView>` incl. mailbox | Modify |
| `lib/app/app_shell.dart` + `lib/main.dart` | provide `MailboxCubit` | Modify |
| `lib/l10n/app_en.arb` / `app_zh.arb` | new strings | Modify |

---

## Task 1: Default the right tools panel to tabs

**Files:**
- Modify: `lib/models/layout_preferences.dart:21` and `:57`
- Test: `test/models/layout_preferences_default_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/models/layout_preferences_default_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';

void main() {
  test('defaults toolsArrangement to tabs', () {
    expect(const LayoutPreferences().toolsArrangement, ToolsArrangement.tabs);
    expect(
      LayoutPreferences.fromJson(const {}).toolsArrangement,
      ToolsArrangement.tabs,
    );
  });

  test('still honors a persisted stacked preference', () {
    expect(
      LayoutPreferences.fromJson(const {'toolsArrangement': 'stacked'})
          .toolsArrangement,
      ToolsArrangement.stacked,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart`
Expected: FAIL — first test expects `tabs`, gets `stacked`.

- [ ] **Step 3: Change the two defaults**

In `lib/models/layout_preferences.dart`, constructor (≈ line 21):
```dart
    this.toolsArrangement = ToolsArrangement.tabs,
```
In `fromJson` (≈ line 57):
```dart
      toolsArrangement:
          _enumValue(ToolsArrangement.values, json['toolsArrangement']) ??
          ToolsArrangement.tabs,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/layout_preferences.dart client/test/models/layout_preferences_default_test.dart
git commit -m "feat(layout): default right tools panel to tabbed layout"
```

---

## Task 2: Bus — deliverUserCommand returns id, unread query

**Files:**
- Modify: `lib/services/team_bus/member_inbox.dart`
- Modify: `lib/services/team_bus/team_bus.dart:331` (`deliverUserCommand`) and add `isUnread`
- Test: `test/services/team_bus/team_bus_user_command_test.dart`

- [ ] **Step 1: Write the failing test**

Append inside `main()` of `test/services/team_bus/team_bus_user_command_test.dart`:

```dart
  test('deliverUserCommand returns id; isUnread flips when taken', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    final node = AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    );
    bus.declareMember(node);

    final id = bus.deliverUserCommand('leader', 'hello');
    expect(id, isNotEmpty);
    expect(bus.isUnread('leader', id), isTrue);
    expect(bus.isUnread('leader', 'nope'), isFalse);
    expect(bus.isUnread('ghost', id), isFalse);

    await node.inbox.waitAndTake(timeout: const Duration(seconds: 1));
    expect(bus.isUnread('leader', id), isFalse);
  });

  test('deliverUserCommand returns empty id for blank line', () {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    expect(bus.deliverUserCommand('leader', '   '), isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/team_bus_user_command_test.dart`
Expected: FAIL — `isUnread` undefined / `deliverUserCommand` returns void.

- [ ] **Step 3: Add `containsUnread` to MemberInbox**

In `lib/services/team_bus/member_inbox.dart`, next to `isEmpty`/`unreadCount` (≈ line 41):
```dart
  /// True iff [id] is still in the unread working set (not yet taken/read).
  bool containsUnread(String id) =>
      _unread.any((r) => r.message.id == id);
```

- [ ] **Step 4: deliverUserCommand returns id; add TeamBus.isUnread**

In `lib/services/team_bus/team_bus.dart`, change `deliverUserCommand` (≈ line 331) to return the id:
```dart
  /// UI 用户在成员 wait 期间提交的一行 → 信箱（`from: user`）。返回新建消息 id，
  /// 空行 / 未知成员返回空串。
  String deliverUserCommand(String memberId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    final node = _members[memberId];
    if (node == null) return '';
    final id = _env.ids();
    _deliverToMember(
      memberId,
      TeamMessage(
        id: id,
        from: userSenderId,
        to: memberId,
        content: trimmed,
      ),
    );
    return id;
  }

  /// 该成员信箱里 [id] 是否仍未读（未被取走 / 未读）。
  bool isUnread(String memberId, String id) =>
      _members[memberId]?.inbox.containsUnread(id) ?? false;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/team_bus_user_command_test.dart`
Expected: PASS (all tests, including the two original ones).

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/team_bus/member_inbox.dart client/lib/services/team_bus/team_bus.dart client/test/services/team_bus/team_bus_user_command_test.dart
git commit -m "feat(team-bus): deliverUserCommand returns id; add isUnread query"
```

---

## Task 3: Routing — carry id + unread query to the session

**Files:**
- Modify: `lib/services/team_bus/bus_user_line_capture.dart:4-12`
- Modify: `lib/cubits/chat/tab_team_bus_coordinator.dart:117-129`
- Test: `test/services/team_bus/bus_user_line_capture_test.dart` (run existing — must still pass)

- [ ] **Step 1: Extend `BusUserInputRouting`**

In `lib/services/team_bus/bus_user_line_capture.dart`, replace the `BusUserInputRouting` class (lines 4-12) with:
```dart
class BusUserInputRouting {
  const BusUserInputRouting({
    required this.shouldIntercept,
    required this.onUserLine,
    this.isUnread,
  });

  final bool Function() shouldIntercept;

  /// Submits a captured line. Returns the delivered message id (empty if none),
  /// so the terminal session can track it for the parked-send overlay.
  final String Function(String line) onUserLine;

  /// Whether a previously-delivered message id is still unread in the target
  /// member's inbox. Null when not wired (overlay disabled).
  final bool Function(String id)? isUnread;
}
```

Note: `BusUserLineCapture._submit` already calls `_routing.onUserLine(line)` and ignores the return — no change needed there. Existing test closures (`onUserLine: (line) => submitted = line`) already evaluate to `String` and stay valid; the new `isUnread` field is optional.

- [ ] **Step 2: Run existing capture tests to verify they still pass**

Run: `cd client && flutter test test/services/team_bus/bus_user_line_capture_test.dart`
Expected: PASS (unchanged behavior).

- [ ] **Step 3: Wire the coordinator routing**

In `lib/cubits/chat/tab_team_bus_coordinator.dart`, `busUserInputRouting` (lines 125-128), replace the returned routing with:
```dart
    return BusUserInputRouting(
      shouldIntercept: () => bus.isWaitingForMessage(memberId),
      onUserLine: (line) => bus.deliverUserCommand(memberId, line),
      isUnread: (id) => bus.isUnread(memberId, id),
    );
```

- [ ] **Step 4: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/team_bus/bus_user_line_capture.dart lib/cubits/chat/tab_team_bus_coordinator.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/bus_user_line_capture.dart client/lib/cubits/chat/tab_team_bus_coordinator.dart
git commit -m "feat(team-bus): routing carries message id and unread query"
```

---

## Task 4: TerminalSession — parked-submission stream + unread query

**Files:**
- Create: `lib/services/terminal/pending_user_message.dart`
- Modify: `lib/services/terminal/terminal_session.dart` (fields, connect wiring ≈ 276-278, dispose ≈ 765)

- [ ] **Step 1: Create the DTO**

Create `lib/services/terminal/pending_user_message.dart`:
```dart
/// A line the user submitted while a member was parked on `wait_for_message`,
/// tracked by the terminal overlay until the receiving member consumes it.
class PendingUserMessage {
  const PendingUserMessage({required this.id, required this.content});

  /// Delivered team-bus message id (used to poll consumption via the session).
  final String id;

  /// The submitted text, shown in the banner.
  final String content;
}
```

- [ ] **Step 2: Add stream + unread query to the session**

In `lib/services/terminal/terminal_session.dart`:

Add the import near the other `team_bus` import (line 17):
```dart
import 'pending_user_message.dart';
```

Add fields next to `_busUserLineCapture` (≈ line 90):
```dart
  final StreamController<PendingUserMessage> _parkedSubmissions =
      StreamController<PendingUserMessage>.broadcast();
  BusUserInputRouting? _busRouting;

  /// Lines submitted to the bus while parked. The overlay subscribes to show a
  /// "sent, awaiting receipt" banner per message.
  Stream<PendingUserMessage> get parkedUserSubmissions =>
      _parkedSubmissions.stream;

  /// Whether a previously-submitted parked message is still unread by its
  /// recipient. Used by the overlay to clear the banner once consumed.
  bool isUnreadParkedMessage(String id) => _busRouting?.isUnread?.call(id) ?? false;
```

Replace the capture construction (lines 276-278) with a wrapping routing that records the id and emits:
```dart
    final incomingRouting = busUserInputRouting;
    _busRouting = incomingRouting;
    _busUserLineCapture = incomingRouting == null
        ? null
        : BusUserLineCapture(
            BusUserInputRouting(
              shouldIntercept: incomingRouting.shouldIntercept,
              isUnread: incomingRouting.isUnread,
              onUserLine: (line) {
                final id = incomingRouting.onUserLine(line);
                if (id.isNotEmpty) {
                  _parkedSubmissions.add(
                    PendingUserMessage(id: id, content: line),
                  );
                }
                return id;
              },
            ),
          );
```

In `dispose()` (≈ line 765), close the controller:
```dart
  void dispose() {
    disconnect();
    engine.dispose();
    unawaited(_parkedSubmissions.close());
  }
```
(`unawaited` and `dart:async` are already imported in this file.)

- [ ] **Step 3: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/terminal/terminal_session.dart lib/services/terminal/pending_user_message.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/terminal/pending_user_message.dart client/lib/services/terminal/terminal_session.dart
git commit -m "feat(terminal): expose parked-submission stream and unread query"
```

---

## Task 5: ParkedSendOverlay widget + l10n

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb`
- Create: `lib/widgets/terminal/parked_send_overlay.dart`
- Test: `test/widgets/parked_send_overlay_test.dart`

- [ ] **Step 1: Add l10n strings**

In `lib/l10n/app_en.arb`, add (place near other `terminal*` keys):
```json
  "terminalParkedSendPending": "Sent, awaiting receipt: {content}",
  "@terminalParkedSendPending": {
    "placeholders": { "content": { "type": "String" } }
  },
  "terminalParkedSendDismiss": "Dismiss",
```
In `lib/l10n/app_zh.arb`, add the same keys:
```json
  "terminalParkedSendPending": "已发送，等待接收：{content}",
  "@terminalParkedSendPending": {
    "placeholders": { "content": { "type": "String" } }
  },
  "terminalParkedSendDismiss": "关闭",
```

- [ ] **Step 2: Regenerate localizations**

Run: `cd client && flutter pub get`
Expected: regenerates `app_localizations*.dart` (so `l10n.terminalParkedSendPending(content)` exists).

- [ ] **Step 3: Write the failing widget test**

Create `test/widgets/parked_send_overlay_test.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';
import 'package:teampilot/widgets/terminal/parked_send_overlay.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Stack(children: [child])),
    );

void main() {
  testWidgets('shows a banner until the message is consumed', (tester) async {
    final controller = StreamController<PendingUserMessage>.broadcast();
    final unread = <String>{'m1'};
    addTearDown(controller.close);

    await tester.pumpWidget(_host(ParkedSendOverlay(
      submissions: controller.stream,
      isUnread: unread.contains,
      pollInterval: const Duration(milliseconds: 50),
    )));

    controller.add(const PendingUserMessage(id: 'm1', content: 'hello'));
    await tester.pump();
    expect(find.textContaining('hello'), findsOneWidget);

    // Consume it → next poll removes the banner.
    unread.remove('m1');
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('hello'), findsNothing);
  });

  testWidgets('manual dismiss removes the banner', (tester) async {
    final controller = StreamController<PendingUserMessage>.broadcast();
    addTearDown(controller.close);

    await tester.pumpWidget(_host(ParkedSendOverlay(
      submissions: controller.stream,
      isUnread: (_) => true,
      pollInterval: const Duration(milliseconds: 50),
    )));

    controller.add(const PendingUserMessage(id: 'm1', content: 'bye'));
    await tester.pump();
    expect(find.textContaining('bye'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.textContaining('bye'), findsNothing);
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/parked_send_overlay_test.dart`
Expected: FAIL — `ParkedSendOverlay` not found.

- [ ] **Step 5: Implement the overlay**

Create `lib/widgets/terminal/parked_send_overlay.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/terminal/pending_user_message.dart';

/// Banner overlay that confirms lines sent to the team bus while a member is
/// parked on `wait_for_message`. A banner persists until [isUnread] reports the
/// recipient consumed it (or the user dismisses it manually). Self-contained so
/// it can be unit-tested without a real terminal engine.
class ParkedSendOverlay extends StatefulWidget {
  const ParkedSendOverlay({
    required this.submissions,
    required this.isUnread,
    this.pollInterval = const Duration(seconds: 1),
    super.key,
  });

  final Stream<PendingUserMessage> submissions;
  final bool Function(String id) isUnread;
  final Duration pollInterval;

  @override
  State<ParkedSendOverlay> createState() => _ParkedSendOverlayState();
}

class _ParkedSendOverlayState extends State<ParkedSendOverlay> {
  final List<PendingUserMessage> _pending = [];
  StreamSubscription<PendingUserMessage>? _sub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(ParkedSendOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.submissions, widget.submissions)) {
      _pending.clear();
      _subscribe();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = widget.submissions.listen(_onSubmission);
  }

  void _onSubmission(PendingUserMessage msg) {
    if (_pending.any((m) => m.id == msg.id)) return;
    setState(() => _pending.add(msg));
    _ensureTicker();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(widget.pollInterval, (_) => _prune());
  }

  void _prune() {
    final before = _pending.length;
    _pending.removeWhere((m) => !widget.isUnread(m.id));
    if (_pending.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (_pending.length != before) setState(() {});
  }

  void _dismiss(PendingUserMessage msg) {
    setState(() => _pending.removeWhere((m) => m.id == msg.id));
    if (_pending.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final msg in _pending)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Material(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: [
                      Icon(Icons.outgoing_mail,
                          size: 18, color: cs.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.terminalParkedSendPending(msg.content),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSecondaryContainer),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: l10n.terminalParkedSendDismiss,
                        color: cs.onSecondaryContainer,
                        onPressed: () => _dismiss(msg),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/parked_send_overlay_test.dart`
Expected: PASS (both tests).

- [ ] **Step 7: Commit**

```bash
git add client/lib/widgets/terminal/parked_send_overlay.dart client/test/widgets/parked_send_overlay_test.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "feat(terminal): parked-send confirmation overlay"
```

---

## Task 6: Mount the overlay in the running terminal

**Files:**
- Modify: `lib/pages/chat/chat_workbench_terminal.dart` (imports + Stack ≈ 61-120)

- [ ] **Step 1: Add the import**

In `lib/pages/chat/chat_workbench_terminal.dart`, with the other widget imports (≈ line 17):
```dart
import '../../widgets/terminal/parked_send_overlay.dart';
```

- [ ] **Step 2: Add the overlay to the Stack**

Inside the `Stack`'s `children` (after the `if (findVisible) Positioned(...)` block, before the closing `]` at ≈ line 120), add:
```dart
          ParkedSendOverlay(
            submissions: session.parkedUserSubmissions,
            isUnread: session.isUnreadParkedMessage,
          ),
```

- [ ] **Step 3: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/chat/chat_workbench_terminal.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/chat/chat_workbench_terminal.dart
git commit -m "feat(chat): show parked-send overlay over the running terminal"
```

---

## Task 7: Mailbox feed aggregation (model + bus)

**Files:**
- Create: `lib/services/team_bus/bus_feed_entry.dart`
- Modify: `lib/services/team_bus/member_inbox.dart` (add `snapshotRecords`)
- Modify: `lib/services/team_bus/team_bus.dart` (add `messagesSnapshot`)
- Test: `test/services/team_bus/team_bus_feed_test.dart`

- [ ] **Step 1: Create the feed DTO**

Create `lib/services/team_bus/bus_feed_entry.dart`:
```dart
import 'package:equatable/equatable.dart';

/// One row in the mailbox feed: a team-bus message flattened for display.
class BusFeedEntry extends Equatable {
  const BusFeedEntry({
    required this.from,
    required this.to,
    required this.content,
    required this.createdAt,
    required this.isUnread,
  });

  final String from;
  final String to;
  final String content;
  final int createdAt;
  final bool isUnread;

  @override
  List<Object?> get props => [from, to, content, createdAt, isUnread];
}
```

- [ ] **Step 2: Write the failing test**

Create `test/services/team_bus/team_bus_feed_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import 'support/fake_member_launcher.dart';

void main() {
  test('messagesSnapshot aggregates member inboxes sorted by time', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    bus.declareMember(AgentNode.test(
      memberId: 'worker',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));

    bus.deliverUserCommand('leader', 'to leader');
    bus.deliverUserCommand('worker', 'to worker');

    final feed = await bus.messagesSnapshot();
    expect(feed.length, 2);
    expect(feed.every((e) => e.from == TeamBus.userSenderId), isTrue);
    expect(feed.map((e) => e.content),
        containsAll(['to leader', 'to worker']));
    expect(feed.every((e) => e.isUnread), isTrue);
    // Sorted ascending by createdAt.
    expect(feed.first.createdAt <= feed.last.createdAt, isTrue);
  });

  test('messagesSnapshot is empty with no members', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    expect(await bus.messagesSnapshot(), isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/team_bus_feed_test.dart`
Expected: FAIL — `messagesSnapshot` undefined.

- [ ] **Step 4: Add `snapshotRecords` to MemberInbox**

In `lib/services/team_bus/member_inbox.dart`, after `readPage` (≈ line 174), add:
```dart
  /// All known records for this member (read + unread). Reads the log when
  /// present, then folds in any un-flushed in-memory unread tail (dedup by id).
  /// Falls back to the in-memory unread set when there is no log.
  Future<List<LoggedMessage>> snapshotRecords() async {
    final log = _log;
    if (log == null) return List<LoggedMessage>.of(_unread);
    final persisted = await log.load(memberId);
    final ids = {for (final r in persisted) r.message.id};
    return [
      ...persisted,
      for (final r in _unread)
        if (!ids.contains(r.message.id)) r,
    ];
  }
```

- [ ] **Step 5: Add `messagesSnapshot` to TeamBus**

In `lib/services/team_bus/team_bus.dart`, add the import at the top (with the other relative imports):
```dart
import 'bus_feed_entry.dart';
```
Add the method near `messages` reading helpers (after `unreadCountFor`, ≈ line 299):
```dart
  /// Read-only full-team feed: unions every member inbox's records, dedups by
  /// message id (broadcasts land in multiple inboxes), and sorts by time.
  Future<List<BusFeedEntry>> messagesSnapshot() async {
    final byId = <String, BusFeedEntry>{};
    for (final node in _members.values) {
      final records = await node.inbox.snapshotRecords();
      for (final r in records) {
        final existing = byId[r.message.id];
        if (existing == null) {
          byId[r.message.id] = BusFeedEntry(
            from: r.message.from,
            to: r.message.to,
            content: r.message.content,
            createdAt: r.createdAt,
            isUnread: r.isUnread,
          );
        } else {
          byId[r.message.id] = BusFeedEntry(
            from: existing.from,
            to: existing.to,
            content: existing.content,
            createdAt:
                existing.createdAt < r.createdAt ? existing.createdAt : r.createdAt,
            isUnread: existing.isUnread || r.isUnread,
          );
        }
      }
    }
    final entries = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return entries;
  }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client && flutter test test/services/team_bus/team_bus_feed_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/team_bus/bus_feed_entry.dart client/lib/services/team_bus/member_inbox.dart client/lib/services/team_bus/team_bus.dart client/test/services/team_bus/team_bus_feed_test.dart
git commit -m "feat(team-bus): read-only full-team message snapshot"
```

---

## Task 8: MailboxCubit

**Files:**
- Create: `lib/cubits/mailbox_cubit.dart`
- Test: `test/cubits/mailbox_cubit_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/cubits/mailbox_cubit_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mailbox_cubit.dart';
import 'package:teampilot/services/team_bus/agent_node.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../services/team_bus/support/fake_member_launcher.dart';

void main() {
  test('attach polls the active bus and emits entries + unread count', () async {
    final bus = TeamBus(launcher: FakeMemberLauncher());
    bus.declareMember(AgentNode.test(
      memberId: 'leader',
      lifecycle: MemberLifecycle.running,
      activity: MemberActivity.active,
    ));
    bus.deliverUserCommand('leader', 'hello');

    final cubit = MailboxCubit(activeBus: () => bus);
    addTearDown(cubit.close);

    cubit.attach();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(cubit.state.entries.single.content, 'hello');
    expect(cubit.state.totalUnread, 1);

    cubit.detach();
    expect(cubit.state.entries, isEmpty);
  });

  test('emits empty when no active bus', () async {
    final cubit = MailboxCubit(activeBus: () => null);
    addTearDown(cubit.close);
    cubit.attach();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(cubit.state.entries, isEmpty);
    expect(cubit.state.totalUnread, 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/mailbox_cubit_test.dart`
Expected: FAIL — `MailboxCubit` not found.

- [ ] **Step 3: Implement the cubit**

Create `lib/cubits/mailbox_cubit.dart`:
```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/team_bus/bus_feed_entry.dart';
import '../services/team_bus/team_bus.dart';

class MailboxState extends Equatable {
  const MailboxState({this.entries = const [], this.totalUnread = 0});

  final List<BusFeedEntry> entries;
  final int totalUnread;

  @override
  List<Object?> get props => [entries, totalUnread];
}

/// Polls the active tab's [TeamBus] for the full-team message feed while a
/// mailbox view is mounted. Mirrors MemberPresenceCubit's attach/detach poll.
class MailboxCubit extends Cubit<MailboxState> {
  MailboxCubit({
    required TeamBus? Function() activeBus,
    Duration pollInterval = const Duration(milliseconds: 1500),
  })  : _activeBus = activeBus,
        _pollInterval = pollInterval,
        super(const MailboxState());

  final TeamBus? Function() _activeBus;
  final Duration _pollInterval;
  Timer? _timer;
  bool _attached = false;
  bool _inFlight = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    _timer?.cancel();
    unawaited(_tick());
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _timer?.cancel();
    _timer = null;
    if (state.entries.isNotEmpty || state.totalUnread != 0) {
      emit(const MailboxState());
    }
  }

  Future<void> _tick() async {
    if (!_attached || _inFlight) return;
    final bus = _activeBus();
    if (bus == null) {
      if (state.entries.isNotEmpty) emit(const MailboxState());
      return;
    }
    _inFlight = true;
    try {
      final entries = await bus.messagesSnapshot();
      if (!_attached || isClosed) return;
      final unread = entries.where((e) => e.isUnread).length;
      final next = MailboxState(entries: entries, totalUnread: unread);
      if (next != state) emit(next);
    } finally {
      _inFlight = false;
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/mailbox_cubit_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/mailbox_cubit.dart client/test/cubits/mailbox_cubit_test.dart
git commit -m "feat(mailbox): polling cubit for full-team feed"
```

---

## Task 9: ToolView refactor (switcher takes a uniform view list)

**Files:**
- Create: `lib/widgets/right_tools/tool_view.dart`
- Modify (rewrite): `lib/widgets/right_tools/tabbed_panel.dart`
- Modify: `lib/widgets/right_tools/stacked_panel.dart`
- Test: `test/widgets/right_tools_tabbed_panel_test.dart`

- [ ] **Step 1: Create `ToolView`**

Create `lib/widgets/right_tools/tool_view.dart`:
```dart
import 'package:flutter/widgets.dart';

/// One selectable view in the right tools switcher: an icon + tooltip label,
/// its content, and an optional badge count (e.g. mailbox unread).
class ToolView {
  const ToolView({
    required this.icon,
    required this.label,
    required this.child,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final int badgeCount;
}
```

- [ ] **Step 2: Write the failing test**

Create `test/widgets/right_tools_tabbed_panel_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/right_tools/tabbed_panel.dart';
import 'package:teampilot/widgets/right_tools/tool_view.dart';

void main() {
  testWidgets('switches the visible view when an icon is tapped',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TabbedPanel(views: const [
          ToolView(
              icon: Icons.groups_outlined,
              label: 'Members',
              child: Text('members-body')),
          ToolView(
              icon: Icons.mail_outline,
              label: 'Mailbox',
              child: Text('mailbox-body'),
              badgeCount: 3),
        ]),
      ),
    ));

    expect(find.text('members-body'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mail_outline));
    await tester.pump();
    expect(find.text('mailbox-body'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // badge
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/right_tools_tabbed_panel_test.dart`
Expected: FAIL — `TabbedPanel` signature mismatch (`views` not defined).

- [ ] **Step 4: Rewrite `tabbed_panel.dart`**

Replace the entire contents of `lib/widgets/right_tools/tabbed_panel.dart`:
```dart
import 'package:flutter/material.dart';

import '../../theme/app_icon_sizes.dart';
import 'tool_view.dart';

/// VSCode-style tool panel: a horizontal row of icon buttons at the top
/// switches the single visible view. Driven by a uniform [ToolView] list so
/// callers control which views (and conditional ones) appear.
class TabbedPanel extends StatefulWidget {
  const TabbedPanel({required this.views, super.key});

  final List<ToolView> views;

  @override
  State<TabbedPanel> createState() => _TabbedPanelState();
}

class _TabbedPanelState extends State<TabbedPanel> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.views.isEmpty) return const SizedBox.shrink();
    if (widget.views.length == 1) return widget.views.single.child;
    final selected = _selected.clamp(0, widget.views.length - 1);

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              for (var i = 0; i < widget.views.length; i++)
                _SwitcherButton(
                  view: widget.views[i],
                  active: i == selected,
                  onTap: () => setState(() => _selected = i),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          child: IndexedStack(
            index: selected,
            sizing: StackFit.expand,
            children: [for (final v in widget.views) v.child],
          ),
        ),
      ],
    );
  }
}

class _SwitcherButton extends StatelessWidget {
  const _SwitcherButton({
    required this.view,
    required this.active,
    required this.onTap,
  });

  final ToolView view;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    return Tooltip(
      message: view.label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(view.icon, size: AppIconSizes.md, color: color),
              if (view.badgeCount > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(minWidth: 14),
                    child: Text(
                      '${view.badgeCount}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onError,
                        fontSize: 9,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Update `stacked_panel.dart` to take views**

In `lib/widgets/right_tools/stacked_panel.dart`, change the class to accept `List<ToolView>` and stack their children. Replace the constructor + fields + the early `build` lines:

Replace the import block top to add:
```dart
import 'tool_view.dart';
```
Replace constructor/fields (lines 10-17):
```dart
  const StackedPanel({required this.views, super.key});

  final List<ToolView> views;
```
Replace the body of `build` lines 20-22 with:
```dart
    final panels = [for (final v in views) v.child];
    if (panels.isEmpty) return const SizedBox.shrink();
    if (panels.length == 1) return panels.single;
```
and below, the `TwoPaneSplitView` uses `panels.first` / `panels.sublist(1)` exactly as before (the local `panels` variable replaces the old parameter). Remove the now-unused `preferences` field and its `import '../../models/layout_preferences.dart';` only if no longer referenced — but `membersSplit` is still used via `context.read<LayoutCubit>()`, so keep the `LayoutCubit` import; the persisted split now reads from the cubit state. Update the `initialFraction`:
```dart
          initialFraction: context.read<LayoutCubit>().state.preferences.membersSplit,
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client && flutter test test/widgets/right_tools_tabbed_panel_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/widgets/right_tools/tool_view.dart client/lib/widgets/right_tools/tabbed_panel.dart client/lib/widgets/right_tools/stacked_panel.dart client/test/widgets/right_tools_tabbed_panel_test.dart
git commit -m "refactor(right-tools): drive switcher from a uniform ToolView list"
```

---

## Task 10: MailboxPanel + RightToolsPanel integration + l10n

**Files:**
- Create: `lib/widgets/right_tools/mailbox_panel.dart`
- Modify: `lib/widgets/right_tools/right_tools_panel.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb`

- [ ] **Step 1: Add l10n strings**

In `lib/l10n/app_en.arb`:
```json
  "mailbox": "Mailbox",
  "mailboxEmpty": "No messages yet",
```
In `lib/l10n/app_zh.arb`:
```json
  "mailbox": "信箱",
  "mailboxEmpty": "暂无消息",
```
Then run: `cd client && flutter pub get`

- [ ] **Step 2: Create `MailboxPanel`**

Create `lib/widgets/right_tools/mailbox_panel.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/mailbox_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/team_bus/bus_feed_entry.dart';
import '../../services/team_bus/team_bus.dart';

/// Live full-team team-bus message feed. Attaches the [MailboxCubit] poll while
/// mounted; tapping a row jumps to the relevant member's chat tab.
class MailboxPanel extends StatefulWidget {
  const MailboxPanel({required this.team, required this.cwd, super.key});

  final TeamConfig team;
  final String cwd;

  @override
  State<MailboxPanel> createState() => _MailboxPanelState();
}

class _MailboxPanelState extends State<MailboxPanel> {
  @override
  void initState() {
    super.initState();
    context.read<MailboxCubit>().attach();
  }

  @override
  void dispose() {
    context.read<MailboxCubit>().detach();
    super.dispose();
  }

  void _jumpTo(BusFeedEntry entry) {
    final targetId =
        entry.from == TeamBus.userSenderId ? entry.to : entry.from;
    if (targetId == TeamBus.userSenderId || targetId == '*') return;
    final matches = widget.team.members.where((m) => m.id == targetId);
    if (matches.isEmpty) return;
    unawaited(context.read<ChatCubit>().openMemberTab(
          widget.team,
          matches.first,
          workspaceCwd: widget.cwd,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final entries = context.watch<MailboxCubit>().state.entries;
    if (entries.isEmpty) {
      return Center(
        child: Text(l10n.mailboxEmpty,
            style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[entries.length - 1 - i]; // newest first
        return ListTile(
          dense: true,
          leading: Icon(
            e.isUnread ? Icons.mark_email_unread_outlined : Icons.email_outlined,
            size: 18,
            color: e.isUnread ? cs.primary : cs.onSurfaceVariant,
          ),
          title: Text('${e.from} → ${e.to}',
              style: Theme.of(context).textTheme.labelSmall),
          subtitle: Text(e.content, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _jumpTo(e),
        );
      },
    );
  }
}
```

- [ ] **Step 3: Integrate into `RightToolsPanel`**

In `lib/widgets/right_tools/right_tools_panel.dart`:

Add imports:
```dart
import '../../cubits/mailbox_cubit.dart';
import '../../models/team_config.dart';
import 'mailbox_panel.dart';
import 'tool_view.dart';
```

Replace the `panels` construction and the return (lines 95-152) with a `ToolView` list. Replace from `final panels = <Widget>[` through the end of `build`:
```dart
    final mailboxState = context.watch<MailboxCubit>().state;
    final activeBus = chatCubit.activeTab?.teamBus;
    final showMailbox =
        team.teamMode == TeamMode.mixed && activeBus != null;

    final views = <ToolView>[
      if (widget.preferences.membersVisible)
        ToolView(
          icon: Icons.groups_outlined,
          label: context.l10n.members,
          child: MembersPanel(
            teamCli: team.cli,
            members: members,
            memberPresence: context.watch<MemberPresenceCubit>().state.presence,
            selectedMemberId: chatCubit.state.selectedMemberId,
            onSelected: (id) {
              final member = team.members.firstWhere((m) => m.id == id);
              final cubit = _chatCubit;
              if (cubit == null) return;
              unawaited(
                cubit.openMemberTab(team, member, workspaceCwd: widget.cwd),
              );
              maybeDismissDrawer();
            },
            onOpen: (id) {
              final member = team.members.firstWhere((m) => m.id == id);
              final cubit = _chatCubit;
              if (cubit == null) return;
              unawaited(
                cubit.openMemberTab(team, member, workspaceCwd: widget.cwd),
              );
              maybeDismissDrawer();
            },
            onLaunchAll: throttledAsync('right_tools_launch_all', () async {
              final cubit = _chatCubit;
              if (cubit == null) return;
              await cubit.launchAllMembers(team, workspaceCwd: widget.cwd);
              maybeDismissDrawer();
            }),
          ),
        ),
      if (widget.preferences.fileTreeVisible)
        ToolView(
          icon: Icons.folder_outlined,
          label: context.l10n.fileTree,
          child: FileTreePanel(team: team, cwd: widget.cwd),
        ),
      if (widget.preferences.gitVisible)
        ToolView(
          icon: Icons.account_tree_outlined,
          label: context.l10n.sourceControl,
          child: GitSourceControlPanel(cwd: widget.cwd),
        ),
      if (showMailbox)
        ToolView(
          icon: Icons.mail_outline,
          label: context.l10n.mailbox,
          badgeCount: mailboxState.totalUnread,
          child: MailboxPanel(team: team, cwd: widget.cwd),
        ),
    ];
    return Container(
      key: widget.panelKey,
      color: cs.workspaceSubtleSurface,
      child: widget.preferences.toolsArrangement == ToolsArrangement.tabs
          ? TabbedPanel(views: views)
          : StackedPanel(views: views),
    );
  }
}
```
(Add `import '../../l10n/l10n_extensions.dart';` if not already imported.)

- [ ] **Step 4: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets/right_tools/`
Expected: No issues. (If `ToolsArrangement` / `LayoutPreferences` import is now unused in `stacked_panel.dart`, remove it; if `layout_preferences` import is unused in `tabbed_panel.dart`, it was already removed in Task 9.)

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/right_tools/mailbox_panel.dart client/lib/widgets/right_tools/right_tools_panel.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
git commit -m "feat(mailbox): full-team feed view in the right tools switcher"
```

---

## Task 11: Provide MailboxCubit (DI)

**Files:**
- Modify: `lib/app/app_shell.dart` (field, constructor param, instantiation)
- Modify: `lib/main.dart` (BlocProvider + dispose)

- [ ] **Step 1: Add the field + constructor param in AppShell**

In `lib/app/app_shell.dart`, add the import:
```dart
import '../cubits/mailbox_cubit.dart';
```
Add a constructor param next to `required this.memberPresenceCubit,` (≈ line 76):
```dart
    required this.mailboxCubit,
```
Add the field next to `final MemberPresenceCubit memberPresenceCubit;` (≈ line 107):
```dart
  final MailboxCubit mailboxCubit;
```

- [ ] **Step 2: Instantiate and pass it**

In `lib/app/app_shell.dart`, after `chatCubit.bindPresenceCubit(memberPresenceCubit);` (≈ line 488):
```dart
  final mailboxCubit = MailboxCubit(activeBus: () => chatCubit.activeTab?.teamBus);
```
In the `return AppShell(` call, after `memberPresenceCubit: memberPresenceCubit,` (≈ line 521):
```dart
    mailboxCubit: mailboxCubit,
```

- [ ] **Step 3: Provide and dispose it in main.dart**

In `lib/main.dart`, in the `MultiBlocProvider` providers list, after `BlocProvider.value(value: shell.memberPresenceCubit),` (≈ line 175):
```dart
                BlocProvider.value(value: shell.mailboxCubit),
```
In `_AppShutdownScopeState.dispose` (≈ line 68), also close it (and thread `mailboxCubit` through `_AppShutdownScope` the same way `chatCubit` is). Update `_AppShutdownScope`:
```dart
class _AppShutdownScope extends StatefulWidget {
  const _AppShutdownScope({
    required this.chatCubit,
    required this.mailboxCubit,
    required this.child,
  });

  final ChatCubit chatCubit;
  final MailboxCubit mailboxCubit;
  final Widget child;

  @override
  State<_AppShutdownScope> createState() => _AppShutdownScopeState();
}

class _AppShutdownScopeState extends State<_AppShutdownScope> {
  @override
  void dispose() {
    unawaited(widget.chatCubit.close());
    unawaited(widget.mailboxCubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```
Add the import in `main.dart`:
```dart
import 'cubits/mailbox_cubit.dart';
```
At the `_AppShutdownScope(` usage site, pass `mailboxCubit: shell.mailboxCubit,` (search for `_AppShutdownScope(` and add the param next to `chatCubit: shell.chatCubit,`).

- [ ] **Step 4: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/app/app_shell.dart lib/main.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add client/lib/app/app_shell.dart client/lib/main.dart
git commit -m "feat(di): provide MailboxCubit bound to the active tab bus"
```

---

## Task 12: Full verification gate

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole client**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues. Fix any unused-import / type errors surfaced by the refactor (notably leftover `panels:`/`preferences:` references to the old `TabbedPanel`/`StackedPanel` API anywhere else).

- [ ] **Step 2: Run the full unit/widget suite**

Run: `cd client && flutter test --exclude-tags integration`
Expected: All pass.

- [ ] **Step 3: Manual golden-path check (document result)**

In a `mixed`-mode team session: launch a member, get it to `wait_for_message`, type a line + Enter in its terminal. Confirm: (a) the "Sent, awaiting receipt: …" banner appears immediately and disappears once the agent receives it; (b) the right tools panel opens in tabbed mode by default with a Mailbox icon (unread badge), and the feed shows the sent message; (c) tapping a feed row opens the relevant member's tab. Note results in the PR description.

- [ ] **Step 4: Final commit (if any analyze fixes were needed)**

```bash
git add -A
git commit -m "chore: analyze/test fixes for team-bus feedback & mailbox"
```

---

## Self-Review Notes

- **Spec coverage:** A → Task 1. B (deliver id/unread → T2; routing → T3; session stream → T4; overlay widget+l10n → T5; mount → T6). C (feed model+aggregation → T7; cubit → T8; ToolView/switcher refactor → T9; panel+integration+l10n → T10; DI → T11). Verification → T12. All spec sections mapped.
- **Type consistency:** `onUserLine: String Function(String)` and `isUnread: bool Function(String)?` consistent across T3/T4; `deliverUserCommand → String` used by T3 routing and T7 deliver path; `BusFeedEntry` fields identical in T7/T8/T10; `ToolView{icon,label,child,badgeCount}` identical in T9/T10; `MailboxState{entries,totalUnread}` identical in T8/T10; `PendingUserMessage{id,content}` identical in T4/T5.
- **Deviation flagged:** The mailbox feed reads inbox records via `snapshotRecords()` (log when present, else in-memory unread). In tests/desktop without a configured `BusMessageLog`, the feed reflects the in-memory unread working set; with a log it includes read history. Matches the spec's "logged messages" intent while degrading gracefully.
