import 'dart:convert';

import 'message.dart';
import 'subagent_attachment.dart';

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

bool cheapStringEqual(String a, String b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  if (a.length <= 128) return a == b;
  return a.substring(0, 64) == b.substring(0, 64) &&
      a.substring(a.length - 64) == b.substring(b.length - 64);
}

String _toolResultText(Object? result) =>
    result is String ? result : (result?.toString() ?? '');

bool _toolCallsCheapEqual(AiToolCallPart a, AiToolCallPart b) {
  if (a.toolCallId != b.toolCallId ||
      a.toolName != b.toolName ||
      a.status != b.status ||
      a.isError != b.isError ||
      subagentAgentIdFromPart(a) != subagentAgentIdFromPart(b)) {
    return false;
  }
  final aArgsText = a.argsText ?? '';
  final bArgsText = b.argsText ?? '';
  if (a.argsText != null || b.argsText != null) {
    if (!cheapStringEqual(aArgsText, bArgsText)) return false;
  } else if ((a.args?.length ?? 0) != (b.args?.length ?? 0)) {
    return false;
  }
  return cheapStringEqual(_toolResultText(a.result), _toolResultText(b.result));
}

bool messagesCheapEqual(AiMessage a, AiMessage b) {
  if (identical(a, b)) return true;
  if (a.id != b.id ||
      a.role != b.role ||
      a.status != b.status ||
      a.deliveryChannel != b.deliveryChannel ||
      a.parts.length != b.parts.length) {
    return false;
  }
  for (var i = 0; i < a.parts.length; i++) {
    final pa = a.parts[i];
    final pb = b.parts[i];
    if (pa.runtimeType != pb.runtimeType) return false;
    switch (pa) {
      case AiTextPart(:final text):
        if (!cheapStringEqual(text, (pb as AiTextPart).text)) return false;
      case AiReasoningPart(:final text):
        if (!cheapStringEqual(text, (pb as AiReasoningPart).text)) return false;
      case AiToolCallPart():
        if (!_toolCallsCheapEqual(pa, pb as AiToolCallPart)) return false;
    }
  }
  return true;
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
