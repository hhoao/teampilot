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

/// 数据库行级增量刷新结果:合并后的消息列表 + 可供子代理附件膨胀使用的
/// 父 transcript 路径(通常为 DB 路径)。
typedef AiTranscriptIncrementalResult = ({
  List<AiMessage> messages,
  String? parentPath,
});

/// 增量状态:由 loader 按 cache key 持有,刷新器在其中维护锚点与实时列表。
abstract class AiTranscriptIncrementalState {
  List<AiMessage> get messages;
}

/// 非 JSONL 存储(如 opencode SQLite)的行级增量刷新器。
///
/// loader 在每次 load 时先尝试 [refresh](在 store 级 token 判定数据已动
/// 之后):刷新器只读"新增/变更"的行并**原地**合并进
/// [AiTranscriptIncrementalState.messages](列表实例不变,保住下游
/// `identical` 快速路径)。返回 null 表示本次无法增量(计数回退/删除/压缩/
/// schema 不支持),loader 回退全量 locate + parse;全量 parse 完成后 loader
/// 调用 [seedFromFullParse] 让增量状态与全量结果对齐,使下一次 refresh
/// 成为纯增量。
abstract interface class AiTranscriptIncrementalRefresher {
  AiTranscriptIncrementalState createState();

  /// 全量 parse 完成后的对齐钩子:记录指纹、采用 [messages] 列表实例。
  /// 默认无操作(不需要对齐的实现直接跳过)。
  Future<void> seedFromFullParse({
    required SessionHistoryContext ctx,
    required List<AiMessage> messages,
    required AiTranscriptIncrementalState state,
  }) async {}

  /// 增量刷新。返回 null → 回退全量。
  Future<AiTranscriptIncrementalResult?> refresh({
    required SessionHistoryContext ctx,
    required AiTranscriptIncrementalState state,
    bool force = false,
  });
}

/// 持有数据库行级增量刷新器的能力标记,与 [AiHistoryCapability] 一起实现。
/// 独立接口而非 AiHistoryCapability 成员:不强制其它 CLI(JSONL 存储)
/// 实现。
abstract interface class AiTranscriptIncrementalCapability {
  AiTranscriptIncrementalRefresher get incrementalRefresher;
}

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
