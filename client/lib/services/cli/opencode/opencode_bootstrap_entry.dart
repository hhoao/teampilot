import '../registry/cli_bootstrap.dart';
import 'provider/opencode_models_service.dart';
import 'provider/opencode_provider_credentials_service.dart';

final class OpencodeBootstrapEntry implements CliBootstrapEntry {
  const OpencodeBootstrapEntry({
    required this.credentialsService,
    this.modelsService,
  });

  final OpencodeProviderCredentialsService credentialsService;
  final OpencodeModelsService? modelsService;
}
