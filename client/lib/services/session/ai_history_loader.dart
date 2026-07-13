import 'package:ai_message_core/ai_message_core.dart';

import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/team_config.dart';
import '../../utils/logger.dart';
import '../cli/preset_resolver.dart';
import '../cli/registry/capabilities/history/claude_ai_transcript.dart';
import '../cli/registry/capabilities/history/codex_ai_transcript.dart';
import '../cli/registry/capabilities/history/cursor_ai_transcript.dart';
import '../cli/registry/capabilities/history/flashskyai_ai_transcript.dart';
import '../cli/registry/capabilities/history/opencode_ai_transcript.dart';
import '../cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../cli/registry/capabilities/session_history_capability.dart';
import '../io/filesystem.dart';
import '../storage/runtime_layout.dart';
import '../terminal/session_member_cli_resolver.dart';
import 'ai_history_locator.dart';
import 'session_history_context_builder.dart';
import 'session_history_loader.dart';

class _AiHistoryCacheEntry {
  const _AiHistoryCacheEntry({required this.token, required this.messages});

  final String? token;
  final List<AiMessage> messages;
}

/// Resolves seat CLI → locate bundle → [AiTranscriptAdapter] → messages, with
/// sessionId+memberId(+mtime) caching.
final class AiHistoryLoader {
  AiHistoryLoader({
    SessionHistoryContextBuilder contextBuilder =
        const SessionHistoryContextBuilder(),
    required Filesystem Function() fs,
    required RuntimeLayout Function() layout,
    required String Function() appDataRoot,
    AiHistoryLocator locator = const AiHistoryLocator(),
    Map<CliTool, AiTranscriptAdapter>? adapters,
    SessionHistoryCacheTokenResolver? resolveCacheToken,
    List<CliPreset> Function()? globalPresets,
  }) : _contextBuilder = contextBuilder,
       _fs = fs,
       _layout = layout,
       _appDataRoot = appDataRoot,
       _locator = locator,
       _adapters = adapters ?? defaultAdapters,
       _resolveCacheToken = resolveCacheToken,
       _globalPresets = globalPresets;

  static final Map<CliTool, AiTranscriptAdapter> defaultAdapters =
      Map.unmodifiable({
        CliTool.claude: const ClaudeAiTranscriptAdapter(),
        CliTool.flashskyai: const FlashskyaiAiTranscriptAdapter(),
        CliTool.codex: const CodexAiTranscriptAdapter(),
        CliTool.opencode: const OpencodeAiTranscriptAdapter(),
        CliTool.cursor: const CursorAiTranscriptAdapter(),
      });

  final SessionHistoryContextBuilder _contextBuilder;
  final Filesystem Function() _fs;
  final RuntimeLayout Function() _layout;
  final String Function() _appDataRoot;
  final AiHistoryLocator _locator;
  final Map<CliTool, AiTranscriptAdapter> _adapters;
  final SessionHistoryCacheTokenResolver? _resolveCacheToken;
  final List<CliPreset> Function()? _globalPresets;

  final _cache = <String, _AiHistoryCacheEntry>{};

  Future<List<AiMessage>> load({
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

    final adapter = _adapters[cli];
    if (adapter == null) {
      appLogger.e(
        '[ai-history] AiTranscriptAdapter missing for CLI $cli '
        'session=${session.sessionId}',
      );
      throw StateError('AiTranscriptAdapter missing for launch CLI $cli');
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
        return hit.messages;
      }
    }

    try {
      final bundle = await _locator.locate(ctx: ctx, cli: cli);
      final messages = bundle == null
          ? const <AiMessage>[]
          : await adapter.parse(bundle);
      _cache[cacheKey] = _AiHistoryCacheEntry(
        token: token,
        messages: messages,
      );
      return messages;
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
