import 'package:ai_message_core/ai_message_core.dart';

/// 去重结果：去重后的消息列表 + 被丢弃的消息（按原列表顺序）。
class AiHistoryDedupResult {
  const AiHistoryDedupResult({required this.messages, required this.removed});

  final List<AiMessage> messages;
  final List<AiMessage> removed;
}

/// Live 列表兜底去重（spec 2026-08-14）：
/// 1. 同 id → 保留最后一次出现；
/// 2. assistant 且文本 part 拼接完全相同的任意对：
///    - 工具结果数严格多者胜；
///    - 否则非文本 part 集合为超集者胜；
///    - 完全相同 → 保留第一条；
///    - 无法判定 → 两条都保留；
/// 3. user 消息不做文本去重（跨时间合法重复）。
/// 判定签名只含文本 part，不含 reasoning/tool。
AiHistoryDedupResult dedupeAiHistoryMessages(List<AiMessage> messages) {
  if (messages.length < 2) {
    return AiHistoryDedupResult(messages: messages, removed: const []);
  }
  final removed = <int>{};

  // Pass 1: 同 id 保留最后一次。
  final lastById = <String, int>{};
  for (var i = 0; i < messages.length; i++) {
    lastById[messages[i].id] = i;
  }
  final seenIds = <String>{};
  for (var i = 0; i < messages.length; i++) {
    final id = messages[i].id;
    if (seenIds.contains(id) || lastById[id] != i) {
      removed.add(i);
      continue;
    }
    seenIds.add(id);
  }

  // Pass 2: assistant 同文本对（按文本签名分组）。
  final groups = <String, List<int>>{};
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    if (m.role != AiRole.assistant) continue;
    if (removed.contains(i)) continue;
    final signature = _textSignature(m);
    if (signature.isEmpty) continue;
    groups.putIfAbsent(signature, () => []).add(i);
  }
  for (final group in groups.values) {
    for (var a = 0; a < group.length; a++) {
      for (var b = a + 1; b < group.length; b++) {
        final ia = group[a];
        final ib = group[b];
        if (removed.contains(ia) || removed.contains(ib)) {
          continue;
        }
        final winner = _betterAssistant(messages[ia], messages[ib]);
        if (winner == 1) {
          removed.add(ib);
        } else if (winner == 2) {
          removed.add(ia);
        }
      }
    }
  }

  if (removed.isEmpty) {
    return AiHistoryDedupResult(messages: messages, removed: const []);
  }
  final out = <AiMessage>[
    for (var i = 0; i < messages.length; i++)
      if (!removed.contains(i)) messages[i],
  ];
  final dropped = <AiMessage>[
    for (var i = 0; i < messages.length; i++)
      if (removed.contains(i)) messages[i],
  ];
  return AiHistoryDedupResult(messages: out, removed: dropped);
}

/// 0 = 无法判定（都保留）; 1 = 保留 a; 2 = 保留 b。
int _betterAssistant(AiMessage a, AiMessage b) {
  final aResults = a.parts
      .whereType<AiToolCallPart>()
      .where((t) => t.result != null)
      .length;
  final bResults = b.parts
      .whereType<AiToolCallPart>()
      .where((t) => t.result != null)
      .length;
  if (aResults != bResults) {
    return aResults > bResults ? 1 : 2;
  }
  final aParts = _nonTextPartSet(a.parts);
  final bParts = _nonTextPartSet(b.parts);
  final aSubset = aParts.isNotEmpty && aParts.difference(bParts).isEmpty;
  final bSubset = bParts.isNotEmpty && bParts.difference(aParts).isEmpty;
  if (aSubset != bSubset) return aSubset ? 2 : 1;
  if (aSubset && aParts.length == bParts.length) return 1;
  return 0;
}

String _textSignature(AiMessage m) {
  final buffer = StringBuffer();
  for (final part in m.parts) {
    if (part is AiTextPart) {
      buffer.write(part.text);
      buffer.write('\u0000');
    }
  }
  return buffer.toString();
}

Set<String> _nonTextPartSet(List<AiMessagePart> parts) {
  final out = <String>{};
  for (final part in parts) {
    switch (part) {
      case AiReasoningPart(:final text):
        out.add('r:$text');
      case AiToolCallPart(:final toolCallId, :final toolName):
        out.add('t:$toolCallId:$toolName');
      default:
        break;
    }
  }
  return out;
}
