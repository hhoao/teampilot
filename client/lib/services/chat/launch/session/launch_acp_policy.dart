import 'dart:io' show Platform;

import '../../../../models/team_config.dart';
import '../../../cli/registry/capabilities/cli_transport_capability.dart';
import '../../../cli/registry/cli_tool_registry.dart';

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
