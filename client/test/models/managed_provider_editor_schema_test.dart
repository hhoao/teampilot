import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/managed_provider_editor_schema.dart';
import 'package:teampilot/services/provider_usage/managed_provider_presets.dart';

void main() {
  ManagedProviderEditorField field(
    ManagedProviderEditorSchema schema,
    String key,
  ) => schema.fields.singleWhere((field) => field.key == key);

  test('DeepSeek preset declares api key dynamic currency and first query', () {
    final preset = managedProviderPresetById('deepseek')!;
    final schema = preset.schema!;

    expect(schema.firstQuery, isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.basics), isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.query), isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.credentials), isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.display), isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.advanced), isTrue);

    expect(field(schema, 'apiKey').kind, ManagedProviderEditorFieldKind.secret);
    expect(field(schema, 'apiKey').required, isTrue);
    expect(field(schema, 'kind').readOnly, isTrue);
    expect(
      field(schema, 'endpointConfig.fieldMappings.currency').defaultValue,
      r'$.currency',
    );
    expect(
      field(schema, 'displayConfig.decimalPlaces').kind,
      ManagedProviderEditorFieldKind.integer,
    );
    expect(field(schema, 'displayConfig.decimalPlaces').defaultValue, '2');
  });

  test('custom HTTP provider exposes query mapping and editable settings', () {
    final schema = ManagedProviderEditorSchema.fromProvider(
      ManagedProvider(
        id: 'p1',
        name: 'Custom',
        kind: ManagedProviderKind.customHttp,
        adapterId: 'http-json',
      ),
    );

    expect(schema.firstQuery, isFalse);
    expect(schema.hasSection(ManagedProviderEditorSection.basics), isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.query), isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.credentials), isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.display), isTrue);
    expect(schema.hasSection(ManagedProviderEditorSection.advanced), isTrue);
    expect(
      field(schema, 'endpointConfig.url').kind,
      ManagedProviderEditorFieldKind.url,
    );
    expect(field(schema, 'endpointConfig.url').required, isTrue);
    expect(
      field(schema, 'endpointConfig.body').kind,
      ManagedProviderEditorFieldKind.json,
    );
    expect(
      field(schema, 'endpointConfig.fieldMappings').kind,
      ManagedProviderEditorFieldKind.json,
    );
    expect(field(schema, 'adapterId').readOnly, isFalse);
    expect(field(schema, 'kind').readOnly, isFalse);
  });

  test(
    'legacy providers derive compatibility from kind adapter and endpoint',
    () {
      final official = ManagedProviderEditorSchema.fromProvider(
        ManagedProvider(
          id: 'codex',
          name: 'Codex',
          kind: ManagedProviderKind.subscriptionQuota,
          adapterId: 'official-codex-subscription',
        ),
      );

      expect(official.hasSection(ManagedProviderEditorSection.basics), isTrue);
      expect(official.hasSection(ManagedProviderEditorSection.query), isFalse);
      expect(
        official.hasSection(ManagedProviderEditorSection.credentials),
        isTrue,
      );
      expect(official.hasSection(ManagedProviderEditorSection.display), isTrue);
      expect(
        official.hasSection(ManagedProviderEditorSection.advanced),
        isTrue,
      );
      expect(official.hasField('endpointConfig.url'), isFalse);
      expect(field(official, 'kind').readOnly, isTrue);

      final legacyHttp = ManagedProviderEditorSchema.fromProvider(
        ManagedProvider(
          id: 'legacy',
          name: 'Legacy HTTP',
          kind: ManagedProviderKind.apiBalance,
          adapterId: 'legacy-adapter',
          endpointConfig: ManagedProviderEndpointConfig(
            url: 'https://legacy.example.test/usage',
            responsePath: r'$.data',
            measuresPath: r'$.data.balance',
          ),
        ),
      );

      expect(legacyHttp.hasSection(ManagedProviderEditorSection.query), isTrue);
      expect(legacyHttp.hasField('endpointConfig.url'), isTrue);
    },
  );

  test('derived schema preserves credential reference default value', () {
    final schema = ManagedProviderEditorSchema.fromProvider(
      ManagedProvider(
        id: 'p1',
        name: 'Custom',
        kind: ManagedProviderKind.customHttp,
        adapterId: 'http-json',
        credentialRef: 'managed-provider:p1',
      ),
    );

    expect(field(schema, 'credentialRef').defaultValue, 'managed-provider:p1');
  });

  test('official subscriptions hide default HTTP credential metadata', () {
    final official = ManagedProviderEditorSchema.fromProvider(
      ManagedProvider(
        id: 'codex',
        name: 'Codex',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'official-codex-subscription',
        credentialRef: 'managed-provider:codex',
      ),
    );

    expect(
      field(official, 'credentialRef').defaultValue,
      'managed-provider:codex',
    );
    expect(official.hasField('endpointConfig.credentialName'), isFalse);
    expect(official.hasField('endpointConfig.credentialField'), isFalse);
    expect(official.hasField('endpointConfig.credentialPlacement'), isFalse);
    expect(official.hasField('endpointConfig.credentialPrefix'), isFalse);

    final legacyOfficial = ManagedProviderEditorSchema.fromProvider(
      ManagedProvider(
        id: 'claude',
        name: 'Claude',
        kind: ManagedProviderKind.subscriptionQuota,
        adapterId: 'official-claude-subscription',
        endpointConfig: ManagedProviderEndpointConfig(
          credentialName: 'Authorization',
          credentialField: 'apiKey',
          credentialPlacement: 'query',
          credentialPrefix: 'Bearer ',
        ),
      ),
    );

    expect(
      field(legacyOfficial, 'endpointConfig.credentialName').defaultValue,
      'Authorization',
    );
    expect(
      field(legacyOfficial, 'endpointConfig.credentialField').defaultValue,
      'apiKey',
    );
    expect(
      field(legacyOfficial, 'endpointConfig.credentialPlacement').defaultValue,
      'query',
    );
    expect(
      field(legacyOfficial, 'endpointConfig.credentialPrefix').defaultValue,
      'Bearer ',
    );
  });
}
