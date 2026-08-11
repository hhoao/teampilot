import '../../registry/capabilities/presence_capability.dart';

final class FlashskyaiPresence implements PresenceCapability {
  const FlashskyaiPresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => true;
}
