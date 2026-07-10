import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../utils/logger.dart';
import '../cli/preset_resolver.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/capabilities/session_history_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../io/filesystem.dart';
import '../storage/runtime_layout.dart';
import '../terminal/session_member_cli_resolver.dart';
import 'session_history_context_builder.dart';

/// Cache fingerprint for a history snapshot (typically transcript mtime).
typedef SessionHistoryCacheTokenResolver =
    Future<String?> Function(SessionHistoryContext ctx);

class _HistoryCacheEntry {
  const _HistoryCacheEntry({required this.token, required this.snapshot});

  final String? token;
  final SessionHistorySnapshot snapshot;
}

/// Resolves seat CLI → [SessionHistoryCapability] → snapshot, with
/// sessionId+memberId(+mtime) caching.
final class SessionHistoryLoader {
  SessionHistoryLoader({
    required CliToolRegistry registry,
    SessionHistoryContextBuilder contextBuilder =
        const SessionHistoryContextBuilder(),
    required Filesystem Function() fs,
    required RuntimeLayout Function() layout,
    required String Function() appDataRoot,
    SessionHistoryCacheTokenResolver? resolveCacheToken,
    List<CliPreset> Function()? globalPresets,
  }) : _registry = registry,
       _contextBuilder = contextBuilder,
       _fs = fs,
       _layout = layout,
       _appDataRoot = appDataRoot,
       _resolveCacheToken = resolveCacheToken,
       _globalPresets = globalPresets;

  final CliToolRegistry _registry;
  final SessionHistoryContextBuilder _contextBuilder;
  final Filesystem Function() _fs;
  final RuntimeLayout Function() _layout;
  final String Function() _appDataRoot;
  final SessionHistoryCacheTokenResolver? _resolveCacheToken;
  final List<CliPreset> Function()? _globalPresets;

  final _cache = <String, _HistoryCacheEntry>{};

  Future<SessionHistorySnapshot> load({
    required AppSession session,
    required String memberId,
    TeamProfile? team,
    String? workingDirectory,
    bool force = false,
  }) async {
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
        '[session-history] drop memberId=$effectiveMemberId without teamId '
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

    final cap = _registry.capability<SessionHistoryCapability>(cli);
    if (cap == null) {
      appLogger.e(
        '[session-history] SessionHistoryCapability missing for CLI $cli '
        'session=${session.sessionId}',
      );
      throw StateError('SessionHistoryCapability missing for launch CLI $cli');
    }

    final ctx = _contextBuilder.build(
      fs: _fs(),
      layout: _layout(),
      appDataRoot: _appDataRoot(),
      session: session,
      memberId: effectiveMemberId,
      cli: cli,
      workingDirectory: workingDirectory,
      teamId: teamId.isEmpty ? null : teamId,
    );

    final cacheKey = _cacheKey(session.sessionId, effectiveMemberId);
    final token = await (_resolveCacheToken ?? _defaultCacheToken)(ctx);
    if (!force) {
      final hit = _cache[cacheKey];
      if (hit != null && hit.token == token) {
        return hit.snapshot;
      }
    }

    try {
      final snapshot = await cap.loadHistory(ctx);
      _cache[cacheKey] = _HistoryCacheEntry(token: token, snapshot: snapshot);
      return snapshot;
    } on Object catch (e, st) {
      appLogger.e(
        '[session-history] loadHistory failed session=${session.sessionId} '
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
