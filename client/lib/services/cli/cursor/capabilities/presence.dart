import '../../registry/capabilities/presence_capability.dart';

final class CursorPresence implements PresenceCapability {
  const CursorPresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
}
