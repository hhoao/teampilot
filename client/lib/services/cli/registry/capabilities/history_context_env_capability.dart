import '../cli_capability.dart';

/// Environment variables that must be set when building session history context.
///
/// Replaces the `switch(cli)` in [SessionHistoryContextBuilder].
abstract interface class HistoryContextEnvCapability implements CliCapability {
  Map<String, String> sessionEnv({
    String? toolRoot,
    String? home,
    String? userProfile,
  });
}
