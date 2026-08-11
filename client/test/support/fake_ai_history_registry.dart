import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/subagent_side_resolver.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/tool_result_enricher.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/session/session_history_context.dart';

/// Minimal [AiHistoryCapability] for loader/locator tests.
final class FakeAiHistoryCapability implements AiHistoryCapability {
  FakeAiHistoryCapability({
    required this.adapter,
    this.locateFn,
    this.lineAppend,
    this.subagentSideResolver = const NullSubagentSideResolver(),
    this.toolResultEnricher = const NoOpToolResultEnricher(),
    this.subagentToolNames = const {},
    this.liveCacheTokenFn,
  });

  @override
  final AiTranscriptAdapter adapter;

  final Future<AiTranscriptBundle?> Function(SessionHistoryContext ctx)?
  locateFn;

  final Future<String?> Function(SessionHistoryContext ctx)? liveCacheTokenFn;

  @override
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx) =>
      locateFn?.call(ctx) ?? Future.value(null);

  @override
  final AiTranscriptLineAppend? lineAppend;

  @override
  String get tailFallbackPrefix => 'test';

  @override
  final Set<String> subagentToolNames;

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  final ToolResultEnricher toolResultEnricher;

  @override
  Future<String?> liveCacheToken(SessionHistoryContext ctx) =>
      liveCacheTokenFn?.call(ctx) ?? Future.value(null);
}

class _FakeHistoryCliTool implements CliToolDefinition {
  const _FakeHistoryCliTool(this.id, this._history);

  final AiHistoryCapability _history;

  @override
  final CliTool id;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [_history];
}

/// Registers a single CLI with the given history capability.
CliToolRegistry fakeAiHistoryRegistry({
  required CliTool cli,
  required AiTranscriptAdapter adapter,
  Future<AiTranscriptBundle?> Function(SessionHistoryContext ctx)? locate,
  SubagentSideResolver subagentSideResolver = const NullSubagentSideResolver(),
  ToolResultEnricher toolResultEnricher = const NoOpToolResultEnricher(),
  Set<String> subagentToolNames = const {},
  Future<String?> Function(SessionHistoryContext ctx)? liveCacheToken,
}) {
  final registry = CliToolRegistry();
  registry.register(
    _FakeHistoryCliTool(
      cli,
      FakeAiHistoryCapability(
        adapter: adapter,
        locateFn: locate,
        subagentSideResolver: subagentSideResolver,
        toolResultEnricher: toolResultEnricher,
        subagentToolNames: subagentToolNames,
        liveCacheTokenFn: liveCacheToken,
      ),
    ),
  );
  return registry;
}
