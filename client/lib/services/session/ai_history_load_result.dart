import 'package:ai_message_core/ai_message_core.dart';

import '../../models/team_config.dart';

/// Parsed History messages plus inflated subagent attachment index.
class AiHistoryLoadResult {
  const AiHistoryLoadResult({
    required this.messages,
    required this.cli,
    this.subagentAttachments = const {},
  });

  final List<AiMessage> messages;
  final CliTool cli;
  final Map<String, AiSubagentAttachment> subagentAttachments;
}
