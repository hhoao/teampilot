import 'package:ai_message_core/ai_message_core.dart';

import '../../../session/session_history_context.dart';
import '../cli_capability.dart';
import 'history/claude_compatible_jsonl.dart';
import 'history/subagent_side_resolver.dart';
import 'history/tool_result_enricher.dart';

abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;
  /// Lower-case names.
  Set<String> get subagentToolNames;
  SubagentSideResolver get subagentSideResolver;
  ToolResultEnricher get toolResultEnricher;

  /// Per-line incremental parser for [AiTranscriptTailer]. Null when the CLI's
  /// transcript cannot be parsed incrementally (loader falls back to a full
  /// [adapter].parse of the located bundle).
  AiTranscriptLineAppend? get lineAppend;
}
