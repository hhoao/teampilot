import 'dart:convert';

import 'message.dart';

/// Stable fingerprint of an [AiMessage] for reuse / selective rebuild.
///
/// Includes id, role, status, and part payloads. Two messages with the same
/// identity may safely share one instance across softReload snapshots.
String messageContentIdentity(AiMessage m) {
  final buf = StringBuffer(
    '${m.id}|${m.role.name}|${m.status.name}|${m.deliveryChannel ?? ''}',
  );
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
        final argsJson = args != null && args.isNotEmpty ? jsonEncode(args) : '';
        buf.write(
          'c:$toolCallId:$toolName:${argsText ?? ''}:$argsJson:'
          '${status.name}:$isError:${result ?? ''}',
        );
    }
  }
  return buf.toString();
}

/// True when [a] and [b] have the same length and per-index content identity.
bool sameMessageListContent(List<AiMessage> a, List<AiMessage> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (messageContentIdentity(a[i]) != messageContentIdentity(b[i])) {
      return false;
    }
  }
  return true;
}
