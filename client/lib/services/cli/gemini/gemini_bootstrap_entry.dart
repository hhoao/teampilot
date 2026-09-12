import '../registry/cli_bootstrap.dart';

/// Gemini runtime services injected after home storage is ready.
///
/// Phase 1 (ACP): only the credential source — the API key for the agent
/// process environment. The credential store is not reachable from the
/// pre-configure registration, so [registerBuiltInCliTools] falls back to a
/// null credential source (key omitted; gemini falls back to its own auth)
/// until [CliToolRegistry.configure] runs with this entry.
final class GeminiBootstrapEntry implements CliBootstrapEntry {
  const GeminiBootstrapEntry({required this.credentialSource});

  /// Returns the stored Gemini API key, or null when unset.
  final String? Function() credentialSource;
}
