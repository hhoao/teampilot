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
      field(schema, 'endpointConfig.windows').defaultValue,
      contains(r'$.balance_infos[0].total_balance'),
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
      field(schema, 'endpointConfig.windows').kind,
      ManagedProviderEditorFieldKind.json,
    );
    expect(field(schema, 'adapterId').readOnly, isFalse);
    expect(field(schema, 'kind').readOnly, isFalse);
  });

  test(
    'http-json subscription presets expose query and cli credential fields',
    () {
      final codex = ManagedProviderEditorSchema.fromProvider(
        managedProviderPresetById('codex')!.template,
      );

      expect(codex.hasSection(ManagedProviderEditorSection.query), isTrue);
      expect(codex.hasField('endpointConfig.url'), isTrue);
      expect(codex.hasField('endpointConfig.headers'), isTrue);
      expect(codex.hasField('endpointConfig.windows'), isTrue);
      expect(
        field(codex, 'endpointConfig.credentialSource').defaultValue,
        'cli:codex',
      );
      expect(
        codex.fields.any(
          (candidate) => candidate.kind == ManagedProviderEditorFieldKind.secret,
        ),
        isFalse,
      );

      final cursor = ManagedProviderEditorSchema.fromProvider(
        managedProviderPresetById('cursor')!.template,
      );
      expect(
        field(cursor, 'endpointConfig.credentialTemplate').defaultValue,
        'WorkosCursorSessionToken={accountId}::{accessToken}',
      );
      expect(
        field(cursor, 'endpointConfig.credentialSource').defaultValue,
        'cli:cursor',
      );
    },
  );

  test('legacy HTTP providers derive compatibility from endpoint declaration', () {
    final legacyHttp = ManagedProviderEditorSchema.fromProvider(
      ManagedProvider(
        id: 'legacy',
        name: 'Legacy HTTP',
        kind: ManagedProviderKind.apiBalance,
        adapterId: 'legacy-adapter',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://legacy.example.test/usage',
          responsePath: r'$.data',
          windows: const [
            ManagedProviderUsageWindow(
              label: 'Balance',
              remaining: r'$.data.balance',
            ),
          ],
        ),
      ),
    );

    expect(legacyHttp.hasSection(ManagedProviderEditorSection.query), isTrue);
    expect(legacyHttp.hasField('endpointConfig.url'), isTrue);
  });

  test('derived schema omits internal credential reference field', () {
    final schema = ManagedProviderEditorSchema.fromProvider(
      ManagedProvider(
        id: 'p1',
        name: 'Custom',
        kind: ManagedProviderKind.customHttp,
        adapterId: 'http-json',
        credentialRef: 'managed-provider:p1',
      ),
    );

    expect(schema.hasField('credentialRef'), isFalse);
  });

  test('http-json presets expose credential metadata for manual providers', () {
    final manual = ManagedProviderEditorSchema.fromProvider(
      ManagedProvider(
        id: 'custom-codex',
        name: 'Custom Codex',
        kind: ManagedProviderKind.customHttp,
        adapterId: 'http-json',
        credentialRef: 'managed-provider:custom-codex',
        endpointConfig: ManagedProviderEndpointConfig(
          url: 'https://chatgpt.com/backend-api/wham/usage',
          credentialName: 'Authorization',
          credentialField: 'accessToken',
          credentialPlacement: 'header',
          credentialPrefix: 'Bearer ',
        ),
      ),
    );

    expect(
      field(manual, 'endpointConfig.credentialName').defaultValue,
      'Authorization',
    );
    expect(field(manual, 'endpointConfig.credentialField').defaultValue, 'accessToken');
    expect(field(manual, 'endpointConfig.credentialPlacement').defaultValue, 'header');
    expect(field(manual, 'endpointConfig.credentialPrefix').defaultValue, 'Bearer ');
  });
}
