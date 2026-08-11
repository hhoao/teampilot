import '../../registry/capabilities/presence_capability.dart';

final class ClaudePresence implements PresenceCapability {
  const ClaudePresence();
  @override
  bool get usesClaudeRoster => true;
  @override
  bool get usesShellActivity => false;
}
