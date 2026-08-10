import '../registry/cli_bootstrap.dart';
import 'provider/cursor_agent_models_service.dart';
import 'provider/cursor_provider_credentials_service.dart';

final class CursorBootstrapEntry implements CliBootstrapEntry {
  const CursorBootstrapEntry({
    required this.credentialsService,
    this.agentModelsService,
  });

  final CursorProviderCredentialsService credentialsService;
  final CursorAgentModelsService? agentModelsService;
}
