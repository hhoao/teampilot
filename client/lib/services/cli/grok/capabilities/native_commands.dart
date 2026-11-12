import '../../registry/capabilities/native_command_capability.dart';

/// Curated Grok slash-command surface shared with TeamPilot's compose menu.
final class GrokNativeCommands implements NativeCommandCapability {
  const GrokNativeCommands();

  @override
  List<NativeCommand> get commands => const [
    NativeCommand(
      name: '/compact',
      description: NativeCommandDescription.compact,
    ),
    NativeCommand(name: '/help', description: NativeCommandDescription.help),
    NativeCommand(name: '/plan', description: NativeCommandDescription.plan),
  ];
}
