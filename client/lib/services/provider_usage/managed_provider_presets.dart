import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

import '../../models/managed_provider.dart';
import '../../models/managed_provider_editor_schema.dart';

/// Dropdown sentinel for the blank custom HTTP template (not persisted).
const kManagedProviderQuickPresetCustomId = '__custom__';

@immutable
class ManagedProviderPreset extends Equatable {
  const ManagedProviderPreset({
    required this.id,
    required this.labelId,
    required this.hintId,
    required this.template,
    this.schema,
  });

  final String id;
  final String labelId;
  final String hintId;
  final ManagedProvider template;
  final ManagedProviderEditorSchema? schema;

  @override
  List<Object?> get props => [id, labelId, hintId, template, schema];
}

const _deepSeekEditorSchema = ManagedProviderEditorSchema(
  sections: {
    ManagedProviderEditorSection.basics,
    ManagedProviderEditorSection.query,
    ManagedProviderEditorSection.credentials,
    ManagedProviderEditorSection.display,
    ManagedProviderEditorSection.advanced,
  },
  fields: [
    ManagedProviderEditorField(
      key: 'name',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: 'DeepSeek',
    ),
    ManagedProviderEditorField(
      key: 'kind',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: 'apiBalance',
      readOnly: true,
    ),
    ManagedProviderEditorField(
      key: 'adapterId',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: 'http-json',
      readOnly: true,
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.url',
      kind: ManagedProviderEditorFieldKind.url,
      required: true,
      defaultValue: 'https://api.deepseek.com/user/balance',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.method',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: 'GET',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.windows',
      kind: ManagedProviderEditorFieldKind.json,
      required: false,
      defaultValue:
          r'''[
  {
    "label": "USD",
    "remaining": "$.balance_infos[0].total_balance"
  },
  {
    "label": "CNY",
    "remaining": "$.balance_infos[1].total_balance"
  }
]''',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.body',
      kind: ManagedProviderEditorFieldKind.json,
      required: false,
    ),
    ManagedProviderEditorField(
      key: 'apiKey',
      kind: ManagedProviderEditorFieldKind.secret,
      required: true,
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.credentialName',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'Authorization',
      readOnly: true,
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.credentialField',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'apiKey',
      readOnly: true,
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.credentialPlacement',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'header',
      readOnly: true,
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.credentialPrefix',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'Bearer ',
      readOnly: true,
    ),
    ManagedProviderEditorField(
      key: 'displayConfig.currency',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
    ),
    ManagedProviderEditorField(
      key: 'displayConfig.unit',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
    ),
    ManagedProviderEditorField(
      key: 'displayConfig.decimalPlaces',
      kind: ManagedProviderEditorFieldKind.integer,
      required: false,
      defaultValue: '2',
    ),
    ManagedProviderEditorField(
      key: 'displayConfig.showPercent',
      kind: ManagedProviderEditorFieldKind.toggle,
      required: false,
      defaultValue: 'false',
    ),
    ManagedProviderEditorField(
      key: 'enabled',
      kind: ManagedProviderEditorFieldKind.toggle,
      required: false,
      defaultValue: 'true',
    ),
  ],
  firstQuery: true,
);

