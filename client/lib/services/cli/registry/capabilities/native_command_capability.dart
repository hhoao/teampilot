import '../cli_capability.dart';

enum NativeCommandDescription { goal, compact, plan, help }

enum NativeCommandAvailability { stable, experimental }

final class NativeCommand {
  const NativeCommand({
    required this.name,
    required this.description,
    this.argumentHint,
    this.availability = NativeCommandAvailability.stable,
  });

  final String name;
  final NativeCommandDescription description;
  final String? argumentHint;
  final NativeCommandAvailability availability;

  bool get acceptsArgument => argumentHint != null;

  String get insertText => acceptsArgument ? '/$name ' : '/$name';
}

abstract interface class NativeCommandCapability implements CliCapability {
  List<NativeCommand> get commands;
}
