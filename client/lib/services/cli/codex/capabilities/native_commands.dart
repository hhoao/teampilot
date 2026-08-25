import '../../registry/capabilities/native_command_capability.dart';

final class CodexNativeCommands implements NativeCommandCapability {
  const CodexNativeCommands();

  @override
  List<NativeCommand> get commands => const [
    NativeCommand(
      name: 'goal',
      description: NativeCommandDescription.goal,
      argumentHint: '<objective>',
    ),
    NativeCommand(
      name: 'compact',
      description: NativeCommandDescription.compact,
      argumentHint: '[instructions]',
    ),
    NativeCommand(name: 'help', description: NativeCommandDescription.help),
  ];
}
