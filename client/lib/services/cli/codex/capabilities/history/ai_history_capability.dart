import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../../registry/capabilities/shared_tool_call_resolvers.dart';
import 'ai_transcript.dart';
import 'root_rollout.dart';
import 'side_resolver.dart';

final class CodexAiHistoryCapability implements AiHistoryCapability {
  const CodexAiHistoryCapability({
    this.subagentSideResolver = const CodexSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
  });

  static const _resolvers = SharedToolCallResolvers();

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
  /// `sessions/**/rollout-*.jsonl` tree holds this session's parent plus any
  /// spawn_agent children. Capture the **root** uuid (never a child) and
  /// resume with `codex resume <uuid>`.
  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    final home = ctx.env['CODEX_HOME']?.trim() ?? '';
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (home.isEmpty) return persisted.isEmpty ? null : persisted;

    final hit = await pickCodexRootRollout(
      fs: ctx.fs,
      codexHome: home,
      persistedNativeId: ctx.persistedNativeId,
    );
    if (hit != null) return hit.uuid;
    // Empty store (first launch) or unreadable tree: keep a previously
    // captured id so resume still has something to pass through.
    return persisted.isEmpty ? null : persisted;
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
