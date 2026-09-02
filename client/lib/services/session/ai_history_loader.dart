import 'dart:isolate';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';

import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../models/workspace_launch_context.dart';
import '../../utils/logging/logger.dart';
import '../ai_history/tool_call_categories.dart';
import '../ai_history/tool_call_category_annotator.dart';
import '../cli/preset_resolver.dart';
import '../cli/registry/capabilities/ai_history_capability.dart';
import '../cli/registry/capabilities/history/tool_result_enricher.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../storage/runtime_context.dart';
import '../terminal/session_member_cli_resolver.dart';
import 'ai_history_cache_token.dart';
import 'ai_history_incremental.dart';
import 'ai_history_load_result.dart';
import 'ai_history_load_timings.dart';
import 'ai_history_locator.dart';
import 'ai_history_page.dart';
import 'ai_history_watch_meta.dart';
import 'ai_transcript_tail_reader.dart';
import 'jsonl_decode_worker.dart';
import 'session_history_context.dart';
import 'session_history_context_builder.dart';
import 'session_history_pagination.dart';
import 'subagent_attachment_inflater.dart';

/// Resolves the work-plane [RuntimeContext] for a History seat (same seam as
/// [SessionLifecycleService.launchWorkContext]).
typedef AiHistoryWorkContextResolver =
    Future<RuntimeContext> Function(
      WorkspaceLaunchContext ctx, {
      String? memberId,
    });

class _AiHistorySeat {
  const _AiHistorySeat({
    required this.cli,
    required this.effectiveMemberId,
    required this.ctx,
  });

  final CliTool cli;
  final String effectiveMemberId;
  final SessionHistoryContext ctx;
}

/// Resolves seat CLI → locate bundle → [AiTranscriptAdapter] parse → messages,
/// with sessionId+memberId(+mtime) caching.
final class AiHistoryLoader {
  AiHistoryLoader({
    SessionHistoryContextBuilder contextBuilder =
        const SessionHistoryContextBuilder(),
    required AiHistoryWorkContextResolver resolveWorkContext,
    CliToolRegistry? registry,
    AiHistoryLocator? locator,
    SessionHistoryCacheTokenResolver? resolveCacheToken,
    List<CliPreset> Function()? globalPresets,
    AiHistoryLoadTimings? timings,
  }) : _contextBuilder = contextBuilder,
       _resolveWorkContext = resolveWorkContext,
       _registry = registry ?? CliToolRegistry.builtIn(),
       _locator =
           locator ??
           AiHistoryLocator(registry: registry ?? CliToolRegistry.builtIn()),
       _resolveCacheToken = resolveCacheToken,
       _globalPresets = globalPresets,
       _timings = timings;

  final SessionHistoryContextBuilder _contextBuilder;
  final AiHistoryWorkContextResolver _resolveWorkContext;
  final CliToolRegistry _registry;
  final AiHistoryLocator _locator;
  final SessionHistoryCacheTokenResolver? _resolveCacheToken;
  final List<CliPreset> Function()? _globalPresets;
  final AiHistoryLoadTimings? _timings;

  /// Per-seat cache: resolver token → messages → attachments.
  final _tokens = <String, String>{};
  final _messages = <String, List<AiMessage>>{};
  final _attachments = <String, Map<String, AiSubagentAttachment>>{};

  /// Per-seat 任务调用签名快照(cacheKey → toolCallId → 签名),与
  /// [_messages] 解耦:DB 行级增量会原地变异 seat 消息列表实例,无法用
  /// "上次的消息列表"做增量前后比较,只能用"上次 inflate 时的签名"。
  final _attachmentSigs = <String, Map<String, String>>{};

  /// Per-seat located parent transcript path (for side fingerprinting) and
  /// last-observed side-transcript fingerprint.
  final _parentPaths = <String, String>{};
  final _sideTokens = <String, String>{};

  /// Incremental tail state (cacheKey → state) and per-CLI tail readers. The
  /// state owns the live [List] that [load] hands out; the reader is stateless
  /// per CLI (all mutable state lives in [TailReaderState]).
  final _tailStates = <String, TailReaderState>{};
  final _tailReaders = <String, AiTranscriptTailReader>{};

  /// DB 行级增量状态(cacheKey → state,如 opencode SQLite)。与 tail 状态
  /// 互斥:JSONL CLI 用 [AiTranscriptLineAppend],SQLite CLI 用
  /// [AiTranscriptIncrementalRefresher]。
  final _incrementalStates = <String, AiTranscriptIncrementalState>{};

  /// 在途 load 单飞表(cacheKey → future):并发触发合并,见 [load]。
  final _inflightLoads = <String, Future<AiHistoryLoadResult>>{};

  /// Per-seat lazy subagent attachment loads (cacheKey+toolCallId → future).
  final _inflightSubagentLoads =
      <String, Future<AiSubagentAttachment?>>{};

  /// Bumped when a seat's lazy attachment cache is cleared (side fingerprint).
  final _subagentSeatGenerations = <String, int>{};

  /// Bumped when signature prune drops one tool-call id.
  final _subagentIdGenerations = <String, int>{};

  /// Lazy, single-flight subagent attachment resolution for one [toolCallId].
  Future<AiSubagentAttachment?> loadSubagentAttachment({
    required String cacheKey,
    required String toolCallId,
    required SessionHistoryContext ctx,
    required AiHistoryCapability capability,
    required List<AiMessage> messages,
    required CliTool cli,
  }) async {
    final id = toolCallId.trim();
    if (id.isEmpty) return null;

    final cached = _attachments[cacheKey]?[id];
    if (cached != null) return cached;

    final inflightKey = '$cacheKey\u0000$id';
    final inFlight = _inflightSubagentLoads[inflightKey];
    if (inFlight != null) return inFlight;

    final future = _loadSubagentAttachmentOnce(
      cacheKey: cacheKey,
      toolCallId: id,
      ctx: ctx,
      capability: capability,
      messages: messages,
      cli: cli,
    );
    _inflightSubagentLoads[inflightKey] = future;
    future.whenComplete(() {
      if (identical(_inflightSubagentLoads[inflightKey], future)) {
        _inflightSubagentLoads.remove(inflightKey);
      }
    }).ignore();
    return future;
  }

