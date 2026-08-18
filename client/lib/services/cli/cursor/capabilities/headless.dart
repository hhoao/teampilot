import 'dart:io';

import '../../../../models/team_config.dart';
import '../../registry/capabilities/headless_capability.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_headless_launch_context.dart';
import '../../registry/launch/headless_launch_context_adapter.dart';
import '../../registry/launch/user_extra_args_provider.dart';
import 'model_launch.dart';
import 'permission_launch.dart';
import 'session_selection_launch.dart';
import 'workspace_access_launch.dart';

/// Cursor one-shot via `cursor-agent -p`.
final class CursorHeadlessCapability implements HeadlessCapability {
  const CursorHeadlessCapability();

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => false;

  @override
  String get executable => 'cursor-agent';

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    'CURSOR_CONFIG_DIR': context.configDir,
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessRunContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext ctx,
  ) sync* {
    final interactive = interactiveContextForHeadless(ctx, CliTool.cursor);
    yield CliLaunchArgContribution(
      key: 'cursor-headless-command',
      phase: LaunchArgPhase.command,
      args: ['-p'],
    );
    yield* const CursorSessionSelectionLaunch().buildLaunchArgs(interactive);
    yield* const CursorWorkspaceAccessLaunch().buildLaunchArgs(interactive);
    yield* const CursorModelLaunch().buildLaunchArgs(interactive);
    yield* const CursorPermissionLaunch().buildLaunchArgs(interactive);
    yield CliLaunchArgContribution(
      key: 'cursor-headless-prompt',
      phase: LaunchArgPhase.prompt,
      args: [ctx.prompt],
    );
    yield* const UserExtraArgsProvider().buildLaunchArgs(interactive);
  }

  @override
  String extractText(ProcessResult result) =>
      (result.stdout as String? ?? '').trim();

  @override
  String? streamResultText(String line) => null;

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async => const HeadlessProvisionResult();
}
