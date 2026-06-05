import 'npm_installer_capability.dart';

/// In-app npm installer for Claude Code (`@anthropic-ai/claude-code`).
final class ClaudeInstallerCapability extends NpmInstallerCapability {
  const ClaudeInstallerCapability();

  @override
  String get npmPackage => '@anthropic-ai/claude-code';

  @override
  String get executableName => 'claude';

  @override
  String get displayName => 'Claude Code';
}
