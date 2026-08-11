import 'package:ai_message_core/ai_message_core.dart';

import '../../../session/session_history_context.dart';
import '../cli_capability.dart';
import 'history/subagent_side_resolver.dart';
import 'history/tool_result_enricher.dart';

/// 逐事件追加钩子:把一条已解码的 transcript 事件合并进 [messages]。
/// 返回该事件是否被解析消费(产生或修改了消息)。增量 tailer 只把"消费
/// 成功"的行推进锚点;无显示内容的事件(快照/元数据)返回 false。
typedef AiTranscriptLineAppend = bool Function(
  List<AiMessage> messages,
  Map<String, dynamic> event, {
  required String Function() fallbackId,
});

abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;
  /// 逐事件追加钩子(增量解析与全量解析共用,保证语义零分叉)。
  /// Null 当该 CLI 的 transcript 无法增量解析(如 opencode 的 SQLite /
  /// JSON 树存储),loader 回退全量 [adapter].parse。
  AiTranscriptLineAppend? get lineAppend;

  /// Fallback id 前缀,必须与全量 adapter parse 的 `'$prefix-${seq}'` 一致
  /// (Claude→'claude',Codex→'codex',Cursor→'cursor',FlashskyAI→'flashskyai'),
  /// 保证增量与全量生成的消息 id 序列完全相同。
  String get tailFallbackPrefix;

  /// Lower-case names.
  Set<String> get subagentToolNames;
  SubagentSideResolver get subagentSideResolver;
  ToolResultEnricher get toolResultEnricher;

  /// Cheap live cache token for the loader's seat cache. Null → the loader
  /// falls back to its default pinned-transcript probe. Implementers whose
  /// transcript lives outside the probed JSONL layout (e.g. OpenCode's
  /// SQLite store) return their own fingerprint so unchanged data skips the
  /// full locate + parse + subagent inflate on every live refresh.
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
}
