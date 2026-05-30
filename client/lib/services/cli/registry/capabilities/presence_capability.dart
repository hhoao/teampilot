import '../cli_capability.dart';

abstract interface class PresenceCapability implements CliCapability {
  bool get usesClaudeRoster;
  bool get usesShellActivity;
}
