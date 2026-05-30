import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

CliToolRegistry createTestCliRegistry() {
  final registry = CliToolRegistry();
  registerBuiltInCliTools(registry);
  return registry;
}
