import '../registry/cli_bootstrap.dart';
import '../../provider/api_model_catalog_service.dart';
import 'provider/claude_provider_credentials_service.dart';

final class ClaudeBootstrapEntry implements CliBootstrapEntry {
  const ClaudeBootstrapEntry({
    required this.credentialsService,
    this.modelsService,
  });

  final ClaudeProviderCredentialsService credentialsService;
  final ApiModelCatalogService? modelsService;
}