final List<ManagedProviderPreset> builtInManagedProviderPresets =
    List.unmodifiable([
      ManagedProviderPreset(
        id: 'codex',
        labelId: 'codex',
        hintId: 'codex',
        template: ManagedProvider(
          id: '',
          name: 'Codex',
          kind: ManagedProviderKind.subscriptionQuota,
          adapterId: 'http-json',
          endpointConfig: ManagedProviderEndpointConfig(
            url: 'https://chatgpt.com/backend-api/wham/usage',
            credentialSource: 'cli:openai-official',
            credentialField: 'accessToken',
            credentialName: 'Authorization',
            credentialPrefix: 'Bearer ',
            headers: {
              'User-Agent': 'codex-cli',
              'Accept': 'application/json',
              'ChatGPT-Account-Id': '{accountId}',
            },
            windows: const [
              ManagedProviderUsageWindow(
                label: '5h',
                used: r'$.rate_limit.primary_window.used_percent',
                resetsAt: r'$.rate_limit.primary_window.reset_at',
                unit: '%',
              ),
              ManagedProviderUsageWindow(
                label: 'Weekly',
                used: r'$.rate_limit.secondary_window.used_percent',
                resetsAt: r'$.rate_limit.secondary_window.reset_at',
                unit: '%',
              ),
              ManagedProviderUsageWindow(
                label: 'Monthly',
                used: r'$.spend_control.individual_limit.used_percent',
                resetsAt: r'$.spend_control.individual_limit.reset_at',
                unit: '%',
              ),
            ],
          ),
        ),
      ),
      ManagedProviderPreset(
        id: 'claude-code',
        labelId: 'claude-code',
        hintId: 'claude-code',
        template: ManagedProvider(
          id: '',
          name: 'Claude Code',
          kind: ManagedProviderKind.subscriptionQuota,
          adapterId: 'http-json',
          endpointConfig: ManagedProviderEndpointConfig(
            url: 'https://api.anthropic.com/api/oauth/usage',
            credentialSource: 'cli:claude-official',
            credentialField: 'accessToken',
            credentialName: 'Authorization',
            credentialPrefix: 'Bearer ',
            headers: {
              'anthropic-beta': 'oauth-2025-04-20',
              'Accept': 'application/json',
              'User-Agent': 'claude-code/2.1.0',
            },
            windows: const [
              ManagedProviderUsageWindow(
                label: '5h',
                used: r'$.five_hour.utilization',
                resetsAt: r'$.five_hour.resets_at',
                unit: '%',
              ),
              ManagedProviderUsageWindow(
                label: 'Weekly',
                used: r'$.seven_day.utilization',
                resetsAt: r'$.seven_day.resets_at',
                unit: '%',
              ),
              ManagedProviderUsageWindow(
                label: 'Weekly Opus',
                used: r'$.seven_day_opus.utilization',
                resetsAt: r'$.seven_day_opus.resets_at',
                unit: '%',
              ),
              ManagedProviderUsageWindow(
                label: 'Weekly Sonnet',
                used: r'$.seven_day_sonnet.utilization',
                resetsAt: r'$.seven_day_sonnet.resets_at',
                unit: '%',
              ),
            ],
          ),
        ),
      ),
      ManagedProviderPreset(
        id: 'cursor',
        labelId: 'cursor',
        hintId: 'cursor',
        template: ManagedProvider(
          id: '',
          name: 'Cursor',
          kind: ManagedProviderKind.subscriptionQuota,
          adapterId: 'http-json',
          endpointConfig: ManagedProviderEndpointConfig(
            url: 'https://cursor.com/api/usage-summary',
            credentialSource: 'cli:cursor-account',
            credentialName: 'Cookie',
            credentialTemplate:
                'WorkosCursorSessionToken={accountId}::{accessToken}',
            headers: {
              'Accept': 'application/json',
              'Origin': 'https://cursor.com',
              'Referer': 'https://cursor.com/dashboard',
            },
            windows: const [
              ManagedProviderUsageWindow(
                label: 'Plan',
                used: r'$.individualUsage.plan.totalPercentUsed',
                unit: '%',
                resetsAt: r'$.billingCycleEnd',
              ),
              ManagedProviderUsageWindow(
                label: 'Auto',
                used: r'$.individualUsage.plan.autoPercentUsed',
                unit: '%',
              ),
              ManagedProviderUsageWindow(
                label: 'API',
                used: r'$.individualUsage.plan.apiPercentUsed',
                unit: '%',
              ),
              ManagedProviderUsageWindow(
                label: 'On-demand',
                used: r'$.individualUsage.onDemand.used',
                total: r'$.individualUsage.onDemand.limit',
              ),
              ManagedProviderUsageWindow(
                label: 'Team',
                used: r'$.teamUsage.pooled.used',
                total: r'$.teamUsage.pooled.limit',
                resetsAt: r'$.billingCycleEnd',
              ),
            ],
          ),
        ),
      ),
      ManagedProviderPreset(
        id: 'deepseek',
        labelId: 'deepseek',
        hintId: 'deepseek',
        template: ManagedProvider(
          id: '',
          name: 'DeepSeek',
          kind: ManagedProviderKind.apiBalance,
          adapterId: 'http-json',
          endpointConfig: ManagedProviderEndpointConfig(
            url: 'https://api.deepseek.com/user/balance',
            method: 'GET',
            windows: const [
              ManagedProviderUsageWindow(
                label: 'USD',
                remaining: r'$.balance_infos[0].total_balance',
              ),
              ManagedProviderUsageWindow(
                label: 'CNY',
                remaining: r'$.balance_infos[1].total_balance',
              ),
            ],
            credentialName: 'Authorization',
            credentialField: 'apiKey',
            credentialPlacement: 'header',
            credentialPrefix: 'Bearer ',
          ),
          displayConfig: ManagedProviderDisplayConfig(decimalPlaces: 2),
        ),
        schema: _deepSeekEditorSchema,
      ),
    ]);

final List<String> managedProviderQuickPresetOptionIds = List.unmodifiable([
  ...builtInManagedProviderPresets.map((preset) => preset.id),
  kManagedProviderQuickPresetCustomId,
]);

ManagedProviderPreset? managedProviderPresetById(String id) {
  for (final preset in builtInManagedProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
