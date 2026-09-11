import '../../registry/capabilities/native_command_capability.dart';

/// Gemini has no curated TeamPilot native-command surface in this phase.
final class GeminiNativeCommands implements NativeCommandCapability {
  const GeminiNativeCommands();

  @override
  List<NativeCommand> get commands => const [];
}
