import 'npm_installer_capability.dart';

/// In-app npm installer for OpenAI Codex CLI (`@openai/codex`).
final class CodexInstallerCapability extends NpmInstallerCapability {
  const CodexInstallerCapability();

  @override
  String get npmPackage => '@openai/codex';

  @override
  String get executableName => 'codex';

  @override
  String get displayName => 'Codex';
}
