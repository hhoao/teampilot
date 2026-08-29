import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/provider_usage/official_managed_provider_binding.dart';

void main() {
  test('maps cli credential sources to CLI provider rows', () {
    final cursor = OfficialManagedProviderBinding.forCredentialSource(
      'cli:cursor-account',
    );
    expect(cursor?.cli, CliTool.cursor);
    expect(cursor?.appProviderId, 'cursor-account');
    expect(OfficialManagedProviderBinding.forCredentialSource('secret'), isNull);
  });
}
