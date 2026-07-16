import 'package:ai_message_core/ai_message_core.dart';

class ThreadTurn {
  const ThreadTurn({required this.id, required this.messageIds});
  final String id;
  final List<String> messageIds;
}

List<ThreadTurn> buildTurns(List<AiMessage> messages) {
  if (messages.isEmpty) return const [];
  final turns = <ThreadTurn>[];
  for (final m in messages) {
    if (m.role == AiRole.user || turns.isEmpty) {
      turns.add(ThreadTurn(id: m.id, messageIds: [m.id]));
    } else {
      final last = turns.removeLast();
      turns.add(
        ThreadTurn(id: last.id, messageIds: [...last.messageIds, m.id]),
      );
    }
  }
  return turns;
}

String messageContentIdentity(AiMessage m) {
  final buf = StringBuffer('${m.id}|${m.role.name}|${m.status.name}');
  for (final p in m.parts) {
    buf.write('|');
    switch (p) {
      case AiTextPart(:final text):
        buf.write('t:$text');
      case AiReasoningPart(:final text):
        buf.write('r:$text');
      case AiToolCallPart(
        :final toolCallId,
        :final toolName,
        :final args,
        :final argsText,
        :final status,
        :final isError,
        :final result,
      ):
        buf.write(
          'c:$toolCallId:$toolName:${_stableArgs(args)}:${argsText ?? ''}:'
          '${status.name}:$isError:${result ?? ''}',
        );
    }
  }
  return buf.toString();
}

/// Stable encoding of tool args for content identity (sorted keys).
String _stableArgs(Map<String, Object?>? args) {
  if (args == null) return '';
  final keys = args.keys.toList()..sort();
  return '{${keys.map((k) => '$k:${args[k]}').join(',')}}';
}

String turnContentIdentity(ThreadTurn turn, List<AiMessage> messages) {
  final byId = {for (final m in messages) m.id: m};
  final buf = StringBuffer(turn.id);
  for (final id in turn.messageIds) {
    final m = byId[id];
    buf.write('|');
    buf.write(m == null ? 'missing:$id' : messageContentIdentity(m));
  }
  return buf.toString();
}

/// Returns [previous] if membership+roles+ids unchanged; else [buildTurns].
List<ThreadTurn> reuseTurnsIfSameMembership({
  required List<ThreadTurn> previous,
  required List<AiMessage> messages,
}) {
  final next = buildTurns(messages);
  if (previous.length != next.length) return next;
  for (var i = 0; i < next.length; i++) {
    if (previous[i].id != next[i].id) return next;
    final a = previous[i].messageIds;
    final b = next[i].messageIds;
    if (a.length != b.length) return next;
    for (var j = 0; j < a.length; j++) {
      if (a[j] != b[j]) return next;
    }
  }
  return previous;
}
