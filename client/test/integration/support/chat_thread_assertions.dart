import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/services/session/ai_history_pending_text.dart';
import 'package:teampilot/services/terminal/pending_user_message.dart';

/// Plain text for any thread message (user or assistant).
String chatThreadMessagePlainText(AiMessage m) =>
    m.parts.whereType<AiTextPart>().map((p) => p.text).join('\n');

/// User bubbles currently published on [history.runtime] (transcript tip,
/// sticky mailbox locals, and optimistic PTY pendings).
List<AiMessage> chatThreadUserMessages(AiHistoryCubit history) => [
  for (final m in history.runtime.messages)
    if (m.role == AiRole.user) m,
];

/// Assistant bubbles currently published on [history.runtime].
List<AiMessage> chatThreadAssistantMessages(AiHistoryCubit history) => [
  for (final m in history.runtime.messages)
    if (m.role == AiRole.assistant) m,
];

/// Human-readable dump for failure messages / diagnostics bundles.
String dumpThread(AiHistoryCubit history) {
  final buf = StringBuffer('AiHistoryCubit thread dump\n');
  buf.writeln(
    'status=${history.state.status.name} '
    'awaiting=${history.state.awaitingAssistant} '
    'total=${history.state.totalMessageCount} '
    'session=${history.state.sessionId} '
    'member=${history.state.memberId}',
  );
  final messages = history.runtime.messages;
  if (messages.isEmpty) {
    buf.writeln('(no runtime messages)');
    return buf.toString();
  }
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    final text = chatThreadMessagePlainText(m).replaceAll('\n', '\\n');
    buf.writeln('[$i] ${m.role.name} id=${m.id} text=$text');
  }
  return buf.toString();
}

/// Asserts a user bubble (pending, sticky, or transcript) contains [text].
void expectUserBubble(
  AiHistoryCubit history,
  String text, {
  bool Function(String haystack, String expected)? matches,
}) {
  final match = matches ?? (haystack, expected) => haystack.contains(expected);
  final users = chatThreadUserMessages(history);
  final hit = users.any((m) => match(chatThreadMessagePlainText(m), text));
  expect(
    hit,
    isTrue,
    reason:
        'Expected user bubble containing ${jsonQuote(text)}\n'
        '${dumpThread(history)}',
  );
}

/// Asserts ≥3 assistant markers are visible on the History thread.
///
/// Callers should soft-reload / [AiHistoryCubit.flushHeldTip] first when the
/// tip may still be held behind [AiHistoryCubit.hasHeldAssistantTip].
void expectAssistantMarkers(
  AiHistoryCubit history,
  List<String> markers, {
  bool Function(String haystack, String marker)? matches,
}) {
  expect(
    markers.length,
    greaterThanOrEqualTo(3),
    reason: 'Matrix cells require ≥3 assistant markers, got ${markers.length}',
  );
  final match = matches ?? (haystack, marker) => haystack.contains(marker);
  final assistants = chatThreadAssistantMessages(history);
  final haystacks = [
    for (final m in assistants) chatThreadMessagePlainText(m),
  ];
  final missing = <String>[];
  for (final marker in markers) {
    if (!haystacks.any((h) => match(h, marker))) {
      missing.add(marker);
    }
  }
  expect(
    missing,
    isEmpty,
    reason:
        'Missing assistant markers: $missing\n'
        '${dumpThread(history)}',
  );
}

/// Asserts the mailbox compose path: [text] was Queued under [mailId], and
/// [history] now shows the sticky local user bubble (`mailbox:$mailId`).
///
/// [queuedSnapshot] is the Queued strip state **before or at** consume time
/// (harness mirrors [SessionChatView]'s Queued list). Sticky id matches
/// production: `mailbox:${mailId}`.
void expectMailboxQueuedThenSticky({
  required Iterable<PendingUserMessage> queuedSnapshot,
  required AiHistoryCubit history,
  required String text,
  required String mailId,
}) {
  final target = normalizeAiHistoryPendingText(text);
  final queuedHit = queuedSnapshot.any(
    (m) =>
        m.id == mailId &&
        normalizeAiHistoryPendingText(m.content) == target,
  );
  expect(
    queuedHit,
    isTrue,
    reason:
        'Expected Queued row mailId=$mailId text=${jsonQuote(text)}\n'
        'queued=${queuedSnapshot.map((m) => '${m.id}:${m.content}').toList()}\n'
        '${dumpThread(history)}',
  );

  final stickyId = 'mailbox:$mailId';
  final sticky = history.runtime.messages.where(
    (m) => m.role == AiRole.user && m.id == stickyId,
  );
  expect(
    sticky,
    isNotEmpty,
    reason:
        'Expected sticky user bubble id=$stickyId\n'
        '${dumpThread(history)}',
  );
  expect(
    normalizeAiHistoryPendingText(
      chatThreadMessagePlainText(sticky.first),
    ),
    target,
    reason:
        'Sticky bubble text mismatch for $stickyId\n'
        '${dumpThread(history)}',
  );
}

/// Tiny quote helper so failure reasons stay readable without `dart:convert`.
String jsonQuote(String s) => '"${s.replaceAll('"', r'\"')}"';
