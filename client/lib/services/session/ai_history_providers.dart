import 'package:ai_message_core/ai_message_core.dart';

import '../../models/team_config.dart';
import '../cli/registry/capabilities/history/claude_ai_transcript.dart';
import '../cli/registry/capabilities/history/codex_ai_transcript.dart';
import '../cli/registry/capabilities/history/cursor_ai_transcript.dart';
import '../cli/registry/capabilities/history/flashskyai_ai_transcript.dart';
import '../cli/registry/capabilities/history/opencode_ai_transcript.dart';
import 'session_history_context.dart';

/// Single registration surface for History locate + parse (one entry per CLI).
typedef AiHistoryLocate =
    Future<AiTranscriptBundle?> Function(SessionHistoryContext ctx);

class AiHistoryProvider {
  const AiHistoryProvider({
    required this.adapter,
    required this.locate,
  });

  final AiTranscriptAdapter adapter;
  final AiHistoryLocate locate;
}

/// Built-in History providers keyed by [CliTool]. Adding a sixth CLI means
/// one entry here — locator and loader both consume this map.
final Map<CliTool, AiHistoryProvider> kAiHistoryProviders =
    Map.unmodifiable({
      CliTool.claude: AiHistoryProvider(
        adapter: const ClaudeAiTranscriptAdapter(),
        locate: locateClaudeTranscript,
      ),
      CliTool.flashskyai: AiHistoryProvider(
        adapter: const FlashskyaiAiTranscriptAdapter(),
        locate: locateFlashskyaiTranscript,
      ),
      CliTool.codex: AiHistoryProvider(
        adapter: const CodexAiTranscriptAdapter(),
        locate: locateCodexTranscript,
      ),
      CliTool.opencode: AiHistoryProvider(
        adapter: const OpencodeAiTranscriptAdapter(),
        locate: locateOpencodeTranscript,
      ),
      CliTool.cursor: AiHistoryProvider(
        adapter: const CursorAiTranscriptAdapter(),
        locate: locateCursorTranscript,
      ),
    });

Map<CliTool, AiTranscriptAdapter> aiHistoryDefaultAdapters() =>
    Map.unmodifiable({
      for (final e in kAiHistoryProviders.entries) e.key: e.value.adapter,
    });
