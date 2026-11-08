import 'dart:io' show Platform;

import '../../../../models/runtime_target.dart';
import '../../../../models/team_config.dart';
import '../../../cli/registry/capabilities/acp_capability.dart';
import '../../../cli/registry/capabilities/cli_transport_capability.dart';
import '../../../cli/registry/cli_tool_registry.dart';

/// What ACP can do for one CLI on one target, ignoring user preference.
enum AcpAvailability {
  /// CLI has no ACP capability, or the target has no exec channel.
  unsupported,

  /// Both PTY and ACP are possible; the user preference decides.
  optional,

  /// ACP-only CLI; ACP is forced when the target supports it.
  forced,
}

/// Settings seed: does this CLI default to ACP chat (personal + members)?
typedef MemberAcpSeed = bool Function(CliTool cli);

/// Capability-only check used by `AppSession` construction fallbacks.
bool acpForcedByCli(CliTool? cli) =>
    CliToolRegistry.builtIn().launchesAcpOnly(cli);

/// Whether ACP can run for [cli] on [targetId], ignoring user preference.
AcpAvailability acpAvailabilityFor({
  required CliTool? cli,
  required String targetId,
}) {
  if (cli == null) return AcpAvailability.unsupported;
  final registry = CliToolRegistry.builtIn();
  if (registry.capability<AcpCapability>(cli) == null) {
    return AcpAvailability.unsupported;
  }
  final kind = runtimeKindOfId(targetId);
  if (kind != RuntimeKind.local && !usesSshTransport(kind)) {
    return AcpAvailability.unsupported;
  }
  if (registry.launchesAcpOnly(cli)) return AcpAvailability.forced;
  final canChoose =
      registry
          .capability<CliTransportCapability>(cli)
          ?.canChooseTransport ??
      false;
  return canChoose ? AcpAvailability.optional : AcpAvailability.unsupported;
}

/// Final ACP flag for one personal session or team seat.
bool resolveAcpOnTarget({
  required CliTool? cli,
  required String targetId,
  required bool requested,
}) {
  return switch (acpAvailabilityFor(cli: cli, targetId: targetId)) {
    AcpAvailability.unsupported => false,
    AcpAvailability.forced => true,
    AcpAvailability.optional => requested,
  };
}

/// True when the user can choose PTY vs ACP for this CLI on this target.
bool canChooseAcpTransport({
  required CliTool? cli,
  required String targetId,
}) =>
    acpAvailabilityFor(cli: cli, targetId: targetId) ==
    AcpAvailability.optional;

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

/// Final ACP flag for a launch.
///
/// [requested] only counts when the CLI declares both transports, on a platform
/// where ACP is available. Session scope (personal / native team / mixed team)
/// and member placement (local / remote) no longer restrict ACP — the CLI
/// preference is the single source of truth. ACP-only CLIs (Gemini, CodeBuddy)
/// are inferred by session create, so `requested` stays false for them.
bool resolveLaunchAcp({
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (!requested || cli == null) return false;
  if (_isAndroid(isAndroidOverride)) return false;
  return CliToolRegistry.builtIn()
          .capability<CliTransportCapability>(cli)
          ?.canChooseTransport ??
      false;
}
