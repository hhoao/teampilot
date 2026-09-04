import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/provider_usage/managed_provider_presets.dart';

void main() {
  test('built-in presets expose stable provider templates', () {
    expect(builtInManagedProviderPresets.map((preset) => preset.id), [
      'codex',
      'claude-code',
      'cursor',
      'deepseek',
    ]);

    final codex = managedProviderPresetById('codex')!;
    expect(codex.template.name, 'Codex');
    expect(codex.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(codex.template.adapterId, 'http-json');
    expect(codex.template.endpointConfig.credentialSource, 'cli:codex');

    final claude = managedProviderPresetById('claude-code')!;
    expect(claude.template.name, 'Claude Code');
    expect(claude.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(claude.template.adapterId, 'http-json');
    expect(
      claude.template.endpointConfig.credentialSource,
      'cli:claude',
    );

    final cursor = managedProviderPresetById('cursor')!;
    expect(cursor.template.adapterId, 'http-json');
    expect(cursor.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(
      cursor.template.endpointConfig.url,
      'https://cursor.com/api/usage-summary',
    );
    expect(
      cursor.template.endpointConfig.credentialSource,
      'cli:cursor',
    );
    expect(
      cursor.template.endpointConfig.credentialTemplate,
      'WorkosCursorSessionToken={accountId}::{accessToken}',
    );
  });

  test('DeepSeek preset is ready for an API key without containing one', () {
    final preset = managedProviderPresetById('deepseek')!;
    final endpoint = preset.template.endpointConfig;

    expect(preset.template.kind, ManagedProviderKind.apiBalance);
    expect(preset.template.adapterId, 'http-json');
    expect(endpoint.url, 'https://api.deepseek.com/user/balance');
    expect(endpoint.method, 'GET');
    expect(
      endpoint.windows,
      const [
        ManagedProviderUsageWindow(
          label: 'USD',
          remaining: r'$.balance_infos[0].total_balance',
        ),
        ManagedProviderUsageWindow(
          label: 'CNY',
          remaining: r'$.balance_infos[1].total_balance',
        ),
      ],
    );
    expect(endpoint.credentialName, 'Authorization');
    expect(endpoint.credentialField, 'apiKey');
    expect(endpoint.credentialPlacement, 'header');
    expect(endpoint.credentialPrefix, 'Bearer ');
    expect(preset.template.credentialRef, isNull);
  });

  test('lookup returns null for unknown preset ids', () {
    expect(managedProviderPresetById('not-a-preset'), isNull);
  });

  test('quick preset options include built-ins and custom', () {
    expect(managedProviderQuickPresetOptionIds, [
      'codex',
      'claude-code',
      'cursor',
      'deepseek',
      kManagedProviderQuickPresetCustomId,
    ]);
  });
}
