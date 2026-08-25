import '../../registry/capabilities/native_command_capability.dart';

final class FlashskyaiNativeCommands implements NativeCommandCapability {
  const FlashskyaiNativeCommands();

  @override
  List<NativeCommand> get commands => const [
    NativeCommand(name: 'help', description: NativeCommandDescription.help),
  ];
}
