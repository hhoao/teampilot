import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';
import '../ai_history_capability.dart';
import 'claude_ai_transcript.dart';
import 'codex_ai_transcript.dart';
import 'cursor_ai_transcript.dart';
import 'flashskyai_ai_transcript.dart';
import 'opencode_ai_transcript.dart';
import 'claude_compatible_side_resolver.dart';
import 'codex_side_resolver.dart';
import 'cursor_side_resolver.dart';
import 'opencode_side_resolver.dart';
import 'subagent_side_resolver.dart';
import 'tool_result_enricher.dart';

final class ClaudeAiHistoryCapability implements AiHistoryCapability {
  const ClaudeAiHistoryCapability({
    this.subagentSideResolver = const ClaudeCompatibleSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateClaudeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const ClaudeAiTranscriptAdapter();

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;
}

final class FlashskyaiAiHistoryCapability implements AiHistoryCapability {
  const FlashskyaiAiHistoryCapability({
    this.subagentSideResolver = const ClaudeCompatibleSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateFlashskyaiTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const FlashskyaiAiTranscriptAdapter();

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;
}

final class CodexAiHistoryCapability implements AiHistoryCapability {
  const CodexAiHistoryCapability({
    this.subagentSideResolver = const CodexSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateCodexTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const CodexAiTranscriptAdapter();

  @override
  Set<String> get subagentToolNames => const {'spawn_agent', 'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;
}

final class OpencodeAiHistoryCapability implements AiHistoryCapability {
  const OpencodeAiHistoryCapability({
    this.subagentSideResolver = const OpencodeSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateOpencodeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const OpencodeAiTranscriptAdapter();

  @override
  Set<String> get subagentToolNames => const {'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;
}

final class CursorAiHistoryCapability implements AiHistoryCapability {
  const CursorAiHistoryCapability({
    this.subagentSideResolver = const CursorSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateCursorTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const CursorAiTranscriptAdapter();

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;
}
