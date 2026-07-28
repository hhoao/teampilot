import 'package:ai_message_core/ai_message_core.dart';

import '../../../session/session_history_context.dart';
import '../cli_capability.dart';
import 'history/subagent_side_resolver.dart';

abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;
  /// Lower-case names.
  Set<String> get subagentToolNames;
  SubagentSideResolver get subagentSideResolver;
}
