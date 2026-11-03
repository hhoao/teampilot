import '../../../../models/team_config.dart';
import '../../registry/launch/cli_launch_arg_contribution.dart';
import '../../registry/launch/cli_launch_arg_provider.dart';
import '../../registry/launch/cli_launch_capability_error.dart';
import '../../registry/launch/cli_launch_context.dart';

/// Interactive TUI has no `--model` on OpenCode v2 (unknown flag dumps help),
/// and headless `opencode run` reads the same `opencode.json` `"model"` key.
///
/// The model selector therefore lives in exactly one place — the config file —
/// and this contribution only validates that a model was picked. Emitting
/// `--model` here would introduce a second source of truth that has to re-derive
/// the upstream namespace (Go vs Zen) without the provider record in hand.
final class OpencodeModelLaunch implements CliLaunchArgProvider {
  const OpencodeModelLaunch();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    _validate(context);
    return const [];
  }

  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliLaunchContext context,
  ) {
    _validate(context);
    return const [];
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
}
