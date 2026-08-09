import '../registry/cli_bootstrap.dart';
import 'provider/codex_provider_credentials_service.dart';

final class CodexBootstrapEntry implements CliBootstrapEntry {
  const CodexBootstrapEntry({required this.credentialsService});

  final CodexProviderCredentialsService credentialsService;
}