  Future<AiSubagentAttachment?> _loadSubagentAttachmentOnce({
    required String cacheKey,
    required String toolCallId,
    required SessionHistoryContext ctx,
    required AiHistoryCapability capability,
    required List<AiMessage> messages,
    required CliTool cli,
  }) async {
    final seatGen = _subagentSeatGeneration(cacheKey);
    final idGen = _subagentIdGeneration(cacheKey, toolCallId);
    final rootTranscriptPath = _parentPaths[cacheKey];
    final path = rootTranscriptPath?.trim().isEmpty ?? true
        ? null
        : rootTranscriptPath;
    var attachment = await const SubagentAttachmentInflater().resolveByToolCallId(
      toolCallId: toolCallId,
      messages: messages,
      ctx: ctx,
      capability: capability,
      rootTranscriptPath: path,
    );
    _timings?.addSideTranscriptRead();
    if (_subagentSeatGeneration(cacheKey) != seatGen ||
        _subagentIdGeneration(cacheKey, toolCallId) != idGen) {
      return null;
    }
    if (attachment == null) return null;

    final annotated = annotateSubagentAttachments(
      {toolCallId: attachment},
      resolver: _categoryResolverFor(cli),
    );
    attachment = annotated[toolCallId] ?? attachment;

    if (_subagentSeatGeneration(cacheKey) != seatGen ||
        _subagentIdGeneration(cacheKey, toolCallId) != idGen) {
      return null;
    }

    final cache = _attachments.putIfAbsent(cacheKey, () => {});
    cache[toolCallId] = attachment;
    if (attachment.workflow != null) {
      SubagentAttachmentInflater.addWorkflowChildren(attachment, cache);
    }
    return attachment;
  }

  int _subagentSeatGeneration(String cacheKey) =>
      _subagentSeatGenerations[cacheKey] ?? 0;

  int _subagentIdGeneration(String cacheKey, String toolCallId) =>
      _subagentIdGenerations['$cacheKey\u0000$toolCallId'] ?? 0;

  void _invalidateSubagentLoadsForSeat(String cacheKey) {
    _subagentSeatGenerations[cacheKey] = _subagentSeatGeneration(cacheKey) + 1;
    _inflightSubagentLoads.removeWhere((k, _) => k.startsWith('$cacheKey\u0000'));
  }

  void _invalidateSubagentLoadForId(String cacheKey, String toolCallId) {
    final inflightKey = '$cacheKey\u0000$toolCallId';
    _subagentIdGenerations[inflightKey] =
        _subagentIdGeneration(cacheKey, toolCallId) + 1;
    _inflightSubagentLoads.remove(inflightKey);
  }

  /// Seat-scoped cache key for [loadSubagentAttachment] callers.
  static String cacheKeyFor(String sessionId, String memberId) =>
      _cacheKey(sessionId, memberId);

  /// Resolves one subagent attachment using the seat's work-plane context.
  Future<AiSubagentAttachment?> loadSubagentAttachmentForSeat({
    required AppSession session,
    required String memberId,
    required WorkspaceLaunchContext launchContext,
    required String toolCallId,
    required List<AiMessage> messages,
    TeamProfile? team,
    String? workingDirectory,
  }) async {
    final seat = await _resolveSeat(
      launchContext: launchContext,
      memberId: memberId,
      team: team,
      workingDirectory: workingDirectory,
    );
    final cap = _registry.capability<AiHistoryCapability>(seat.cli);
    if (cap == null) return null;
    return loadSubagentAttachment(
      cacheKey: _cacheKey(session.sessionId, seat.effectiveMemberId),
      toolCallId: toolCallId,
      ctx: seat.ctx,
      capability: cap,
      messages: messages,
      cli: seat.cli,
    );
  }

  /// Puts [attachment] into the seat's lazy attachment cache (e.g. restore a
  /// prior preview after a forced refresh degraded to a tool-result stub).
  Future<void> seedSubagentAttachmentForSeat({
    required AppSession session,
    required String memberId,
    required WorkspaceLaunchContext launchContext,
    required String toolCallId,
    required AiSubagentAttachment attachment,
    TeamProfile? team,
    String? workingDirectory,
  }) async {
    final seat = await _resolveSeat(
      launchContext: launchContext,
      memberId: memberId,
      team: team,
      workingDirectory: workingDirectory,
    );
    final cache = _attachments.putIfAbsent(
      _cacheKey(session.sessionId, seat.effectiveMemberId),
      () => {},
    );
    cache[toolCallId] = attachment;
    if (attachment.workflow != null) {
      SubagentAttachmentInflater.addWorkflowChildren(attachment, cache);
    }
  }
  final _hasOlder = <String, bool>{};
  final _cursors = <String, AiHistoryCursor?>{};
  final _complete = <String, bool>{};
  final _pageContexts = <String, SessionHistoryContext>{};
  final _pageClis = <String, CliTool>{};

  /// Background full-index futures and completed results (search / task board).
  final _fullIndexFutures = <String, Future<AiHistoryLoadResult>>{};
  final _fullIndexes = <String, AiHistoryLoadResult>{};

  /// Bundles at/above this size parse on a worker isolate; smaller ones parse
  /// in place (isolate spawn + transfer overhead would dominate).
  static const _isolateParseMinBytes = 256 * 1024;

  /// Switch to disable worker-isolate parsing of heavy transcripts (everything
  /// then parses on the caller / UI isolate). Debug builds already skip
  /// isolate parse — see `_parseAndEnrich` (`kDebugMode` guard).
  static bool enableIsolateParse = true;

  /// Work-plane context for the seat (live refresh binds this FS).
  Future<RuntimeContext> resolveSeatRuntime({
    required WorkspaceLaunchContext launchContext,
    required String memberId,
  }) {
    final mid = memberId.trim();
    return _resolveWorkContext(
      launchContext,
      memberId: mid.isEmpty ? null : mid,
    );
  }

  /// Clears all seats (v1 work-plane evict).
  void clearCache() {
    _tokens.clear();
    _messages.clear();
    _attachments.clear();
    _attachmentSigs.clear();
    _parentPaths.clear();
    _sideTokens.clear();
    _tailStates.clear();
    _incrementalStates.clear();
    _inflightLoads.clear();
    _inflightSubagentLoads.clear();
    _subagentSeatGenerations.clear();
    _subagentIdGenerations.clear();
    _hasOlder.clear();
    _cursors.clear();
    _complete.clear();
    _pageContexts.clear();
    _pageClis.clear();
    _fullIndexFutures.clear();
    _fullIndexes.clear();
    _invalidateToolResultIndexes(all: true);
  }

