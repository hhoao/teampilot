import '../../registry/capabilities/presence_capability.dart';

final class CodexPresence implements PresenceCapability {
  const CodexPresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
}
