import '../../cli_tool_adapter.dart';
import '../../registry/capabilities/noop_cli_session_capability.dart';
import 'launch_args.dart';

/// opencode session capability: noop lifecycle + standard CONFIG_DIR layout,
/// argv delegated to [OpencodeCliToolAdapter].
final class OpencodeCliSessionCapability extends NoopCliSessionCapability {
  const OpencodeCliSessionCapability();

  @override
  List<String> buildArguments(CliLaunchContext context) =>
      const OpencodeCliToolAdapter().buildArguments(context);
}
