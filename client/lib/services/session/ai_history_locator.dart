import 'package:ai_message_core/ai_message_core.dart';

import '../../models/team_config.dart';
import '../cli/registry/capabilities/ai_history_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import 'session_history_context.dart';

/// Resolves on-disk transcript bytes for a seat CLI into an [AiTranscriptBundle].
class AiHistoryLocator {
  AiHistoryLocator({
    CliToolRegistry? registry,
  }) : _registry = registry ?? CliToolRegistry.builtIn();

  final CliToolRegistry _registry;

  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) {
    final cap = _registry.capability<AiHistoryCapability>(cli);
    if (cap == null) {
      throw StateError('AiHistoryCapability missing for launch CLI $cli');
    }
    return cap.locate(ctx);
  }
}
