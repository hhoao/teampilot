import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/claude_official_provider.dart';

void main() {
  test('official provider with empty env', () {
    const p = AppProviderConfig(
      id: 'work',
      cli: AppProviderCli.claude,
      name: 'Work',
      category: AppProviderCategory.official,
      config: {'env': {}},
    );
    expect(isOfficialClaudeProvider(p), isTrue);
  });

  test('third party with base url is not official credential provider', () {
    const p = AppProviderConfig(
      id: 'ds',
      cli: AppProviderCli.claude,
      name: 'DS',
      category: AppProviderCategory.thirdParty,
      baseUrl: 'https://api.deepseek.com',
      config: {'env': {'ANTHROPIC_BASE_URL': 'https://api.deepseek.com'}},
    );
    expect(isOfficialClaudeProvider(p), isFalse);
  });

  test('settings map official detection', () {
    expect(isOfficialClaudeSettings({'env': {}}), isTrue);
    expect(
      isOfficialClaudeSettings({
        'env': {'ANTHROPIC_BASE_URL': 'https://x'},
      }),
      isFalse,
    );
  });
}
