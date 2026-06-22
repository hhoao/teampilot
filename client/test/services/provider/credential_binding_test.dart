import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/provider/claude/claude_official_provider.dart';
import 'package:teampilot/services/provider/credential_binding.dart';

void main() {
  test('official claude defaults to linked binding', () {
    const provider = AppProviderConfig(
      id: 'default',
      cli: CliTool.claude,
      name: 'Default',
      category: AppProviderCategory.official,
      config: {'env': {}},
    );
    expect(resolveCredentialBinding(provider), CredentialBindingKind.linked);
  });

  test('explicit isolated binding is preserved', () {
    const provider = AppProviderConfig(
      id: 'default',
      cli: CliTool.claude,
      name: 'Default',
      category: AppProviderCategory.official,
      config: {
        'env': {},
        credentialBindingConfigKey: 'isolated',
      },
    );
    expect(resolveCredentialBinding(provider), CredentialBindingKind.isolated);
  });

  test('custom third-party providers default to isolated', () {
    const provider = AppProviderConfig(
      id: 'packy',
      cli: CliTool.claude,
      name: 'Packy',
      category: AppProviderCategory.thirdParty,
      config: {
        'env': {'ANTHROPIC_API_KEY': 'sk-test'},
      },
    );
    expect(isOfficialClaudeProvider(provider), isFalse);
    expect(resolveCredentialBinding(provider), CredentialBindingKind.isolated);
  });
}
