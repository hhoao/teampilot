import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

import '../../models/managed_provider.dart';
import '../../models/managed_provider_editor_schema.dart';

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
      key: 'endpointConfig.measuresPath',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: r'$.balance_infos',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.body',
      kind: ManagedProviderEditorFieldKind.json,
      required: false,
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.fieldMappings',
      kind: ManagedProviderEditorFieldKind.json,
      required: false,
      defaultValue:
          r'{"label":"$.currency","remaining":"$.total_balance","currency":"$.currency"}',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.fieldMappings.label',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: r'$.currency',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.fieldMappings.remaining',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: r'$.total_balance',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.fieldMappings.currency',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: r'$.currency',
    ),
    ManagedProviderEditorField(
      key: 'apiKey',
      kind: ManagedProviderEditorFieldKind.secret,
      required: true,
    ),
    ManagedProviderEditorField(
      key: 'credentialRef',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.credentialName',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'Authorization',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.credentialField',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'apiKey',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.credentialPlacement',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'header',
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.credentialPrefix',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: 'Bearer ',
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
          adapterId: 'official-codex-subscription',
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
          adapterId: 'official-claude-subscription',
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
            measuresPath: r'$.balance_infos',
            fieldMappings: {
              'label': r'$.currency',
              'remaining': r'$.total_balance',
              'currency': r'$.currency',
            },
            credentialName: 'Authorization',
            credentialField: 'apiKey',
            credentialPlacement: 'header',
            credentialPrefix: 'Bearer ',
          ),
          displayConfig: ManagedProviderDisplayConfig(decimalPlaces: 2),
        ),
        schema: _deepSeekEditorSchema,
      ),
      ManagedProviderPreset(
        id: 'opencode',
        labelId: 'opencode',
        hintId: 'opencode',
        template: ManagedProvider(
          id: '',
          name: 'OpenCode',
          kind: ManagedProviderKind.customHttp,
          adapterId: 'http-json',
        ),
      ),
    ]);

ManagedProviderPreset? managedProviderPresetById(String id) {
  for (final preset in builtInManagedProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
