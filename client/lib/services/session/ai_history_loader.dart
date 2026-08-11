import 'dart:isolate';

import 'package:ai_message_core/ai_message_core.dart';

import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../models/workspace_launch_context.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';
import '../ai_history/tool_call_categories.dart';
import '../ai_history/tool_call_category_annotator.dart';
import '../cli/preset_resolver.dart';
import '../cli/registry/capabilities/ai_history_capability.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/capabilities/tool_call_resolver_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../storage/runtime_context.dart';
import '../terminal/session_member_cli_resolver.dart';
import 'ai_history_load_result.dart';
import 'ai_history_locator.dart';
import 'ai_history_watch_meta.dart';
import 'ai_transcript_tail_reader.dart';
import 'session_history_context.dart';
import 'session_history_context_builder.dart';
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
  }) : _contextBuilder = contextBuilder,
       _resolveWorkContext = resolveWorkContext,
       _registry = registry ?? CliToolRegistry.builtIn(),
       _locator =
           locator ??
           AiHistoryLocator(registry: registry ?? CliToolRegistry.builtIn()),
       _resolveCacheToken = resolveCacheToken,
       _globalPresets = globalPresets;

  final SessionHistoryContextBuilder _contextBuilder;
  final AiHistoryWorkContextResolver _resolveWorkContext;
  final CliToolRegistry _registry;
  final AiHistoryLocator _locator;
  final SessionHistoryCacheTokenResolver? _resolveCacheToken;
  final List<CliPreset> Function()? _globalPresets;

  /// Per-seat cache: resolver token → messages → attachments.
  final _tokens = <String, String>{};
  final _messages = <String, List<AiMessage>>{};
  final _attachments = <String, Map<String, AiSubagentAttachment>>{};

  /// Per-seat located parent transcript path (for side fingerprinting) and
  /// last-observed side-transcript fingerprint.
  final _parentPaths = <String, String>{};
  final _sideTokens = <String, String>{};

  /// Incremental tail state (cacheKey → state) and per-CLI tail readers. The
  /// state owns the live [List] that [load] hands out; the reader is stateless
  /// per CLI (all mutable state lives in [TailReaderState]).
  final _tailStates = <String, TailReaderState>{};
  final _tailReaders = <String, AiTranscriptTailReader>{};

  /// Bundles at/above this size parse on a worker isolate; smaller ones parse
  /// in place (isolate spawn + transfer overhead would dominate).
  static const _isolateParseMinBytes = 256 * 1024;

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
    _parentPaths.clear();
    _sideTokens.clear();
    _tailStates.clear();
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
    bool force = false,
  }) async {
    if (parentPath == null || parentPath.isEmpty) return null;
    final reader = _tailReaderFor(cli);
    if (reader == null) return null;
    final state = _tailStates.putIfAbsent(cacheKey, TailReaderState.new);
    await reader.refresh(
      fs: ctx.fs,
      path: parentPath,
      state: state,
      force: force,
    );
    return state.messages;
  }

  AiToolCallCategoryResolver _categoryResolverFor(CliTool cli) =>
      _registry.capability<ToolCallResolversCapability>(cli)?.categoryResolver ??
      defaultToolCallCategoryResolver;

  /// Defensive annotation for post-load merged lists (mailbox). Idempotent.
  List<AiMessage> annotate(List<AiMessage> messages, {required CliTool cli}) =>
      annotateToolCallCategories(
        messages,
        resolver: _categoryResolverFor(cli),
      );

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

    final cap = _registry.capability<AiHistoryCapability>(cli);
    if (cap == null) {
      appLogger.e(
        '[ai-history] AiHistoryCapability missing for CLI $cli '
        'session=${session.sessionId}',
      );
      throw StateError('AiHistoryCapability missing for launch CLI $cli');
    }

    final cacheKey = _cacheKey(session.sessionId, effectiveMemberId);

    final token = await (_resolveCacheToken ?? _defaultTokenResolverFor(cap))(ctx);
    if (!force && token != null && _tokens[cacheKey] == token) {
      final cachedMessages = _messages[cacheKey] ?? const [];
      final cachedAttachments = _attachments[cacheKey] ?? const {};
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
        return AiHistoryLoadResult(
          messages: cachedMessages,
          cli: cli,
          subagentAttachments: cachedAttachments,
        );
      }
      var attachments = await const SubagentAttachmentInflater().inflate(
        messages: cachedMessages,
        ctx: ctx,
        capability: cap,
        rootTranscriptPath: _parentPaths[cacheKey],
      );
      // Fresh parts from the re-inflate are unannotated → annotate now.
      attachments = annotateSubagentAttachments(
        attachments,
        resolver: _categoryResolverFor(cli),
      );
      _attachments[cacheKey] = attachments;
      _sideTokens[cacheKey] = sideToken;
      return AiHistoryLoadResult(
        messages: cachedMessages,
        cli: cli,
        subagentAttachments: attachments,
      );
    }

    try {
      final bundle = await _locator.locate(ctx: ctx, cli: cli);
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

      // 增量优先:JSONL 类 CLI 走 tail-anchor 增量(原地变异复用消息实例);
      // 失败/不适配(无 path、无 lineAppend、非 JSONL 存储)回退全量 parse。
      var incremental = await _tryIncrementalLoad(
        cacheKey: cacheKey,
        cli: cli,
        ctx: ctx,
        parentPath: parentPath,
        force: force,
      );
      if (incremental != null) {
        // Tail-appended parts are unannotated → annotate now (idempotent on
        // parts the previous load already covered).
        incremental = annotateToolCallCategories(
          incremental,
          resolver: _categoryResolverFor(cli),
        );
        // Attachments: reuse the cached map across appends — only the first
        // (inflate-less) load inflates, and only when nothing is cached yet.
        // Cached maps are already annotated (we always store the annotated
        // result); only the fresh inflate needs annotation.
        var attachments = _attachments[cacheKey];
        if (attachments == null) {
          attachments = await const SubagentAttachmentInflater().inflate(
            messages: incremental,
            ctx: ctx,
            capability: cap,
            rootTranscriptPath: parentPath,
          );
          attachments = annotateSubagentAttachments(
            attachments,
            resolver: _categoryResolverFor(cli),
          );
        }
        _messages[cacheKey] = incremental;
        _attachments[cacheKey] = attachments;
        _tokens[cacheKey] = token ?? 'changed-$cacheKey';
        return AiHistoryLoadResult(
          messages: incremental,
          cli: cli,
          subagentAttachments: attachments,
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
        final adapter = cap.adapter;
        final enricher = cap.toolResultEnricher;
        final totalBytes = bundle.fragments.fold<int>(
          0,
          (sum, f) => sum + f.bytes.length,
        );
        if (totalBytes >= _isolateParseMinBytes) {
          messages = await Isolate.run(() async {
            var parsed = await adapter.parse(bundle);
            // Bundle-only enrichers never touch ctx (guarded by
            // requiresFilesystem), so null is safe on the worker isolate.
            if (!enricher.requiresFilesystem &&
                _needsToolResultEnrichment(parsed)) {
              parsed = await enricher.enrich(
                messages: parsed,
                ctx: null,
                rootTranscriptPath: parentPath,
                bundle: bundle,
              );
            }
            return parsed;
          });
        } else {
          messages = await adapter.parse(bundle);
          if (_needsToolResultEnrichment(messages)) {
            messages = await enricher.enrich(
              messages: messages,
              ctx: ctx,
              rootTranscriptPath: parentPath,
              bundle: bundle,
            );
          }
        }
      }

      // Fresh parse: annotate tool call categories before inflating so that
      // both top-level messages and inflated attachments are covered. The
      // annotator is idempotent, so cache hits below return the same lists.
      messages = annotateToolCallCategories(
        messages,
        resolver: _categoryResolverFor(cli),
      );

      var attachments = await const SubagentAttachmentInflater().inflate(
        messages: messages,
        ctx: ctx,
        capability: cap,
        rootTranscriptPath: parentPath,
      );
      attachments = annotateSubagentAttachments(
        attachments,
        resolver: _categoryResolverFor(cli),
      );

      _messages[cacheKey] = messages;
      _attachments[cacheKey] = attachments;
      _tokens[cacheKey] = token ?? 'changed-$cacheKey';
      final sideToken = await cap.subagentSideResolver.fingerprint(
        ctx: ctx,
        rootTranscriptPath: parentPath,
      );
      if (sideToken != null) _sideTokens[cacheKey] = sideToken;
      return AiHistoryLoadResult(
        messages: messages,
        cli: cli,
        subagentAttachments: attachments,
      );
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

  void invalidate({required String sessionId, String? memberId}) {
    if (memberId != null) {
      final key = _cacheKey(sessionId, memberId);
      _tokens.remove(key);
      _messages.remove(key);
      _attachments.remove(key);
      _parentPaths.remove(key);
      _sideTokens.remove(key);
      _tailStates.remove(key);
      return;
    }
    final prefix = '${sessionId.trim()}\u0000';
    _tokens.removeWhere((key, _) => key.startsWith(prefix));
    _messages.removeWhere((key, _) => key.startsWith(prefix));
    _attachments.removeWhere((key, _) => key.startsWith(prefix));
    _parentPaths.removeWhere((key, _) => key.startsWith(prefix));
    _sideTokens.removeWhere((key, _) => key.startsWith(prefix));
    _tailStates.removeWhere((key, _) => key.startsWith(prefix));
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

  static String _cacheKey(String sessionId, String memberId) =>
      '${sessionId.trim()}\u0000${memberId.trim()}';

  /// The Claude enricher full-reads the transcript to resolve truncated tool
  /// results; skip it when no part carries the truncation sentinel.
  static bool _needsToolResultEnrichment(List<AiMessage> messages) {
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is AiToolCallPart) {
          final result = part.result;
          if (result is String && result.contains('tool output truncated')) {
            return true;
          }
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
    return (ctx) async => await cap.liveCacheToken(ctx) ?? _defaultCacheToken(ctx);
  }

  /// Best-effort transcript mtime under common Claude/flashskyai layouts.
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
    final mtime = st.mtime;
    if (mtime != null) return mtime.toUtc().toIso8601String();
    return path;
  }
}
