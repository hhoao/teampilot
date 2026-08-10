import '../registry/cli_bootstrap.dart';
import 'provider/claude_provider_credentials_service.dart';

final class ClaudeBootstrapEntry implements CliBootstrapEntry {
  const ClaudeBootstrapEntry({required this.credentialsService});

  final ClaudeProviderCredentialsService credentialsService;
}
