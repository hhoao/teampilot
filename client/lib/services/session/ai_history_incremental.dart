import 'package:ai_message_core/ai_message_core.dart';

import '../ai_history/tool_call_category_annotator.dart';

/// Returns the length of the shared identical prefix of [previous] and [next].
int identicalPrefixLength(List<AiMessage> previous, List<AiMessage> next) {
  final n = previous.length < next.length ? previous.length : next.length;
  for (var i = 0; i < n; i++) {
    if (!identical(previous[i], next[i])) return i;
  }
  return n;
}

/// Annotates only the suffix of [next] that is not identical to [previous].
///
/// Compact / rewrite / shrink ([next] shorter than [previous], or no previous)
/// falls back to a full [annotateToolCallCategories].
List<AiMessage> annotateChangedSuffix({
  required List<AiMessage>? previous,
  required List<AiMessage> next,
  required AiToolCallCategoryResolver resolver,
}) {
  if (previous == null || next.length < previous.length) {
    return annotateToolCallCategories(next, resolver: resolver);
  }
  final start = identicalPrefixLength(previous, next);
  if (start == 0) {
    return annotateToolCallCategories(next, resolver: resolver);
  }
  if (start == next.length) return next;
  return [
    ...next.sublist(0, start),
    ...annotateToolCallCategories(next.sublist(start), resolver: resolver),
  ];
}

/// 截断的 part 内容签名:状态 + 错误标志 + 结果(长度分量 + 头 64 字符)
/// + 子 agent id。结果不整串拼接,签名构建 O(1),避免大 tool result 每
/// tick 全量字符串化;长度分量捕获流式追加/截断,头分量捕获同长替换。
///
/// 子 agent id 分量覆盖 Codex 等「先出现 spawn 工具、后经 SubAgentActivity
/// 绑定 thread id」的路径:仅结果签名不变时也必须触发重新 inflate,否则
/// 会一直复用 degrade 附件。
///
/// 状态按 [finalizeAiMessagesForHistory] 语义归一:未配对调用(结果为空)
/// 在全量 parse 后被归一为 incomplete,而增量 tail 直接 append 时仍保持
/// 默认的 complete——归一后同一条调用在两条路径上的签名才可比,否则
/// 每次 tail 增量都会被误判为"调用变了"而白白重 inflate。
String taskCallSignature(AiToolCallPart part) {
  final result = part.result;
  final raw = result is String ? result : (result?.toString() ?? '');
  final head = raw.length > 64 ? '${raw.length}:${raw.substring(0, 64)}' : raw;
  final status = part.status;
  final normalizedStatus =
      (result == null &&
          (status == AiToolCallStatus.running ||
              (status == AiToolCallStatus.complete && !part.isError)))
      ? AiToolCallStatus.incomplete
      : status;
  final agentId = subagentAgentIdFromPart(part) ?? '';
  return '${normalizedStatus.name}|${part.isError}|$head|$agentId';
}

/// Collects subagent tool-call signatures from [messages], starting at [from].
Map<String, String> collectTaskCallSignatures(
  List<AiMessage> messages,
  Set<String> subagentToolNames, {
  int from = 0,
}) {
  final out = <String, String>{};
  for (var i = from; i < messages.length; i++) {
    for (final part in messages[i].parts) {
      if (part is! AiToolCallPart) continue;
      if (!subagentToolNames.contains(part.toolName.trim().toLowerCase())) {
        continue;
      }
      final id = part.toolCallId.trim();
      if (id.isEmpty) continue;
      out[id] = taskCallSignature(part);
    }
  }
  return out;
}

/// Drops suffix ids from [previousSigs] then unions the next suffix.
Map<String, String> updateTaskCallSignatures({
  required Map<String, String> previousSigs,
  required List<AiMessage> previousMessages,
  required List<AiMessage> nextMessages,
  required int suffixStart,
  required Set<String> subagentToolNames,
}) {
  final out = Map<String, String>.of(previousSigs);
  for (final id in collectTaskCallSignatures(
    previousMessages,
    subagentToolNames,
    from: suffixStart,
  ).keys) {
    out.remove(id);
  }
  out.addAll(
    collectTaskCallSignatures(
      nextMessages,
      subagentToolNames,
      from: suffixStart,
    ),
  );
  return out;
}

/// 任务调用签名快照与当前签名是否一致。
bool sameTaskSignatures(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
