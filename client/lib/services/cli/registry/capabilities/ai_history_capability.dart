import 'package:ai_message_core/ai_message_core.dart';

import '../../../io/filesystem.dart';
import '../../../session/ai_history_page.dart';
import '../../../session/session_history_context.dart';
import '../cli_capability.dart';
import 'history/subagent_side_resolver.dart';
import 'history/tool_result_enricher.dart';

export '../../../session/ai_history_page.dart';

/// Optional paged source for transcript histories.
abstract interface class AiTranscriptPageReader {
  Future<AiHistoryPage?> readLatest({
    required SessionHistoryContext ctx,
    required int limit,
  });

  Future<AiHistoryPage?> readOlder({
    required SessionHistoryContext ctx,
    required AiHistoryCursor cursor,
    required int limit,
  });
}

/// 逐事件追加钩子:把一条已解码的 transcript 事件合并进 [messages]。
/// 返回该事件是否被解析消费(产生或修改了消息)。增量 tailer 只把"消费
/// 成功"的行推进锚点;无显示内容的事件(快照/元数据)返回 false。
typedef AiTranscriptLineAppend =
    bool Function(
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

/// How a CLI's native session id is bound to our session. See
/// `docs/session-resume-architecture.md`.
enum ResumeBinding {
  /// We choose the id and pin it at creation (`--session-id`); native id ==
  /// our taskId. claude (`projects/`), flashskyai (`workspaces/`).
  clientPinned,

  /// The CLI mints the id and stores it in its per-session-isolated store; we
  /// capture it on reopen. codex, opencode, cursor.
  postCaptured,
}

/// Everything a resume strategy needs to detect a native session id,
/// independent of team-vs-personal mode.
class ResumeContext {
  const ResumeContext({
    required this.fs,
    required this.toolValue,
    required this.taskId,
    required this.env,
    required this.transcriptRoots,
    required this.bucket,
    this.persistedNativeId,
    this.workspaceId,
    this.sessionId,
    this.memberId,
    this.teamId,
    this.manifestDataRoot,
  });

  final Filesystem fs;
  final String toolValue;

  /// Our session/member UUID — the id pinned for `clientPinned` CLIs.
  final String taskId;

  /// Resolved launch environment (holds `CODEX_HOME` / `OPENCODE_DB` /
  /// `CURSOR_CONFIG_DIR`, used to locate the per-session native store).
  final Map<String, String> env;

  /// claude-style transcript search roots (for `clientPinned` probing).
  /// Claude stores under `projects/`; flashskyai under `workspaces/`.
  final List<String> transcriptRoots;

  /// Workspace bucket derived from the working dir (claude transcript layout).
  final String bucket;

  /// The native id already recorded on the session-member binding, if any.
  final String? persistedNativeId;

  /// Optional session scope for lifecycle manifest resume (`chatId`).
  final String? workspaceId;
  final String? sessionId;
  final String? memberId;
  final String? teamId;

  /// Teampilot data root for [manifestDataRoot]-relative manifest paths.
  final String? manifestDataRoot;
}

abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;

  /// 逐事件追加钩子(增量解析与全量解析共用,保证语义零分叉)。
  /// Null 当该 CLI 的 transcript 无法增量解析(如 opencode 的 SQLite /
  /// JSON 树存储),loader 回退全量 [adapter].parse。
  AiTranscriptLineAppend? get lineAppend;

  /// Optional page source. Unsupported or unsafe sources return null so the
  /// loader can retain the adapter's full parse as its correctness fallback.
  AiTranscriptPageReader? get pageReader => null;

  /// Fallback id 前缀,必须与全量 adapter parse 的 `'$prefix-${seq}'` 一致
  /// (Claude→'claude',Codex→'codex',Cursor→'cursor',FlashskyAI→'flashskyai'),
  /// 保证增量与全量生成的消息 id 序列完全相同。
  String get tailFallbackPrefix;

  /// Lower-case names.
  Set<String> get subagentToolNames;
  SubagentSideResolver get subagentSideResolver;
  ToolResultEnricher get toolResultEnricher;

  /// Parent JSONL path used for cache tokens and tail warm-seed.
  ///
  /// Null → the loader falls back to the Claude/flashskyai pinned-transcript
  /// probe (`projects/` / `workspaces/`). Post-captured JSONL CLIs (Cursor,
  /// Codex) whose transcripts sit outside that layout must return the same
  /// path their [pageReader] / locate use.
  Future<String?> resolveParentTranscriptPath(SessionHistoryContext ctx) async =>
      null;

  /// Cheap live cache token for the loader's seat cache. Null → the loader
  /// falls back to its default path token ([resolveParentTranscriptPath] or
  /// the pinned-transcript probe). Implementers whose transcript lives outside
  /// a simple path|mtime|size fingerprint (e.g. OpenCode's SQLite store)
  /// return their own fingerprint so unchanged data skips the full locate +
  /// parse + subagent inflate on every live refresh.
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;

  /// 数据库行级增量刷新器(非 JSONL 存储,如 opencode SQLite)。默认 null:
  /// JSONL 存储的 CLI 不必覆盖,loader 走 tail 增量路径。
  AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

  /// Environment variables that must be set when building session history context.
  ///
  /// Each CLI derives the env it needs from the on-disk session CONFIG_DIR
  /// (resolved by the caller via [CliSessionCapability]) — the caller never
  /// special-cases a CLI identity.
  Map<String, String> sessionEnv({String? toolRoot});

  /// Whether/how this CLI pins its native session id.
  ResumeBinding get binding;

  /// Resolve the native id of an existing resumable session, or `null` when
  /// none exists yet. `clientPinned` probes the transcript file by our id;
  /// `postCaptured` scans the CLI's per-session-isolated store.
  Future<String?> detectNativeId(ResumeContext ctx);

  AiEditToolTargetResolver get editResolver;
  AiToolFileTargetResolver get fileResolver;
  AiShellToolTargetResolver get shellResolver;
  AiToolCallCategoryResolver get categoryResolver;
}
