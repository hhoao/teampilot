import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/provider_usage/managed_provider_presets.dart';

void main() {
  test('built-in presets expose stable provider templates', () {
    expect(builtInManagedProviderPresets.map((preset) => preset.id), [
      'codex',
      'claude-code',
      'deepseek',
      'opencode',
    ]);

    final codex = managedProviderPresetById('codex')!;
    expect(codex.template.name, 'Codex');
    expect(codex.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(codex.template.adapterId, 'official-codex-subscription');

    final claude = managedProviderPresetById('claude-code')!;
    expect(claude.template.name, 'Claude Code');
    expect(claude.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(claude.template.adapterId, 'official-claude-subscription');
  });

  test('DeepSeek preset is ready for an API key without containing one', () {
    final preset = managedProviderPresetById('deepseek')!;
    final endpoint = preset.template.endpointConfig;

    expect(preset.template.kind, ManagedProviderKind.apiBalance);
    expect(preset.template.adapterId, 'http-json');
    expect(endpoint.url, 'https://api.deepseek.com/user/balance');
    expect(endpoint.method, 'GET');
    expect(endpoint.measuresPath, r'$.balance_infos');
    expect(endpoint.fieldMappings, {
      'label': r'$.currency',
      'remaining': r'$.total_balance',
      'currency': r'$.currency',
    });
    expect(endpoint.credentialName, 'Authorization');
    expect(endpoint.credentialField, 'apiKey');
    expect(endpoint.credentialPlacement, 'header');
    expect(endpoint.credentialPrefix, 'Bearer ');
    expect(preset.template.credentialRef, isNull);
  });

  test('OpenCode preset does not invent a balance endpoint', () {
    final preset = managedProviderPresetById('opencode')!;

    expect(preset.template.name, 'OpenCode');
    expect(preset.template.kind, ManagedProviderKind.customHttp);
    expect(preset.template.adapterId, 'http-json');
    expect(preset.template.endpointConfig.url, isEmpty);
    expect(preset.template.credentialRef, isNull);
  });

  test('lookup returns null for unknown preset ids', () {
    expect(managedProviderPresetById('not-a-preset'), isNull);
  });
}
