import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../../registry/capabilities/resume/pinned_transcript_probe.dart';
import '../../../registry/capabilities/shared_tool_call_resolvers.dart';
import '../../../claude/capabilities/history/compatible_jsonl.dart';
import '../../../claude/capabilities/history/compatible_side_resolver.dart';
import '../../../claude/capabilities/history/compatible_tool_result_enricher.dart';
import 'ai_transcript.dart';

final class FlashskyaiAiHistoryCapability implements AiHistoryCapability {
  const FlashskyaiAiHistoryCapability({
    this.subagentSideResolver = const ClaudeCompatibleSideResolver(),
    this.toolResultEnricher = const ClaudeCompatibleToolResultEnricher(),
  });

  static const _resolvers = SharedToolCallResolvers();

  // Real flashskyai installs use `projects/`; keep `workspaces` for older trees.
  static const _layoutSegments = ['projects', 'workspaces'];

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateFlashskyaiTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const FlashskyaiAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendClaudeJsonlEvent;

  @override
  String get tailFallbackPrefix => 'flashskyai';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

  @override
  Map<String, String> sessionEnv({String? toolRoot}) => const {};

  /// `clientPinned`: we pin our UUID with `--session-id` at creation, so the
  /// native id == [ResumeContext.taskId] and a resumable session is detected
  /// by the presence of the CLI's transcript file `<taskId>.jsonl` (or
  /// `<taskId>/` dir) under `projects|workspaces/{bucket}/`.
  @override
  ResumeBinding get binding => ResumeBinding.clientPinned;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    // Duplicated sessions carry the source transcript under its original
    // pinned filename; prefer the persisted id over the taskId probe.
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (persisted.isNotEmpty) {
      final persistedExists = await pinnedTranscriptExists(
        fs: ctx.fs,
        toolRoots: ctx.transcriptRoots,
        sessionId: persisted,
        bucket: ctx.bucket,
        layoutSegments: _layoutSegments,
      );
      if (persistedExists) return persisted;
    }
    final id = ctx.taskId.trim();
    if (id.isEmpty) return null;
    final exists = await pinnedTranscriptExists(
      fs: ctx.fs,
      toolRoots: ctx.transcriptRoots,
      sessionId: id,
      bucket: ctx.bucket,
      layoutSegments: _layoutSegments,
    );
    return exists ? id : null;
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
