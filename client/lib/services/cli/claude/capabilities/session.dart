import '../../cli_tool_adapter.dart';
import '../../registry/capabilities/noop_cli_session_capability.dart';
import 'launch_args.dart';

/// Claude session capability: noop lifecycle + standard CONFIG_DIR layout,
/// argv delegated to [ClaudeCodeCliToolAdapter].
final class ClaudeCliSessionCapability extends NoopCliSessionCapability {
  const ClaudeCliSessionCapability();

  @override
  List<String> buildArguments(CliLaunchContext context) =>
      const ClaudeCodeCliToolAdapter().buildArguments(context);
}
