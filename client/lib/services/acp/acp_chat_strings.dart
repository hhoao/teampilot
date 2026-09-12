/// User-facing strings for the ACP chat runtime, resolved by the UI layer.
///
/// The cubit stays l10n-free (services/cubits resolve no arb directly); the
/// host injects the localized copy through [AcpChatRuntimeCubit.ensureStrings]
/// before `start`.
library;

import 'acp_session_runtime.dart';

/// Fallback [AcpChatStrings] for hosts that inject no localized copy
/// (tests, embedding shells). Production always injects via the host hook;
/// these English constants only keep the record total.
// TODO(l10n): every production host must inject `acpChatStrings`; these
// defaults are not localized by design.
const AcpChatStrings defaultAcpChatStrings = AcpChatStrings(
  launchFailedVersion: acpLaunchFailedVersion,
  turnFailed: 'Turn failed',
  processExited: 'Agent process exited',
);

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
