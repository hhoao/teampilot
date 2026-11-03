import '../../registry/capabilities/native_command_capability.dart';

/// Antigravity advertises native commands through ACP
/// (`available_commands_update`), so the static surface stays empty.
final class AntigravityNativeCommands implements NativeCommandCapability {
  const AntigravityNativeCommands();

  @override
  List<NativeCommand> get commands => const [];
}
