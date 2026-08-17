import '../registry/cli_bootstrap.dart';
import '../../provider/api_model_catalog_service.dart';
import 'provider/codex_provider_credentials_service.dart';

final class CodexBootstrapEntry implements CliBootstrapEntry {
  const CodexBootstrapEntry({
    required this.credentialsService,
    this.modelsService,
  });

  final CodexProviderCredentialsService credentialsService;
  final ApiModelCatalogService? modelsService;
}