  /// Cached seat messages when [token] still matches the last successful load.
  List<AiMessage>? messagesIfCached({
    required String sessionId,
    required String memberId,
    required String token,
  }) {
    final key = _cacheKey(sessionId, memberId);
    if (_tokens[key] != token) return null;
    return _fullIndexes[key]?.messages;
  }

  /// Per-CLI tail reader for JSONL-style transcripts. Returns null when the
  /// capability has no [AiTranscriptLineAppend] (e.g. opencode's multi-file DB)
  /// so the loader falls back to the full adapter parse.
  AiTranscriptTailReader? _tailReaderFor(CliTool cli) {
    final history = _registry.capability<AiHistoryCapability>(cli);
    final lineAppend = history?.lineAppend;
    if (lineAppend == null) return null;
    return _tailReaders.putIfAbsent(
      cli.name,
      () => AiTranscriptTailReader(
        lineAppend: lineAppend,
        fallbackPrefix: history!.tailFallbackPrefix,
        decodeEvents: _decodeEvents,
      ),
    );
  }

  /// Incremental path: locate → parent path → tail refresh on the state's
  /// in-place list. Returns null when unavailable (no parent path / no
  /// lineAppend) so [load] falls back to the full adapter parse.
  Future<List<AiMessage>?> _tryIncrementalLoad({
    required String cacheKey,
    required CliTool cli,
    required SessionHistoryContext ctx,
    required String? parentPath,
  }) async {
    if (parentPath == null || parentPath.isEmpty) return null;
    final reader = _tailReaderFor(cli);
    if (reader == null) return null;
    final state = _tailStates.putIfAbsent(cacheKey, TailReaderState.new);
    await reader.refresh(
      fs: ctx.fs,
      path: parentPath,
      state: state,
    );
    return state.messages;
  }

  /// DB 行级增量路径:刷新器只重读指纹变化的行并原地合并进 state 的实时
  /// 列表。返回 null 时 [load] 回退全量 locate + parse。
  Future<AiTranscriptIncrementalResult?> _tryIncrementalRefresh({
    required String cacheKey,
    required CliTool cli,
    required SessionHistoryContext ctx,
  }) async {
    final cap = _registry.capability<AiHistoryCapability>(cli);
    final refresher = cap?.incrementalRefresher;
    if (refresher == null) return null;
    // After the first parse, a warm incremental cursor must keep going even
    // when the caller asked for force (force only skips the mtime token cache).
    final state = _incrementalStates[cacheKey];
    if (state == null) return null;
    return refresher.refresh(ctx: ctx, state: state, force: false);
  }

  /// 增量路径(JSONL tail / DB 行级)共用的收尾:注解、附件膨胀、缓存落库。
  /// 未变化的原始消息保持实例身份,列表实例保持不变(下游 `identical`
  /// 快速路径)。
  Future<AiHistoryLoadResult> _finishIncremental({
    required String cacheKey,
    required CliTool cli,
    required SessionHistoryContext ctx,
    required List<AiMessage> messages,
    required String? parentPath,
    required String? token,
    bool indexOnly = false,
  }) async {
    // Incrementally added/replaced parts are unannotated → annotate now
    // (idempotent on parts the previous load already covered).
    final previous = _messages[cacheKey];
    final annotated = annotateChangedSuffix(
      previous: previous,
      next: messages,
      resolver: _categoryResolverFor(cli),
    );
    // 附件索引按需重建:任务调用集合(签名)与 side 数据都没有变化时复用
    // 缓存 map 本身——seat 的 identical 比较直接跳过,UI isolate 零字符串
    // 构建;新任务调用出现 / 调用完成(结果落库) / 运行中子 agent 的 side
    // 数据移动时才重新 inflate(resolver 内部 memo 保证未变化的子会话返回
    // 相同实例,重建代价被限制在真正变化的内容上)。
    final capability = _registry.capability<AiHistoryCapability>(cli);
    Map<String, String>? suffixSigs;
    if (capability != null) {
      final names = capability.subagentToolNames;
      if (previous == null || messages.length < previous.length) {
        suffixSigs = collectTaskCallSignatures(annotated, names);
      } else {
        suffixSigs = updateTaskCallSignatures(
          previousSigs: _attachmentSigs[cacheKey] ?? const {},
          previousMessages: previous,
          nextMessages: annotated,
          suffixStart: identicalPrefixLength(previous, messages),
          subagentToolNames: names,
        );
      }
    }
    final attachments = await _subagentAttachmentsFor(
      cacheKey: cacheKey,
      cli: cli,
      ctx: ctx,
      messages: annotated,
      rootTranscriptPath: parentPath,
      cache: !indexOnly,
      currentSigs: suffixSigs,
    );
    // 增量路径原地变异 state 的实时列表,annotate 无改动时返回的仍是
    // 同一个实例——seat 用 identical 判定"CLI 未变化"会把这个实例当成
    // 没变而跳过,页面永远不出现增量消息。必须包装成新实例(内部消息
    // 实例不变,附件/下游 identical 快速路径不受影响),且缓存里存的必须
    // 是同一个返回实例,否则缓存命中路径返回的实例与上次返回值不同,
    // seat 会误判"变了"。
    final result = List<AiMessage>.of(annotated);
    final complete = AiHistoryLoadResult(
      messages: result,
      cli: cli,
      subagentAttachments: attachments,
      isComplete: true,
    );
    _fullIndexes[cacheKey] = complete;
    _fullIndexFutures[cacheKey] = Future.value(complete);
    if (indexOnly) return complete;
    _messages[cacheKey] = result;
    _attachments[cacheKey] = attachments;
    _tokens[cacheKey] = token ?? 'changed-$cacheKey';
    _markComplete(cacheKey);
    return complete;
  }

