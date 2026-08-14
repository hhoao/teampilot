import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../../registry/capabilities/shared_tool_call_resolvers.dart';
import 'ai_transcript.dart';
import 'side_resolver.dart';

final class CodexAiHistoryCapability implements AiHistoryCapability {
  const CodexAiHistoryCapability({
    this.subagentSideResolver = const CodexSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
  });

  static const _resolvers = SharedToolCallResolvers();

  static final _rolloutId = RegExp(
    r'rollout-.*-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$',
  );

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateCodexTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const CodexAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendCodexJsonlEvent;

  @override
  String get tailFallbackPrefix => 'codex';

  @override
  Set<String> get subagentToolNames => const {'spawn_agent', 'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

  @override
  Map<String, String> sessionEnv({String? toolRoot}) {
    if (toolRoot == null || toolRoot.isEmpty) return const {};
    return {'CODEX_HOME': toolRoot};
  }

  /// `postCaptured`: codex generates its own session id and cannot be told
  /// ours, but `$CODEX_HOME` is isolated per session, so its
  /// `sessions/**/rollout-*.jsonl` tree holds exactly this session's rollout.
  /// We capture the uuid embedded in the rollout filename and resume with
  /// `codex resume <uuid>`.
  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    // A previously captured id is authoritative.
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) return persisted;

    final home = ctx.env['CODEX_HOME']?.trim() ?? '';
    if (home.isEmpty) return null;
    final sessionsDir = ctx.fs.pathContext.join(home, 'sessions');
    final basename = ctx.fs.pathContext.basename;

    var bestName = '';
    try {
      final entries = await ctx.fs.listDirRecursive(sessionsDir);
      for (final e in entries) {
        if (e.isDirectory) continue;
        if (!_rolloutId.hasMatch(basename(e.name))) continue;
        // Lexicographic max over timestamp-prefixed names == newest. The
        // isolated home normally holds a single rollout anyway.
        if (e.name.compareTo(bestName) > 0) bestName = e.name;
      }
    } on Object {
      return null;
    }
    if (bestName.isEmpty) return null;
    return _rolloutId.firstMatch(basename(bestName))?.group(1);
  }

  @override
  AiEditToolTargetResolver get editResolver => _resolvers.editResolver;

  @override
  AiToolFileTargetResolver get fileResolver => _resolvers.fileResolver;

  @override
  AiShellToolTargetResolver get shellResolver => _resolvers.shellResolver;

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      _resolvers.categoryResolver;
}
