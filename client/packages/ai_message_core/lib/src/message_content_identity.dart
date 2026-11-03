import 'dart:convert';

import 'message.dart';
import 'subagent_attachment.dart';

/// Per-instance part fingerprints.
///
/// Parts are immutable value objects — mutation goes through `copyWith`, which
/// allocates a new instance — so a digest computed once for a part instance
/// stays valid. This keeps identity cheap for the live tip, which can hold
/// hundreds of parts and megabytes of tool output: unchanged parts hit the
/// cache instead of re-serialising their payload.
final Expando<String> _partDigestCache = Expando<String>('aiMessagePartDigest');

/// Length + hash of a payload string.
///
/// `String.hashCode` is cached on the string instance by the VM, so unchanged
/// payloads cost nothing after the first call and only the freshly built
/// streaming string is hashed.
String _payloadDigest(String? text) =>
    text == null ? '-' : '${text.length}:${text.hashCode}';

/// Stable fingerprint of an [AiMessage] for reuse / selective rebuild.
///
/// Includes id, role, status, and part payloads. Two messages with the same
/// identity may safely share one instance across softReload snapshots.
///
/// The result is a fixed-size digest, never the payload itself: hosts recompute
/// it on every streaming chunk (see `ExternalStoreAiThreadRuntime.setMessages`),
/// so embedding text/tool output would make each chunk O(turn size).
String messageContentIdentity(AiMessage m) {
  final buf = StringBuffer(
    '${m.id}|${m.role.name}|${m.status.name}|${m.deliveryChannel ?? ''}',
  );
  for (final p in m.parts) {
    buf.write('|');
    buf.write(_partDigest(p));
  }
  return buf.toString();
}

String _partDigest(AiMessagePart part) {
  final cached = _partDigestCache[part];
  if (cached != null) return cached;
  final digest = switch (part) {
    AiTextPart(:final text) => 't:${_payloadDigest(text)}',
    AiReasoningPart(:final text) => 'r:${_payloadDigest(text)}',
    AiToolCallPart(
      :final toolCallId,
      :final toolName,
      :final args,
      :final argsText,
      :final status,
      :final isError,
      :final result,
    ) =>
      'c:$toolCallId:$toolName:${_payloadDigest(argsText)}:${_argsDigest(args)}:'
          '${status.name}:$isError:${_payloadDigest(_toolResultText(result))}',
  };
  _partDigestCache[part] = digest;
  return digest;
}

String _argsDigest(Map<String, Object?>? args) {
  if (args == null || args.isEmpty) return '-';
  final json = jsonEncode(args);
  return '${json.length}:${json.hashCode}';
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