  /// 增量路径的附件索引刷新。
  ///
  /// 首屏与增量 tick 只维护任务调用签名与 side 指纹,不 eager inflate。
  /// 已 lazy-load 的条目在签名/side 未变时复用;变化时按 id 失效。
  Future<Map<String, AiSubagentAttachment>> _subagentAttachmentsFor({
    required String cacheKey,
    required CliTool cli,
    required SessionHistoryContext ctx,
    required List<AiMessage> messages,
    required String? rootTranscriptPath,
    bool cache = true,
    Map<String, String>? currentSigs,
  }) async {
    final capability = _registry.capability<AiHistoryCapability>(cli);
    if (capability == null) return const {};
    final sigs =
        currentSigs ??
        collectTaskCallSignatures(messages, capability.subagentToolNames);
    if (cache) {
      final prevSigs = _attachmentSigs[cacheKey];
      if (prevSigs != null) {
        _pruneAttachmentsForSignatureChanges(
          cacheKey: cacheKey,
          prevSigs: prevSigs,
          currentSigs: sigs,
        );
      }
      final sideToken = await capability.subagentSideResolver.fingerprint(
        ctx: ctx,
        rootTranscriptPath: rootTranscriptPath,
      );
      if (sideToken != null &&
          _sideTokens[cacheKey] != null &&
          _sideTokens[cacheKey] != sideToken) {
        _attachments[cacheKey]?.clear();
        _invalidateSubagentLoadsForSeat(cacheKey);
      }
      if (sideToken != null) _sideTokens[cacheKey] = sideToken;
      _attachmentSigs[cacheKey] = sigs;
    }
    if (cache) {
      return _attachments.putIfAbsent(cacheKey, () => {});
    }
    return const {};
  }

  void _pruneAttachmentsForSignatureChanges({
    required String cacheKey,
    required Map<String, String> prevSigs,
    required Map<String, String> currentSigs,
  }) {
    if (sameTaskSignatures(prevSigs, currentSigs)) return;
    final attachments = _attachments[cacheKey];
    if (attachments == null || attachments.isEmpty) return;
    for (final entry in prevSigs.entries) {
      if (currentSigs[entry.key] != entry.value) {
        attachments.remove(entry.key);
        _invalidateSubagentLoadForId(cacheKey, entry.key);
      }
    }
  }

  AiToolCallCategoryResolver _categoryResolverFor(CliTool cli) =>
      _registry.capability<AiHistoryCapability>(cli)?.categoryResolver ??
      defaultToolCallCategoryResolver;

  /// Defensive annotation for post-load merged lists (mailbox). Idempotent.
  List<AiMessage> annotate(List<AiMessage> messages, {required CliTool cli}) =>
      annotateToolCallCategories(messages, resolver: _categoryResolverFor(cli));

  /// Locate-only watch hints for live transcript refresh (no full parse).
  Future<AiHistoryWatchMeta?> resolveWatchMeta({
    required WorkspaceLaunchContext launchContext,
    required String memberId,
    TeamProfile? team,
    String? workingDirectory,
  }) async {
    final seat = await _resolveSeat(
      launchContext: launchContext,
      memberId: memberId,
      team: team,
      workingDirectory: workingDirectory,
    );
    final bundle = await _locator.locate(ctx: seat.ctx, cli: seat.cli);
    if (bundle == null) return null;
    return AiHistoryWatchMeta.fromHints(bundle.hints);
  }

  Future<AiHistoryLoadResult> load({
    required AppSession session,
    required String memberId,
    required WorkspaceLaunchContext launchContext,
    TeamProfile? team,
    String? workingDirectory,
    bool force = false,
  }) async {
    final seat = await _resolveSeat(
      launchContext: launchContext,
      memberId: memberId,
      team: team,
      workingDirectory: workingDirectory,
    );
    final cli = seat.cli;
    final effectiveMemberId = seat.effectiveMemberId;
    final ctx = seat.ctx;
    final cacheKey = _cacheKey(session.sessionId, effectiveMemberId);

    // 单飞:同一 seat 的并发 load(变化信号 / stale 信号 / refreshNow 三路
    // 触发互相不互斥)合并为一个在途 Future,不重复起跑重量级查询链——
    // 否则多条链同时存活会同时存在多个 worker isolate。force 请求绕过
    // 合并,保证显式刷新必然起一轮新周期。
    final inFlight = _inflightLoads[cacheKey];
    if (inFlight != null && !force) return inFlight;

    final future = _loadOnce(
      session: session,
      cli: cli,
      effectiveMemberId: effectiveMemberId,
      ctx: ctx,
      cacheKey: cacheKey,
      force: force,
    );
    _inflightLoads[cacheKey] = future;
    future.whenComplete(() {
      if (identical(_inflightLoads[cacheKey], future)) {
        _inflightLoads.remove(cacheKey);
      }
    }).ignore();
    return future;
  }

