import 'package:ai_message_core/ai_message_core.dart';

import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../models/workspace_launch_context.dart';
import '../../utils/logging/logger.dart';
import '../cli/preset_resolver.dart';
import '../cli/registry/capabilities/ai_history_capability.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../storage/runtime_context.dart';
import '../terminal/session_member_cli_resolver.dart';
import 'ai_history_load_result.dart';
import 'ai_history_locator.dart';
import 'ai_history_watch_meta.dart';
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

class _AiHistoryCacheEntry {
  const _AiHistoryCacheEntry({
    required this.token,
    required this.messages,
    this.subagentAttachments = const {},
  });

  final String token;
  final List<AiMessage> messages;
  final Map<String, AiSubagentAttachment> subagentAttachments;
}

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

/// Resolves seat CLI → locate bundle → [AiTranscriptAdapter] → messages, with
/// sessionId+memberId(+mtime) caching.
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

  final _cache = <String, _AiHistoryCacheEntry>{};

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
  void clearCache() => _cache.clear();

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
    final preliminaryToken = await (_resolveCacheToken ?? _defaultCacheToken)(
      ctx,
    );
    if (!force && preliminaryToken != null) {
      final hit = _cache[cacheKey];
      if (hit != null && hit.token == preliminaryToken) {
        return AiHistoryLoadResult(
          messages: hit.messages,
          subagentAttachments: hit.subagentAttachments,
        );
      }
    }

    try {
      final bundle = await _locator.locate(ctx: ctx, cli: cli);
      final hintToken = bundle?.hints['cacheToken']?.trim();
      // Custom resolvers own the cache key; otherwise prefer locate hints.
      final token = _resolveCacheToken != null
          ? preliminaryToken
          : ((hintToken != null && hintToken.isNotEmpty)
                ? hintToken
                : preliminaryToken);

      if (!force && token != null) {
        final hit = _cache[cacheKey];
        if (hit != null && hit.token == token) {
          return AiHistoryLoadResult(
            messages: hit.messages,
            subagentAttachments: hit.subagentAttachments,
          );
        }
      }

      final messages = bundle == null
          ? const <AiMessage>[]
          : await cap.adapter.parse(bundle);

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

      final attachments = await const SubagentAttachmentInflater().inflate(
        messages: messages,
        ctx: ctx,
        capability: cap,
        rootTranscriptPath: parentPath,
      );

      // Null token is uncacheable — never treat null==null as a forever hit.
      if (token != null) {
        _cache[cacheKey] = _AiHistoryCacheEntry(
          token: token,
          messages: messages,
          subagentAttachments: attachments,
        );
      } else {
        _cache.remove(cacheKey);
      }
      return AiHistoryLoadResult(
        messages: messages,
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
      _cache.remove(_cacheKey(sessionId, memberId));
      return;
    }
    final prefix = '${sessionId.trim()}\u0000';
    _cache.removeWhere((key, _) => key.startsWith(prefix));
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

  /// Best-effort transcript mtime under common Claude/flashskyai layouts.
  static Future<String?> _defaultCacheToken(SessionHistoryContext ctx) async {
    final probe = await probePinnedTranscript(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: ctx.taskId,
      bucket: ctx.bucket,
      layoutSegments: const ['projects', 'workspaces'],
    );
    final path = probe.matchedPath;
    if (path == null) return null;
    final st = await ctx.fs.stat(path);
    final mtime = st.mtime;
    if (mtime != null) return mtime.toUtc().toIso8601String();
    return path;
  }
}
