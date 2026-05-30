import '../../../models/app_provider_config.dart';
import 'cli_capability.dart';
import 'cli_tool_id.dart';

abstract interface class CliToolDefinition {
  CliToolId get id;
  bool get isLaunchSupported;
  AppProviderCli? get providerCatalogCli;
  Iterable<CliCapability> get capabilities;
}
