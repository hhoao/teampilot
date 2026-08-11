import 'package:ai_message_core/ai_message_core.dart';

import '../../../../session/session_history_context.dart';
import '../ai_history_capability.dart';
import '../../../claude/capabilities/history/ai_transcript.dart';
import '../../../codex/capabilities/history/ai_transcript.dart';
import '../../../cursor/capabilities/history/ai_transcript.dart';
import '../../../flashskyai/capabilities/history/ai_transcript.dart';
import '../../../opencode/capabilities/history/ai_transcript.dart';
import '../../../claude/capabilities/history/compatible_jsonl.dart';
import '../../../claude/capabilities/history/compatible_side_resolver.dart';
import '../../../claude/capabilities/history/side_resolver.dart';
import '../../../codex/capabilities/history/side_resolver.dart';
import '../../../cursor/capabilities/history/side_resolver.dart';
import '../../../claude/capabilities/history/compatible_tool_result_enricher.dart';
import '../../../cursor/capabilities/history/terminal_tool_result_enricher.dart';
import '../../../opencode/capabilities/history/side_resolver.dart';
import 'subagent_side_resolver.dart';
import 'tool_result_enricher.dart';

final class ClaudeAiHistoryCapability implements AiHistoryCapability {
  const ClaudeAiHistoryCapability({
    this.subagentSideResolver = const ClaudeSideResolver(),
    this.toolResultEnricher = const ClaudeCompatibleToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateClaudeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const ClaudeAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendClaudeJsonlEvent;

  @override
  String get tailFallbackPrefix => 'claude';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task', 'workflow'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
}

final class FlashskyaiAiHistoryCapability implements AiHistoryCapability {
  const FlashskyaiAiHistoryCapability({
    this.subagentSideResolver = const ClaudeCompatibleSideResolver(),
    this.toolResultEnricher = const ClaudeCompatibleToolResultEnricher(),
  });

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateFlashskyaiTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const FlashskyaiAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendClaudeJsonlEvent;

  @override
  String get tailFallbackPrefix => 'flashskyai';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
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
  AiTranscriptLineAppend get lineAppend => appendCodexJsonlEvent;

  @override
  String get tailFallbackPrefix => 'codex';

  @override
  Set<String> get subagentToolNames => const {'spawn_agent', 'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
}

final class OpencodeAiHistoryCapability implements AiHistoryCapability {
  const OpencodeAiHistoryCapability({
    this.subagentSideResolver = const OpencodeSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
    this.liveCacheTokenImpl = opencodeLiveCacheToken,
  });

  final Future<String?> Function(SessionHistoryContext ctx) liveCacheTokenImpl;

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateOpencodeTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const OpencodeAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend? get lineAppend => null; // multi-file DB; no single-line incremental dialect.

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
}

final class CursorAiHistoryCapability implements AiHistoryCapability {
  const CursorAiHistoryCapability({
    required this.shellResolver,
    this.subagentSideResolver = const CursorSideResolver(),
  });

  final AiShellToolTargetResolver shellResolver;

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateCursorTranscript(ctx);

  @override
  AiTranscriptAdapter get adapter => const CursorAiTranscriptAdapter();

  @override
  AiTranscriptLineAppend get lineAppend => appendCursorJsonlEvent;

  @override
  String get tailFallbackPrefix => 'cursor';

  @override
  Set<String> get subagentToolNames => const {'agent', 'task'};

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  ToolResultEnricher get toolResultEnricher => CursorTerminalToolResultEnricher(
        shellResolver: shellResolver,
      );

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) async => null;
}
