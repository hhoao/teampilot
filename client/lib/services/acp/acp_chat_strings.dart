/// User-facing strings for the ACP chat runtime, resolved by the UI layer.
///
/// The cubit stays l10n-free (services/cubits resolve no arb directly); the
/// host injects the localized copy through [AcpChatRuntimeCubit.ensureStrings]
/// before `start`.
class AcpChatStrings {
  const AcpChatStrings({
    required this.launchFailedVersion,
    required this.turnFailed,
    required this.processExited,
  });

  /// [acpLaunchFailedVersion] copy: no ACP flag candidate produced a usable
  /// agent (old CLI version).
  final String launchFailedVersion;

  /// Prefix for a turn that ended with a surfaced error.
  final String turnFailed;

  /// Prefix for the agent process dying mid-session (`{exitCode}` appended).
  final String processExited;
}