  Future<AiHistoryLoadResult> _loadOnce({
    required AppSession session,
    required CliTool cli,
    required String effectiveMemberId,
    required SessionHistoryContext ctx,
    required String cacheKey,
    required bool force,
    bool skipPaging = false,
  }) async {
    final cap = _registry.capability<AiHistoryCapability>(cli);
    if (cap == null) {
      appLogger.e(
        '[ai-history] AiHistoryCapability missing for CLI $cli '
        'session=${session.sessionId}',
      );
      throw StateError('AiHistoryCapability missing for launch CLI $cli');
    }

    final token = await (_resolveCacheToken ?? _defaultTokenResolverFor(cap))(
      ctx,
    );
    if (!force && token != null && _tokens[cacheKey] == token) {
      final full = _fullIndexes[cacheKey];
      final cachedMessages = full?.messages ?? _messages[cacheKey] ?? const [];
      final cachedAttachments =
          full?.subagentAttachments ?? _attachments[cacheKey] ?? const {};
      // Parent transcript unchanged. While a sub-agent is still running its
      // side transcript appends lines but the parent transcript only moves
      // when the tool result lands — so the parent cache token cannot see it.
      // Re-inflate attachments from the cached messages when the side data
      // fingerprint moved (skip when the CLI layout cannot fingerprint).
      final sideToken = await cap.subagentSideResolver.fingerprint(
        ctx: ctx,
        rootTranscriptPath: _parentPaths[cacheKey],
      );
      if (sideToken == null || _sideTokens[cacheKey] == sideToken) {
        final liveAttachments = _attachments[cacheKey];
        if (full != null) {
          if (full.subagentAttachments.isEmpty &&
              liveAttachments != null &&
              liveAttachments.isNotEmpty) {
            return AiHistoryLoadResult(
              messages: full.messages,
              cli: full.cli,
              subagentAttachments: liveAttachments,
              hasOlder: full.hasOlder,
              cursor: full.cursor,
              isComplete: full.isComplete,
            );
          }
          return full;
        }
        return _result(
          cacheKey: cacheKey,
          messages: cachedMessages,
          cli: cli,
          subagentAttachments: cachedAttachments,
        );
      }
      _attachments[cacheKey]?.clear();
      _invalidateSubagentLoadsForSeat(cacheKey);
      _sideTokens[cacheKey] = sideToken;
      // Keep the full-index entry on the live attachments map so later token
      // hits observe lazy rematerializations instead of a baked-in empty map.
      final liveAttachments = _attachments.putIfAbsent(cacheKey, () => {});
      if (full != null) {
        final indexed = AiHistoryLoadResult(
          messages: cachedMessages,
          cli: cli,
          subagentAttachments: liveAttachments,
          isComplete: true,
        );
        _fullIndexes[cacheKey] = indexed;
        _fullIndexFutures[cacheKey] = Future.value(indexed);
        return AiHistoryLoadResult(
          messages: cachedMessages,
          cli: cli,
          subagentAttachments: const {},
          isComplete: true,
          subagentSideIndexDirty: true,
        );
      }
      return _result(
        cacheKey: cacheKey,
        messages: cachedMessages,
        cli: cli,
        subagentAttachments: const {},
        subagentSideIndexDirty: true,
      );
    }

    try {
      // Page-first until incremental/tail state is warm. Do not treat the
      // published window (`_messages`) as a reason to skip: a later token
      // change must re-read the latest page instead of falling through to a
      // full locate/parse while the background index is still running.
      if (!skipPaging && !_hasWarmIncremental(cacheKey)) {
        final paged = await _tryPageFirst(
          session: session,
          cacheKey: cacheKey,
          cli: cli,
          cap: cap,
          ctx: ctx,
          token: token,
          effectiveMemberId: effectiveMemberId,
        );
        if (paged != null && !_hasWarmIncremental(cacheKey)) return paged;
      }

      // 增量优先:数据库行级增量(如 opencode SQLite)——跳过全量 locate +
      // 全量 parse,只重读指纹变化的行并原地合并。不可增量(未对齐/计数
      // 回退/删除/压缩/schema 不兼容)返回 null,继续走全量路径。
      final dbDelta = await _tryIncrementalRefresh(
        cacheKey: cacheKey,
        cli: cli,
        ctx: ctx,
      );
      if (dbDelta != null) {
        final parentPath = dbDelta.parentPath;
        if (parentPath != null) _parentPaths[cacheKey] = parentPath;
        return _finishIncremental(
          cacheKey: cacheKey,
          cli: cli,
          ctx: ctx,
          messages: dbDelta.messages,
          parentPath: parentPath,
          token: token,
          indexOnly: skipPaging,
        );
      }

      final bundle = await _timed(
        AiHistoryLoadPhase.locate,
        () => _locator.locate(ctx: ctx, cli: cli),
      );
      final watch = bundle == null
          ? null
          : AiHistoryWatchMeta.fromHints(bundle.hints);
      final parentPath = () {
        final paths = watch?.cacheTokenPaths ?? const <String>[];
        for (final p in paths) {
          final t = p.trim();
          if (t.isNotEmpty) return t;
        }
        return null; // degrade-only; never invent a path from fragment basename
      }();
      _parentPaths[cacheKey] = parentPath ?? '';

      // JSONL 类 CLI 走 tail-anchor 增量(原地变异复用消息实例);
      // 失败/不适配(无 path、无 lineAppend、非 JSONL 存储)回退全量 parse。
      final tail = await _tryIncrementalLoad(
        cacheKey: cacheKey,
        cli: cli,
        ctx: ctx,
        parentPath: parentPath,
      );
      if (tail != null) {
        return _finishIncremental(
          cacheKey: cacheKey,
          cli: cli,
          ctx: ctx,
          messages: tail,
          parentPath: parentPath,
          token: token,
          indexOnly: skipPaging,
        );
      }

      // Full parse through the capability's adapter: reads the whole located
      // transcript each time. The mtime token above skips the work when nothing
      // changed.
      //
      // Heavy transcripts parse on a worker isolate so the UI thread never
      // spends tens of ms re-decoding a large JSONL on live refresh. Isolate
      // spawn + transfer have a fixed ~ms cost, so small bundles parse in place
      // where the overhead would dominate.
      //
      // Bundle-only enrichers (no filesystem access, e.g. the Claude-compatible
      // tool-result enricher that re-indexes the transcript for truncated
      // results) run in the same isolate pass — on the caller isolate the full
      // line-by-line re-decode + jsonDecode of the whole transcript would
      // block the UI thread on every live refresh once any truncated result
      // exists in the transcript.
      var messages = const <AiMessage>[];
      if (bundle != null) {
        messages = await _parseAndEnrich(
          adapter: cap.adapter,
          enricher: cap.toolResultEnricher,
          bundle: bundle,
          ctx: ctx,
          parentPath: parentPath,
          sourceToken: token,
        );
      }

      // Fresh parse: annotate tool call categories before inflating so that
      // both top-level messages and inflated attachments are covered. The
      // annotator is idempotent, so cache hits below return the same lists.
      messages = annotateToolCallCategories(
        messages,
        resolver: _categoryResolverFor(cli),
      );

      final attachments = await _timed(
        AiHistoryLoadPhase.inflate,
        () => _subagentAttachmentsFor(
          cacheKey: cacheKey,
          cli: cli,
          ctx: ctx,
          messages: messages,
          rootTranscriptPath: parentPath,
        ),
      );

      // 全量 parse 完成后对齐增量状态:让下一次 refresh 变成纯增量
      // (只重读指纹变化的行,原地合并进 messages 同一实例)。
      final refresher = cap.incrementalRefresher;
      if (refresher != null) {
        final incrementalState = refresher.createState();
        await refresher.seedFromFullParse(
          ctx: ctx,
          messages: messages,
          state: incrementalState,
        );
        _incrementalStates[cacheKey] = incrementalState;
      }

      final complete = AiHistoryLoadResult(
        messages: messages,
        cli: cli,
        subagentAttachments: attachments,
        isComplete: true,
      );
      _fullIndexes[cacheKey] = complete;
      _fullIndexFutures[cacheKey] = Future.value(complete);
      if (skipPaging) return complete;
      _messages[cacheKey] = messages;
      _attachments.putIfAbsent(cacheKey, () => {});
      _attachmentSigs[cacheKey] = collectTaskCallSignatures(
        messages,
        cap.subagentToolNames,
      );
      _tokens[cacheKey] = token ?? 'changed-$cacheKey';
      final sideToken = await cap.subagentSideResolver.fingerprint(
        ctx: ctx,
        rootTranscriptPath: parentPath,
      );
      if (sideToken != null) _sideTokens[cacheKey] = sideToken;
      _markComplete(cacheKey);
      _timings?.record(AiHistoryLoadPhase.firstPublish, Duration.zero);
      return complete;
    } on Object catch (e, st) {
      appLogger.e(
        '[ai-history] load failed session=${session.sessionId} '
        'member=$effectiveMemberId cli=$cli: $e',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Older page for a seat that already published a recent window.
  ///
  /// Returns null when there is no cursor (complete in-memory list, or paging
  /// unavailable). Throws when a later page fails so the seat can keep the
  /// current runtime and show a non-blocking error.
  Future<AiHistoryLoadResult?> loadOlder({
    required String sessionId,
    required String memberId,
  }) async {
    final cacheKey = _cacheKey(sessionId, memberId);
    if (_complete[cacheKey] == true) return null;
    final cursor = _cursors[cacheKey];
    final ctx = _pageContexts[cacheKey];
    final cli = _pageClis[cacheKey];
    if (cursor == null || ctx == null || cli == null) return null;
    final cap = _registry.capability<AiHistoryCapability>(cli);
    final reader = cap?.pageReader;
    if (reader == null) return null;
    final page = await reader.readOlder(
      ctx: ctx,
      cursor: cursor,
      limit: kSessionHistoryOlderPageSize,
    );
    if (page == null) return null;
    final messages = annotate(page.messages, cli: cli);
    _cursors[cacheKey] = page.nextCursor;
    _hasOlder[cacheKey] = page.hasOlder;
    _complete[cacheKey] = false;
    final recent = _messages[cacheKey] ?? const <AiMessage>[];
    _messages[cacheKey] = prependOlderHistoryMessages(
      older: messages,
      recent: recent,
    );
    return AiHistoryLoadResult(
      messages: messages,
      cli: cli,
      hasOlder: page.hasOlder,
      cursor: page.nextCursor,
      isComplete: false,
    );
  }

  /// Completed or in-flight full transcript for search / task-board consumers.
  Future<AiHistoryLoadResult?> fullIndex({
    required String sessionId,
    required String memberId,
  }) async {
    final cacheKey = _cacheKey(sessionId, memberId);
    return _fullIndexFutures[cacheKey];
  }

  bool _hasWarmIncremental(String cacheKey) =>
      _tailStates.containsKey(cacheKey) ||
      _incrementalStates.containsKey(cacheKey);

  void _markComplete(String cacheKey) {
    _complete[cacheKey] = true;
    _hasOlder[cacheKey] = false;
    _cursors[cacheKey] = null;
  }

  AiHistoryLoadResult _result({
    required String cacheKey,
    required List<AiMessage> messages,
    required CliTool cli,
    required Map<String, AiSubagentAttachment> subagentAttachments,
    bool subagentSideIndexDirty = false,
  }) {
    return AiHistoryLoadResult(
      messages: messages,
      cli: cli,
      subagentAttachments: subagentAttachments,
      hasOlder: _hasOlder[cacheKey] ?? false,
      cursor: _cursors[cacheKey],
      isComplete: _complete[cacheKey] ?? true,
      subagentSideIndexDirty: subagentSideIndexDirty,
    );
  }

  Future<AiHistoryLoadResult?> _tryPageFirst({
    required AppSession session,
    required String cacheKey,
    required CliTool cli,
    required AiHistoryCapability cap,
    required SessionHistoryContext ctx,
    required String? token,
    required String effectiveMemberId,
  }) async {
    final reader = cap.pageReader;
    if (reader == null) return null;
    try {
      final page = await _timed(
        AiHistoryLoadPhase.read,
        () => reader.readLatest(
          ctx: ctx,
          limit: kSessionHistoryInitialTurns,
        ),
      );
      if (page == null) return null;
      if (_hasWarmIncremental(cacheKey)) return null;
      final messages = annotate(page.messages, cli: cli);
      final parentPath = await _parentPathHint(ctx);
      final attachments = await _timed(
        AiHistoryLoadPhase.inflate,
        () => _subagentAttachmentsFor(
          cacheKey: cacheKey,
          cli: cli,
          ctx: ctx,
          messages: messages,
          rootTranscriptPath: parentPath,
        ),
      );
      if (_hasWarmIncremental(cacheKey)) return null;
      _parentPaths[cacheKey] = parentPath;
      _messages[cacheKey] = messages;
      _attachments[cacheKey] = attachments;
      _tokens[cacheKey] = token ?? 'changed-$cacheKey';
      _hasOlder[cacheKey] = page.hasOlder;
      _cursors[cacheKey] = page.nextCursor;
      _complete[cacheKey] = false;
      _pageContexts[cacheKey] = ctx;
      _pageClis[cacheKey] = cli;
      _fullIndexFutures.putIfAbsent(
        cacheKey,
        () => Future(() {
          return _loadOnce(
            session: session,
            cli: cli,
            effectiveMemberId: effectiveMemberId,
            ctx: ctx,
            cacheKey: cacheKey,
            force: true,
            skipPaging: true,
          );
        }),
      );
      final published = AiHistoryLoadResult(
        messages: messages,
        cli: cli,
        subagentAttachments: attachments,
        hasOlder: page.hasOlder,
        cursor: page.nextCursor,
        isComplete: false,
      );
      _timings?.record(AiHistoryLoadPhase.firstPublish, Duration.zero);
      return published;
    } on Object catch (e, st) {
      appLogger.w(
        '[ai-history] page reader failed, falling back to full parse '
        'cli=$cli: $e',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  void invalidate({required String sessionId, String? memberId}) {
    if (memberId != null) {
      final key = _cacheKey(sessionId, memberId);
      _invalidateToolResultIndexes(identity: _indexIdentityFor(key));
      _tokens.remove(key);
      _messages.remove(key);
      _attachments.remove(key);
      _attachmentSigs.remove(key);
      _parentPaths.remove(key);
      _sideTokens.remove(key);
      _tailStates.remove(key);
      _incrementalStates.remove(key);
      _inflightSubagentLoads.removeWhere((k, _) => k.startsWith('$key\u0000'));
      _subagentSeatGenerations.remove(key);
      _subagentIdGenerations.removeWhere((k, _) => k.startsWith('$key\u0000'));
      _hasOlder.remove(key);
      _cursors.remove(key);
      _complete.remove(key);
      _pageContexts.remove(key);
      _pageClis.remove(key);
      _fullIndexFutures.remove(key);
      _fullIndexes.remove(key);
      return;
    }
    final prefix = '${sessionId.trim()}\u0000';
    for (final key in [..._parentPaths.keys, ..._tokens.keys]
        .where((k) => k.startsWith(prefix))
        .toSet()) {
      _invalidateToolResultIndexes(identity: _indexIdentityFor(key));
    }
    _tokens.removeWhere((key, _) => key.startsWith(prefix));
    _messages.removeWhere((key, _) => key.startsWith(prefix));
    _attachments.removeWhere((key, _) => key.startsWith(prefix));
    _attachmentSigs.removeWhere((key, _) => key.startsWith(prefix));
    _parentPaths.removeWhere((key, _) => key.startsWith(prefix));
    _sideTokens.removeWhere((key, _) => key.startsWith(prefix));
    _tailStates.removeWhere((key, _) => key.startsWith(prefix));
    _incrementalStates.removeWhere((key, _) => key.startsWith(prefix));
    _inflightSubagentLoads.removeWhere((key, _) => key.startsWith(prefix));
    _subagentSeatGenerations.removeWhere((key, _) => key.startsWith(prefix));
    _subagentIdGenerations.removeWhere((key, _) => key.startsWith(prefix));
    _hasOlder.removeWhere((key, _) => key.startsWith(prefix));
    _cursors.removeWhere((key, _) => key.startsWith(prefix));
    _complete.removeWhere((key, _) => key.startsWith(prefix));
    _pageContexts.removeWhere((key, _) => key.startsWith(prefix));
    _pageClis.removeWhere((key, _) => key.startsWith(prefix));
    _fullIndexFutures.removeWhere((key, _) => key.startsWith(prefix));
    _fullIndexes.removeWhere((key, _) => key.startsWith(prefix));
  }

  Future<_AiHistorySeat> _resolveSeat({
    required WorkspaceLaunchContext launchContext,
    required String memberId,
    TeamProfile? team,
    String? workingDirectory,
  }) async {
    final session = launchContext.session;
    final sessionTeam = session.sessionTeam.trim();
    final teamId = () {
      final fromTeam = team?.id.trim() ?? '';
      if (fromTeam.isNotEmpty) return fromTeam;
      return sessionTeam;
    }();
    var effectiveMemberId = memberId.trim();
    // Selected-member UUID without a team id cannot locate team runtime roots.
    if (effectiveMemberId.isNotEmpty && teamId.isEmpty) {
      appLogger.w(
        '[ai-history] drop memberId=$effectiveMemberId without teamId '
        'session=${session.sessionId} (treating as simple seat)',
      );
      effectiveMemberId = '';
    }

    final cli = SessionMemberCliResolver.resolve(
      persistedSession: session,
      team: team,
      memberId: effectiveMemberId,
      globalPresets: _globalPresets?.call() ?? const [],
      cliForMember: (t, id, {List<CliPreset> globalPresets = const []}) {
        for (final m in t.members) {
          if (m.id == id) {
            return memberLaunchCli(
              team: t,
              member: m,
              globalPresets: globalPresets,
            );
          }
        }
        return t.cli;
      },
    );

    final mid = effectiveMemberId.isEmpty ? null : effectiveMemberId;
    final roots = await _resolveWorkContext(launchContext, memberId: mid);
    final ctx = _contextBuilder.build(
      fs: roots.filesystem,
      layout: roots.layout,
      appDataRoot: roots.appDataRoot,
      session: session,
      memberId: effectiveMemberId,
      cli: cli,
      workingDirectory: workingDirectory,
      teamId: teamId.isEmpty ? null : teamId,
    );

    return _AiHistorySeat(
      cli: cli,
      effectiveMemberId: effectiveMemberId,
      ctx: ctx,
    );
  }

  EventDecoder? get _decodeEvents {
    final timings = _timings;
    if (timings == null) return null;
    return (lines) async {
      timings.addDecoderBatch(lines: lines.length);
      return decodeJsonlLines(lines);
    };
  }

  Future<T> _timed<T>(
    AiHistoryLoadPhase phase,
    Future<T> Function() run,
  ) async {
    final timings = _timings;
    if (timings == null) return run();
    final sw = Stopwatch()..start();
    try {
      return await run();
    } finally {
      sw.stop();
      timings.record(phase, sw.elapsed);
    }
  }

  void _invalidateToolResultIndexes({String? identity, bool all = false}) {
    if (!all && (identity == null || identity.trim().isEmpty)) {
      return;
    }
    for (final cli in CliTool.values) {
      final enricher =
          _registry.capability<AiHistoryCapability>(cli)?.toolResultEnricher;
      final cache = enricher is ToolResultIndexCache
          ? enricher as ToolResultIndexCache
          : null;
      cache?.invalidateIndex(sourceToken: all ? null : identity);
    }
  }

  String? _indexIdentityFor(String cacheKey) {
    final path = _parentPaths[cacheKey]?.trim();
    if (path != null && path.isNotEmpty) return path;
    return _tokens[cacheKey];
  }

  Future<List<AiMessage>> _parseAndEnrich({
    required AiTranscriptAdapter adapter,
    required ToolResultEnricher enricher,
    required AiTranscriptBundle bundle,
    required SessionHistoryContext ctx,
    required String? parentPath,
    required String? sourceToken,
  }) async {
    final totalBytes = bundle.fragments.fold<int>(
      0,
      (sum, f) => sum + f.bytes.length,
    );
    final indexCache = enricher is ToolResultIndexCache
        ? enricher as ToolResultIndexCache
        : null;
    final reuse =
        !enricher.requiresFilesystem &&
        indexCache != null &&
        indexCache.canReuseIndex(
          sourceToken: sourceToken,
          rootTranscriptPath: parentPath,
          contentLength: totalBytes,
        );

    // Linux/Android debug: cold Isolate.run can hang forever (child never
    // resumes) and tear down the VM service — same class of failure as the
    // boot index readers. Keep large-parse off-isolate in profile/release only.
    if (enableIsolateParse &&
        !kDebugMode &&
        totalBytes >= _isolateParseMinBytes) {
      if (reuse) {
        final parsed = await _timed(
          AiHistoryLoadPhase.parse,
          () => Isolate.run(
            () => adapter.parse(bundle),
            debugName: 'history-loader',
          ),
        );
        if (_needsToolResultEnrichment(parsed, enricher)) {
          return _enrichMessages(
            enricher: enricher,
            messages: parsed,
            ctx: ctx,
            parentPath: parentPath,
            bundle: bundle,
            sourceToken: sourceToken,
          );
        }
        return parsed;
      }

      final packed = await Isolate.run(() async {
        final parseSw = Stopwatch()..start();
        var parsed = await adapter.parse(bundle);
        parseSw.stop();
        var enrichUs = 0;
        var decodeBatches = 0;
        var decodeLines = 0;
        var decodeUs = 0;
        Object? index;
        if (!enricher.requiresFilesystem &&
            _needsToolResultEnrichment(parsed, enricher)) {
          final enrichSw = Stopwatch()..start();
          parsed = await enricher.enrich(
            messages: parsed,
            ctx: null,
            rootTranscriptPath: parentPath,
            bundle: bundle,
            sourceToken: sourceToken,
          );
          enrichSw.stop();
          enrichUs = enrichSw.elapsedMicroseconds;
          if (enricher is ToolResultIndexCache) {
            final cache = enricher as ToolResultIndexCache;
            decodeBatches = cache.lastDecodeBatches;
            decodeLines = cache.lastDecodeLines;
            decodeUs = cache.lastDecodeMicroseconds;
            index = cache.exportIndex();
          }
        }
        return <Object?>[
          parsed,
          index,
          parseSw.elapsedMicroseconds,
          enrichUs,
          decodeBatches,
          decodeLines,
          decodeUs,
        ];
      }, debugName: 'history-loader');
      final messages = packed[0]! as List<AiMessage>;
      indexCache?.importIndex(packed[1]);
      _recordTimedPhase(AiHistoryLoadPhase.parse, packed[2]! as int);
      final enrichUs = packed[3]! as int;
      if (enrichUs > 0) {
        _recordTimedPhase(AiHistoryLoadPhase.enrich, enrichUs);
      }
      _recordDecodeCounts(
        batches: packed[4]! as int,
        lines: packed[5]! as int,
        microseconds: packed[6]! as int,
      );
      if (enricher.requiresFilesystem &&
          _needsToolResultEnrichment(messages, enricher)) {
        return _enrichMessages(
          enricher: enricher,
          messages: messages,
          ctx: ctx,
          parentPath: parentPath,
          bundle: bundle,
          sourceToken: sourceToken,
        );
      }
      return messages;
    }

    final parsed = await _timed(
      AiHistoryLoadPhase.parse,
      () => adapter.parse(bundle),
    );
    if (_needsToolResultEnrichment(parsed, enricher)) {
      return _enrichMessages(
        enricher: enricher,
        messages: parsed,
        ctx: ctx,
        parentPath: parentPath,
        bundle: bundle,
        sourceToken: sourceToken,
      );
    }
    return parsed;
  }

  Future<List<AiMessage>> _enrichMessages({
    required ToolResultEnricher enricher,
    required List<AiMessage> messages,
    required SessionHistoryContext? ctx,
    required String? parentPath,
    required AiTranscriptBundle? bundle,
    required String? sourceToken,
  }) async {
    final result = await _timed(
      AiHistoryLoadPhase.enrich,
      () => enricher.enrich(
        messages: messages,
        ctx: ctx,
        rootTranscriptPath: parentPath,
        bundle: bundle,
        sourceToken: sourceToken,
      ),
    );
    _recordIndexDecode(enricher);
    return result;
  }

  void _recordTimedPhase(AiHistoryLoadPhase phase, int microseconds) {
    _timings?.record(phase, Duration(microseconds: microseconds));
  }

  void _recordIndexDecode(ToolResultEnricher enricher) {
    if (enricher is! ToolResultIndexCache) return;
    final cache = enricher as ToolResultIndexCache;
    _recordDecodeCounts(
      batches: cache.lastDecodeBatches,
      lines: cache.lastDecodeLines,
      microseconds: cache.lastDecodeMicroseconds,
    );
  }

  void _recordDecodeCounts({
    required int batches,
    required int lines,
    required int microseconds,
  }) {
    if (batches <= 0) return;
    _timings?.addDecoderBatch(lines: lines);
    _timings?.record(
      AiHistoryLoadPhase.decode,
      Duration(microseconds: microseconds),
    );
  }

  static String _cacheKey(String sessionId, String memberId) =>
      '${sessionId.trim()}\u0000${memberId.trim()}';

  /// Cheap parent-transcript path for first-paint attachment inflate. Stats
  /// only — never reads transcript bytes.
  static Future<String> _parentPathHint(SessionHistoryContext ctx) async {
    final probe = await probePinnedTranscript(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: ctx.taskId,
      bucket: ctx.bucket,
      layoutSegments: const ['projects', 'workspaces'],
      matchDirectories: false,
    );
    return probe.matchedPath ?? '';
  }

  /// Enrichers gate per-part via [ToolResultEnricher.needsEnrichment]; skip
  /// [enrich] when no part needs it.
  static bool _needsToolResultEnrichment(
    List<AiMessage> messages,
    ToolResultEnricher enricher,
  ) {
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is AiToolCallPart && enricher.needsEnrichment(part)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Default token resolver: the capability's own cheap live fingerprint
  /// first (OpenCode SQLite store), else the pinned-transcript probe used by
  /// the JSONL CLIs.
  static SessionHistoryCacheTokenResolver _defaultTokenResolverFor(
    AiHistoryCapability cap,
  ) {
    return (ctx) async =>
        await cap.liveCacheToken(ctx) ?? _defaultCacheToken(ctx);
  }

  /// Best-effort transcript identity matching locate `cacheToken`
  /// (`path|mtime|size`) under common Claude/flashskyai layouts.
  static Future<String?> _defaultCacheToken(SessionHistoryContext ctx) async {
    final probe = await probePinnedTranscript(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: ctx.taskId,
      bucket: ctx.bucket,
      layoutSegments: const ['projects', 'workspaces'],
      // Cache token tracks the transcript file's own mtime; a `{sessionId}/`
      // sidecar directory would invalidate on unrelated workflow writes.
      matchDirectories: false,
    );
    final path = probe.matchedPath;
    if (path == null) return null;
    final st = await ctx.fs.stat(path);
    final size = st.size;
    if (size == null) return null;
    return aiHistoryPathCacheToken(fs: ctx.fs, path: path, byteLength: size);
  }
}
