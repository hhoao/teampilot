import 'package:ai_message_core/ai_message_core.dart';

import '../../models/team_config.dart';
import 'ai_history_providers.dart';
import 'session_history_context.dart';

/// Resolves on-disk transcript bytes for a seat CLI into an [AiTranscriptBundle].
class AiHistoryLocator {
  AiHistoryLocator({
    Map<CliTool, AiHistoryProvider>? providers,
  }) : _providers = providers ?? kAiHistoryProviders;

  final Map<CliTool, AiHistoryProvider> _providers;

  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) {
    final provider = _providers[cli];
    if (provider == null) {
      throw StateError('AiHistoryProvider missing for launch CLI $cli');
    }
    return provider.locate(ctx);
  }
}
