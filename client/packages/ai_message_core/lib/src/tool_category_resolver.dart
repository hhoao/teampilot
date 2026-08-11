import 'message.dart';

/// Maps a tool call to its coarse category. Implementations are per-CLI
/// (client/lib/services/cli/registry/capabilities/) or the shared default
/// table (client/lib/services/ai_history/tool_call_categories.dart).
abstract interface class AiToolCallCategoryResolver {
  AiToolCallCategory resolve(AiToolCallPart part);
}
