import '../../registry/capabilities/native_command_capability.dart';

final class OpencodeNativeCommands implements NativeCommandCapability {
  const OpencodeNativeCommands();

  @override
  List<NativeCommand> get commands => const [
    NativeCommand(
      name: 'compact',
      description: NativeCommandDescription.compact,
      argumentHint: '[instructions]',
    ),
    NativeCommand(name: 'help', description: NativeCommandDescription.help),
  ];
}
