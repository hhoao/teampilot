import '../cli_capability.dart';

/// The CLI implements first-party multi-agent native teams (roster + team flags),
/// not merely parallel single-agent terminals under [TeamMode.native].
///
/// Register on tool definitions that pass `--team-name` / `--team` (etc.) and
/// provision a shared native roster. Mixed-mode teams use [TeamBus] instead and
/// do not require this capability.
abstract interface class NativeTeamCapability implements CliCapability {}

/// Shared marker instance for built-in native-team CLIs.
final class NativeTeamSupport implements NativeTeamCapability {
  const NativeTeamSupport();
}
