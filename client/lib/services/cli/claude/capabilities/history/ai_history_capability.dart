import 'package:ai_message_core/ai_message_core.dart';

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../io/filesystem.dart';
import '../../../../session/jsonl_transcript_page_reader.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../../../registry/capabilities/resume/pinned_transcript_probe.dart';
import '../../../registry/capabilities/shared_tool_call_resolvers.dart';
import 'ai_transcript.dart';
import 'compatible_jsonl.dart';
import 'compatible_tool_result_enricher.dart';
import 'side_resolver.dart';

final class ClaudeAiHistoryCapability implements AiHistoryCapability {
  const ClaudeAiHistoryCapability({
    this.subagentSideResolver = const ClaudeSideResolver(),
    ToolResultEnricher? toolResultEnricher,
    this.pageFilesystem,
  }) : _toolResultEnricher = toolResultEnricher;

  /// Test seam; production reads go through [SessionHistoryContext.fs].
  final Filesystem? pageFilesystem;
  final ToolResultEnricher? _toolResultEnricher;

  static final _defaultEnricher = ClaudeCompatibleToolResultEnricher();

  static const _layoutSegments = ['projects'];
  static const _resolvers = SharedToolCallResolvers();

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateClaudeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const ClaudeAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendClaudeJsonlEvent;

  @override
  AiTranscriptPageReader get pageReader => JsonlTranscriptPageReader(
    fs: pageFilesystem,
    lineAppend: lineAppend,
    fallbackPrefix: tailFallbackPrefix,
    sourcePath: locateClaudeTranscriptPath,
  );

  @override
  String get tailFallbackPrefix => 'claude';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task', 'workflow'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  ToolResultEnricher get toolResultEnricher =>
      _toolResultEnricher ?? _defaultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;

  @override
  AiTranscriptIncrementalRefresher? get incrementalRefresher => null;

  @override
  Map<String, String> sessionEnv({String? toolRoot}) => const {};

  /// `clientPinned`: we pin our UUID with `--session-id` at creation, so the
  /// native id == [ResumeContext.taskId]. Claude stores transcripts under
  /// `{config}/projects/{cwd-bucket}/{id}.jsonl` (not flashskyai's
  /// `workspaces/` layout).
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
