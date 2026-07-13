import 'package:ai_message_core/ai_message_core.dart';

import '../../models/team_config.dart';
import '../cli/registry/capabilities/history/claude_ai_transcript.dart';
import '../cli/registry/capabilities/history/codex_ai_transcript.dart';
import '../cli/registry/capabilities/history/cursor_ai_transcript.dart';
import '../cli/registry/capabilities/history/flashskyai_ai_transcript.dart';
import '../cli/registry/capabilities/history/opencode_ai_transcript.dart';
import 'session_history_context.dart';

/// Resolves on-disk transcript bytes for a seat CLI into an [AiTranscriptBundle].
class AiHistoryLocator {
  const AiHistoryLocator();

  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) {
    switch (cli) {
      case CliTool.claude:
        return locateClaudeTranscript(ctx);
      case CliTool.flashskyai:
        return locateFlashskyaiTranscript(ctx);
      case CliTool.codex:
        return locateCodexTranscript(ctx);
      case CliTool.opencode:
        return locateOpencodeTranscript(ctx);
      case CliTool.cursor:
        return locateCursorTranscript(ctx);
    }
  }
}
