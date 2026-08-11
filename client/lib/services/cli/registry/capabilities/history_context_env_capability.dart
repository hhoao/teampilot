import '../cli_capability.dart';

/// Environment variables that must be set when building session history context.
///
/// Each CLI derives the env it needs from the on-disk session CONFIG_DIR
/// (resolved by the caller via [CliConfigLayoutCapability]) — the caller never
/// special-cases a CLI identity.
abstract interface class HistoryContextEnvCapability implements CliCapability {
  /// Environment for reading a session's history, given the CLI's session
  /// CONFIG_DIR ([CliConfigLayoutCapability.sessionConfigDir]).
  Map<String, String> sessionEnv({String? toolRoot});
}
