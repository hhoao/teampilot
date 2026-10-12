import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

/// Interactive TUI has no `--model` on OpenCode v2 (unknown flag dumps help).
/// The picker selection is stamped into `opencode.json` `"model"`.
/// Headless `opencode run` still accepts `--model`.
final class OpencodeModelLaunch implements CliLaunchArgProvider {
  const OpencodeModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    _validate(context);
    return const [];
  }

  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    _validate(context);
    final contribution = _modelArgs(context);
    if (contribution != null) yield contribution;
  }

  void _validate(CliLaunchContext context) {
    final provider = context.member.provider.trim();
    final model = context.member.model.trim();
    if (provider.isNotEmpty && model.isEmpty) {
      throw const CliLaunchCapabilityException(
        cli: CliTool.opencode,
        contributionKey: 'opencode-model',
        reason: 'OpenCode requires a model when a provider is selected.',
      );
    }
  }

  CliLaunchArgContribution? _modelArgs(CliLaunchContext context) {
    final provider = context.member.provider.trim();
    final model = context.member.model.trim();
    if (model.isEmpty) return null;
    return CliLaunchArgContribution(
      key: 'opencode-model',
      phase: LaunchArgPhase.model,
      args: ['--model', provider.isEmpty ? model : '$provider/$model'],
    );
  }
}
