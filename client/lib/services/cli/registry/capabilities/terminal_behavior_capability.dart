import '../cli_capability.dart';

abstract interface class TerminalBehaviorCapability implements CliCapability {
  bool get usesFullScreenInput;
}
