import '../../../../l10n/app_localizations.dart';
import 'display_capability.dart';
import 'executable_resolver_capability.dart';
import 'plugin_manifest_paths.dart';
import 'presence_capability.dart';
import 'terminal_behavior_capability.dart';

final class FlashskyaiExecutableResolver implements ExecutableResolverCapability {
  const FlashskyaiExecutableResolver();
  @override
  String get defaultExecutableName => 'flashskyai';
  @override
  String get preferencesPathKey => 'flashskyai';
}

final class ClaudeExecutableResolver implements ExecutableResolverCapability {
  const ClaudeExecutableResolver();
  @override
  String get defaultExecutableName => 'claude';
  @override
  String get preferencesPathKey => 'claude';
}

final class CodexExecutableResolver implements ExecutableResolverCapability {
  const CodexExecutableResolver();
  @override
  String get defaultExecutableName => 'codex';
  @override
  String get preferencesPathKey => 'codex';
}

final class FlashskyaiPresence implements PresenceCapability {
  const FlashskyaiPresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => true;
}

final class ClaudePresence implements PresenceCapability {
  const ClaudePresence();
  @override
  bool get usesClaudeRoster => true;
  @override
  bool get usesShellActivity => false;
}

final class CodexPresence implements PresenceCapability {
  const CodexPresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
}

final class OpencodeExecutableResolver implements ExecutableResolverCapability {
  const OpencodeExecutableResolver();
  @override
  String get defaultExecutableName => 'opencode';
  @override
  String get preferencesPathKey => 'opencode';
}

final class OpencodePresence implements PresenceCapability {
  const OpencodePresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
}

final class CursorExecutableResolver implements ExecutableResolverCapability {
  const CursorExecutableResolver();
  @override
  String get defaultExecutableName => 'cursor-agent';
  @override
  String get preferencesPathKey => 'cursor';
}

final class CursorPresence implements PresenceCapability {
  const CursorPresence();
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
}

final class FlashskyaiDisplay implements DisplayCapability {
  const FlashskyaiDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolFlashskyai;
}

final class ClaudeDisplay implements DisplayCapability {
  const ClaudeDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolClaude;
}

final class CodexDisplay implements DisplayCapability {
  const CodexDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolCodex;
}

final class OpencodeDisplay implements DisplayCapability {
  const OpencodeDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolOpencode;
}

final class CursorDisplay implements DisplayCapability {
  const CursorDisplay();
  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolCursor;
}

final class FlashskyaiTerminalBehavior implements TerminalBehaviorCapability {
  const FlashskyaiTerminalBehavior();
  @override
  bool get usesFullScreenInput => false;
  @override
  bool get forwardsColorSchemeReport => true;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false);
}

final class ClaudeTerminalBehavior implements TerminalBehaviorCapability {
  const ClaudeTerminalBehavior();
  @override
  bool get usesFullScreenInput => true;
  @override
  bool get forwardsColorSchemeReport => true;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);
}

final class CodexTerminalBehavior implements TerminalBehaviorCapability {
  const CodexTerminalBehavior();
  @override
  bool get usesFullScreenInput => true;
  @override
  bool get forwardsColorSchemeReport => true;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);
}

final class OpencodeTerminalBehavior implements TerminalBehaviorCapability {
  const OpencodeTerminalBehavior();
  @override
  bool get usesFullScreenInput => false;
  @override
  bool get forwardsColorSchemeReport => true;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: false);
}

final class CursorTerminalBehavior implements TerminalBehaviorCapability {
  const CursorTerminalBehavior();
  @override
  bool get usesFullScreenInput => true;
  @override
  bool get forwardsColorSchemeReport => false;
  @override
  TerminalPathDropBehavior get pathDropBehavior =>
      TerminalPathDropBehavior.defaultFor(usesFullScreenInput: true);
}

