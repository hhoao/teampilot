import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';

abstract interface class LaunchArgsCapability implements CliCapability {
  List<String> buildArguments(CliLaunchContext context);
}
