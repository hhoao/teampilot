import '../../cli_tool_adapter.dart';
import '../../registry/capabilities/noop_cli_session_capability.dart';
import 'launch_args.dart';

/// Codex session capability: noop lifecycle + standard CONFIG_DIR layout,
/// argv delegated to [CodexCliToolAdapter].
final class CodexCliSessionCapability extends NoopCliSessionCapability {
  const CodexCliSessionCapability();

  @override
  List<String> buildArguments(CliLaunchContext context) =>
      const CodexCliToolAdapter().buildArguments(context);
}
