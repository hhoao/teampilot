import '../registry/cli_bootstrap.dart';

/// Grok runtime services injected after home storage is ready.
///
/// The API key source is a sync closure because the ACP environment is built
/// synchronously; provider rows load asynchronously and are cached by the app
/// shell.
final class GrokBootstrapEntry implements CliBootstrapEntry {
  const GrokBootstrapEntry({required this.credentialSource});

  /// Returns the stored xAI API key, or null when unset.
  final String? Function() credentialSource;
}
