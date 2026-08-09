import '../registry/cli_bootstrap.dart';
import 'provider/opencode_provider_credentials_service.dart';

final class OpencodeBootstrapEntry implements CliBootstrapEntry {
  const OpencodeBootstrapEntry({required this.credentialsService});

  final OpencodeProviderCredentialsService credentialsService;
}
