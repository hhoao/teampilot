import '../../cli_tool_adapter.dart';
import '../../registry/capabilities/noop_cli_session_capability.dart';
import 'launch_args.dart';

/// flashskyai session capability: noop lifecycle + standard CONFIG_DIR layout,
/// argv delegated to [FlashskyaiCliToolAdapter].
final class FlashskyaiCliSessionCapability extends NoopCliSessionCapability {
  const FlashskyaiCliSessionCapability();

  @override
  List<String> buildArguments(CliLaunchContext context) =>
      const FlashskyaiCliToolAdapter().buildArguments(context);
}
