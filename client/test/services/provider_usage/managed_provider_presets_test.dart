import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/services/provider_usage/managed_provider_presets.dart';

void main() {
  test('built-in presets expose stable provider templates', () {
    expect(builtInManagedProviderPresets.map((preset) => preset.id), [
      'codex',
      'claude-code',
      'cursor',
      'codebuddy',
      'deepseek',
      'opencode-go',
      'qoder',
      'qoder-cn',
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
    expect(claude.template.endpointConfig.credentialSource, 'cli:claude');

    final cursor = managedProviderPresetById('cursor')!;
    expect(cursor.template.adapterId, 'http-json');
    expect(cursor.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(
      cursor.template.endpointConfig.url,
      'https://cursor.com/api/usage-summary',
    );
    expect(cursor.template.endpointConfig.credentialSource, 'cli:cursor');
    expect(
      cursor.template.endpointConfig.credentialTemplate,
      'WorkosCursorSessionToken={accountId}::{accessToken}',
    );

    final codebuddy = managedProviderPresetById('codebuddy')!;
    expect(codebuddy.template.name, 'CodeBuddy');
    expect(codebuddy.template.kind, ManagedProviderKind.apiBalance);
    expect(codebuddy.template.adapterId, 'codebuddy-credits');
    expect(codebuddy.template.endpointConfig.credentialSource, 'cli:codebuddy');
    expect(codebuddy.template.credentialRef, isNull);
  });

  test('DeepSeek preset is ready for an API key without containing one', () {
    final preset = managedProviderPresetById('deepseek')!;
    final endpoint = preset.template.endpointConfig;

    expect(preset.template.kind, ManagedProviderKind.apiBalance);
    expect(preset.template.adapterId, 'http-json');
    expect(endpoint.url, 'https://api.deepseek.com/user/balance');
    expect(endpoint.method, 'GET');
    expect(endpoint.windows, const [
      ManagedProviderUsageWindow(
        label: 'USD',
        remaining: r'$.balance_infos[0].total_balance',
      ),
      ManagedProviderUsageWindow(
        label: 'CNY',
        remaining: r'$.balance_infos[1].total_balance',
      ),
    ]);
    expect(endpoint.credentialName, 'Authorization');
    expect(endpoint.credentialField, 'apiKey');
    expect(endpoint.credentialPlacement, 'header');
    expect(endpoint.credentialPrefix, 'Bearer ');
    expect(preset.template.credentialRef, isNull);
  });

  test('Qoder presets are PAT-backed and region-specific', () {
    final global = managedProviderPresetById('qoder')!;
    expect(global.template.name, 'Qoder');
    expect(global.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(global.template.adapterId, 'qoder-usage');
    expect(
      global.template.endpointConfig.url,
      'https://openapi.qoder.sh/api/v2/quota/usage',
    );
    expect(global.template.endpointConfig.method, 'GET');
    expect(global.template.endpointConfig.credentialField, 'apiKey');
    expect(global.template.endpointConfig.credentialSource, 'secret');
    expect(global.template.displayConfig.unit, 'credits');
    expect(global.schema?.isFieldEditable('endpointConfig.url'), isTrue);
    expect(global.schema?.isFieldEditable('apiKey'), isTrue);
    expect(global.schema?.hasField('endpointConfig.windows'), isFalse);

    final cn = managedProviderPresetById('qoder-cn')!;
    expect(cn.template.name, 'Qoder CN');
    expect(
      cn.template.endpointConfig.url,
      'https://openapi.qoder.com.cn/api/v2/quota/usage',
    );
    expect(cn.template.adapterId, 'qoder-usage');
  });

  test('lookup returns null for unknown preset ids', () {
    expect(managedProviderPresetById('not-a-preset'), isNull);
  });

  test('OpenCode Go preset maps the Zen Go usage API without a key', () {
    final preset = managedProviderPresetById('opencode-go')!;
    final endpoint = preset.template.endpointConfig;

    expect(preset.template.name, 'OpenCode Go');
    expect(preset.template.kind, ManagedProviderKind.subscriptionQuota);
    expect(preset.template.adapterId, 'http-json');
    expect(endpoint.url, 'https://opencode.ai/zen/go/v1/usage');
    expect(endpoint.method, 'GET');
    expect(endpoint.credentialSource, 'secret');
    expect(endpoint.credentialName, 'Authorization');
    expect(endpoint.credentialField, 'apiKey');
    expect(endpoint.credentialPlacement, 'header');
    expect(endpoint.credentialPrefix, 'Bearer ');
    expect(preset.template.credentialRef, isNull);
    expect(endpoint.windows, const [
      ManagedProviderUsageWindow(
        label: '5h',
        used: r'$.usage.rolling.percent',
        resetsAt: r'$.usage.rolling.resetsAt',
        unit: '%',
      ),
      ManagedProviderUsageWindow(
        label: 'Weekly',
        used: r'$.usage.weekly.percent',
        resetsAt: r'$.usage.weekly.resetsAt',
        unit: '%',
      ),
      ManagedProviderUsageWindow(
        label: 'Monthly',
        used: r'$.usage.monthly.percent',
        resetsAt: r'$.usage.monthly.resetsAt',
        unit: '%',
      ),
    ]);
  });

  test('quick preset options include built-ins and custom', () {
    expect(managedProviderQuickPresetOptionIds, [
      'codex',
      'claude-code',
      'cursor',
      'codebuddy',
      'deepseek',
      'opencode-go',
      'qoder',
      'qoder-cn',
      kManagedProviderQuickPresetCustomId,
    ]);
  });

  test('every quick preset id has an English label and hint', () {
    final l10n = AppLocalizationsEn();
    for (final id in managedProviderQuickPresetOptionIds) {
      expect(l10n.managedProviderPresetLabel(id), isNotEmpty, reason: id);
      expect(l10n.managedProviderPresetHint(id), isNotEmpty, reason: id);
    }

    expect(l10n.managedProviderPresetLabel('qoder'), 'Qoder');
    expect(l10n.managedProviderPresetLabel('qoder-cn'), 'Qoder CN');
    expect(
      l10n.managedProviderPresetHint('qoder-cn'),
      contains('qoder.com.cn'),
    );
    expect(
      l10n.managedProviderPresetHint('qoder'),
      isNot(contains('qoder.com.cn')),
    );
  });
}
