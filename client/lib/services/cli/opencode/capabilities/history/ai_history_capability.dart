import 'package:ai_message_core/ai_message_core.dart';
import 'package:path/path.dart' as p;

import '../../../registry/capabilities/ai_history_capability.dart';
import '../../../../session/session_history_context.dart';
import '../../../registry/capabilities/history/subagent_side_resolver.dart';
import '../../../registry/capabilities/history/tool_result_enricher.dart';
import '../native_session_id.dart';
import '../tool_call_resolvers.dart';
import 'ai_transcript.dart';
import 'side_resolver.dart';
import 'tool_output_backfill_enricher.dart';

final class OpencodeAiHistoryCapability implements AiHistoryCapability {
  const OpencodeAiHistoryCapability({
    this.subagentSideResolver = const OpencodeSideResolver(),
    this.toolResultEnricher = const OpencodeToolOutputBackfillEnricher(),
    this.liveCacheTokenImpl = opencodeLiveCacheToken,
    this.pageReaderOverride,
  });

  final Future<String?> Function(SessionHistoryContext ctx) liveCacheTokenImpl;

  /// Test seam for callers that need to supply an isolated page source.
  final AiTranscriptPageReader? pageReaderOverride;

  static const _resolvers = OpencodeToolCallResolvers();

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateOpencodeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const OpencodeAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend? get lineAppend => null; // multi-file DB; no single-line incremental dialect.

  @override
  AiTranscriptPageReader get pageReader =>
      pageReaderOverride ?? const OpencodeTranscriptPageReader();

  @override
  AiTranscriptIncrementalRefresher get incrementalRefresher =>
      const OpencodeHistoryIncrementalRefresher();

  @override
  String get tailFallbackPrefix => 'opencode';

  @override
  Set<String> get subagentToolNames => const {'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) =>
      liveCacheTokenImpl(ctx);

  @override
  Map<String, String> sessionEnv({String? toolRoot}) {
    if (toolRoot == null || toolRoot.isEmpty) return const {};
    return {'OPENCODE_DB': p.join(toolRoot, 'opencode.db')};
  }

  /// `postCaptured`: opencode generates `ses_*` ids; we isolate the session
  /// via absolute `OPENCODE_DB` (see the config profile), so the SQLite store
  /// is unambiguous. We capture the id and resume with `--session <id>`.
  @override
  ResumeBinding get binding => ResumeBinding.postCaptured;

  @override
  Future<String?> detectNativeId(ResumeContext ctx) async {
    final dataDir = _dataDirFromEnv(ctx);
    final persisted = ctx.persistedNativeId?.trim() ?? '';
    if (dataDir.isEmpty) {
      return persisted.isEmpty ? null : persisted;
    }
    return resolveOpencodeNativeSessionId(
      fs: ctx.fs,
      dataDir: dataDir,
      persistedNativeId: ctx.persistedNativeId,
    );
  }

  static String _dataDirFromEnv(ResumeContext ctx) {
    final db = ctx.env['OPENCODE_DB']?.trim() ?? '';
    if (db.isEmpty || db == ':memory:') return '';
    return ctx.fs.pathContext.dirname(db);
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
