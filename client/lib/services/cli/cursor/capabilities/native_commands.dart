import '../../registry/capabilities/native_command_capability.dart';

final class CursorNativeCommands implements NativeCommandCapability {
  const CursorNativeCommands();

  @override
  List<NativeCommand> get commands => const [
    NativeCommand(
      name: 'goal',
      description: NativeCommandDescription.goal,
      argumentHint: '<objective>',
      availability: NativeCommandAvailability.experimental,
    ),
    NativeCommand(name: 'help', description: NativeCommandDescription.help),
  ];
}
