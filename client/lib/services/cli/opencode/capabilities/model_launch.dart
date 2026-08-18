import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

final class OpencodeModelLaunch implements CliLaunchArgProvider {
  const OpencodeModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final provider = context.member.provider.trim();
    final model = context.member.model.trim();
    if (provider.isNotEmpty && model.isEmpty) {
      throw const CliLaunchCapabilityException(
        cli: CliTool.opencode,
        contributionKey: 'opencode-model',
        reason: 'OpenCode requires a model when a provider is selected.',
      );
    }
    if (model.isEmpty) return;

    yield CliLaunchArgContribution(
      key: 'opencode-model',
      phase: LaunchArgPhase.model,
      args: ['--model', provider.isEmpty ? model : '$provider/$model'],
    );
  }
}
