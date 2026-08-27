import 'package:ai_message_core/ai_message_core.dart';

import '../../models/team_config.dart';
import 'ai_history_page.dart';

/// Parsed History messages plus inflated subagent attachment index.
class AiHistoryLoadResult {
  const AiHistoryLoadResult({
    required this.messages,
    required this.cli,
    this.subagentAttachments = const {},
    this.hasOlder = false,
    this.cursor,
    this.isComplete = true,
  });

  final List<AiMessage> messages;
  final CliTool cli;
  final Map<String, AiSubagentAttachment> subagentAttachments;

  /// True when an older page (or an in-memory window) exists beyond [messages].
  final bool hasOlder;

  /// Cursor for [AiHistoryLoader.loadOlder]. Null when [hasOlder] is false.
  final AiHistoryCursor? cursor;

  /// True when [messages] is the full transcript, not only a recent page.
  final bool isComplete;
}
