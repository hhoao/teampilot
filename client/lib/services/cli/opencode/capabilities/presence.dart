import '../../registry/capabilities/presence_capability.dart';

final class OpencodePresence implements PresenceCapability {
  const OpencodePresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
}
