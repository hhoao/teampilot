import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

import 'managed_provider.dart';

enum ManagedProviderEditorSection {
  basics,
  query,
  credentials,
  display,
  advanced,
}

enum ManagedProviderEditorFieldKind { text, secret, url, json, integer, toggle }

@immutable
class ManagedProviderEditorField extends Equatable {
  const ManagedProviderEditorField({
    required this.key,
    required this.kind,
    required this.required,
    this.defaultValue,
    this.readOnly = false,
  });

  final String key;
  final ManagedProviderEditorFieldKind kind;
  final bool required;
  final String? defaultValue;
  final bool readOnly;

  @override
  List<Object?> get props => [key, kind, required, defaultValue, readOnly];
}

@immutable
class ManagedProviderEditorSchema extends Equatable {
  const ManagedProviderEditorSchema({
    required this.sections,
    required this.fields,
    required this.firstQuery,
  });

  final Set<ManagedProviderEditorSection> sections;
  final List<ManagedProviderEditorField> fields;
  final bool firstQuery;

  bool hasSection(ManagedProviderEditorSection section) =>
      sections.contains(section);

  bool hasField(String key) => fields.any((field) => field.key == key);

  static ManagedProviderEditorSchema fromProvider(ManagedProvider provider) {
    final usesHttpEditor = _usesHttpEditor(provider);
    final hasQuery =
        usesHttpEditor || _hasEndpointDeclaration(provider.endpointConfig);
    final sections = <ManagedProviderEditorSection>{
      ManagedProviderEditorSection.basics,
      if (hasQuery) ManagedProviderEditorSection.query,
      ManagedProviderEditorSection.credentials,
      ManagedProviderEditorSection.display,
      ManagedProviderEditorSection.advanced,
    };
    final fields = <ManagedProviderEditorField>[
      ManagedProviderEditorField(
        key: 'name',
        kind: ManagedProviderEditorFieldKind.text,
        required: true,
        defaultValue: _defaultText(provider.name),
      ),
      ManagedProviderEditorField(
        key: 'kind',
        kind: ManagedProviderEditorFieldKind.text,
        required: true,
        defaultValue: provider.kind.value,
      ),
      ManagedProviderEditorField(
        key: 'adapterId',
        kind: ManagedProviderEditorFieldKind.text,
        required: true,
        defaultValue: _defaultText(provider.adapterId),
        readOnly: _isOfficialSubscriptionAdapter(provider.adapterId),
      ),
      if (hasQuery) ..._queryFields(provider.endpointConfig),
      ..._credentialFields(
        provider,
        exposeHttpCredentialMetadata: usesHttpEditor,
      ),
      ..._displayFields(provider.displayConfig),
      ManagedProviderEditorField(
        key: 'enabled',
        kind: ManagedProviderEditorFieldKind.toggle,
        required: false,
        defaultValue: provider.enabled.toString(),
      ),
    ];
    return ManagedProviderEditorSchema(
      sections: Set.unmodifiable(sections),
      fields: List.unmodifiable(fields),
      firstQuery: false,
    );
  }

  @override
  List<Object?> get props => [sections, fields, firstQuery];
}

List<ManagedProviderEditorField> _queryFields(
  ManagedProviderEndpointConfig endpoint,
) {
  final fields = <ManagedProviderEditorField>[
    ManagedProviderEditorField(
      key: 'endpointConfig.url',
      kind: ManagedProviderEditorFieldKind.url,
      required: true,
      defaultValue: _defaultText(endpoint.url),
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.method',
      kind: ManagedProviderEditorFieldKind.text,
      required: true,
      defaultValue: _defaultText(endpoint.method),
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.responsePath',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: _defaultText(endpoint.responsePath),
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.measuresPath',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: _defaultText(endpoint.measuresPath),
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.body',
      kind: ManagedProviderEditorFieldKind.json,
      required: false,
      defaultValue: _defaultJson(endpoint.body),
    ),
    ManagedProviderEditorField(
      key: 'endpointConfig.fieldMappings',
      kind: ManagedProviderEditorFieldKind.json,
      required: false,
      defaultValue: _defaultJson(endpoint.fieldMappings),
    ),
  ];
  for (final entry in endpoint.fieldMappings.entries) {
    final value = entry.value;
    if (value is String) {
      fields.add(
        ManagedProviderEditorField(
          key: 'endpointConfig.fieldMappings.${entry.key}',
          kind: ManagedProviderEditorFieldKind.text,
          required: false,
          defaultValue: value,
        ),
      );
    }
  }
  return fields;
}

List<ManagedProviderEditorField> _credentialFields(
  ManagedProvider provider, {
  required bool exposeHttpCredentialMetadata,
}) {
  final endpoint = provider.endpointConfig;
  final fields = <ManagedProviderEditorField>[
    ManagedProviderEditorField(
      key: 'credentialRef',
      kind: ManagedProviderEditorFieldKind.text,
      required: false,
      defaultValue: _defaultText(provider.credentialRef),
    ),
  ];
  final includeSecretField =
      endpoint.credentialField != null && endpoint.credentialField!.isNotEmpty;
  if (includeSecretField) {
    fields.add(
      ManagedProviderEditorField(
        key: endpoint.credentialField!,
        kind: ManagedProviderEditorFieldKind.secret,
        required: true,
      ),
    );
  }
  final includeAllMetadata = exposeHttpCredentialMetadata;
  if (includeAllMetadata ||
      endpoint.credentialName != null && endpoint.credentialName!.isNotEmpty) {
    fields.add(
      ManagedProviderEditorField(
        key: 'endpointConfig.credentialName',
        kind: ManagedProviderEditorFieldKind.text,
        required: false,
        defaultValue: _defaultText(endpoint.credentialName),
      ),
    );
  }
  if (includeAllMetadata || includeSecretField) {
    fields.add(
      ManagedProviderEditorField(
        key: 'endpointConfig.credentialField',
        kind: ManagedProviderEditorFieldKind.text,
        required: false,
        defaultValue: _defaultText(endpoint.credentialField),
      ),
    );
  }
  if (includeAllMetadata || endpoint.credentialPlacement != 'header') {
    fields.add(
      ManagedProviderEditorField(
        key: 'endpointConfig.credentialPlacement',
        kind: ManagedProviderEditorFieldKind.text,
        required: false,
        defaultValue: _defaultText(endpoint.credentialPlacement),
      ),
    );
  }
  if (includeAllMetadata ||
      endpoint.credentialPrefix != null &&
          endpoint.credentialPrefix!.isNotEmpty) {
    fields.add(
      ManagedProviderEditorField(
        key: 'endpointConfig.credentialPrefix',
        kind: ManagedProviderEditorFieldKind.text,
        required: false,
        defaultValue: _defaultText(endpoint.credentialPrefix),
      ),
    );
  }
  return fields;
}

List<ManagedProviderEditorField> _displayFields(
  ManagedProviderDisplayConfig display,
) => [
  ManagedProviderEditorField(
    key: 'displayConfig.currency',
    kind: ManagedProviderEditorFieldKind.text,
    required: false,
    defaultValue: _defaultText(display.currency),
  ),
  ManagedProviderEditorField(
    key: 'displayConfig.unit',
    kind: ManagedProviderEditorFieldKind.text,
    required: false,
    defaultValue: _defaultText(display.unit),
  ),
  ManagedProviderEditorField(
    key: 'displayConfig.decimalPlaces',
    kind: ManagedProviderEditorFieldKind.integer,
    required: false,
    defaultValue: display.decimalPlaces?.toString(),
  ),
  ManagedProviderEditorField(
    key: 'displayConfig.showPercent',
    kind: ManagedProviderEditorFieldKind.toggle,
    required: false,
    defaultValue: display.showPercent.toString(),
  ),
];

bool _usesHttpEditor(ManagedProvider provider) =>
    provider.adapterId == 'http-json' ||
    provider.kind == ManagedProviderKind.customHttp;

bool _isOfficialSubscriptionAdapter(String adapterId) =>
    adapterId == 'official-codex-subscription' ||
    adapterId == 'official-claude-subscription';

bool _hasEndpointDeclaration(ManagedProviderEndpointConfig endpoint) =>
    endpoint.url.isNotEmpty ||
    endpoint.method.toUpperCase() != 'GET' ||
    endpoint.responsePath != null && endpoint.responsePath!.isNotEmpty ||
    endpoint.measuresPath != null && endpoint.measuresPath!.isNotEmpty ||
    endpoint.body.isNotEmpty ||
    endpoint.fieldMappings.isNotEmpty;

String? _defaultText(String? value) =>
    value == null || value.isEmpty ? null : value;

String? _defaultJson(Map<String, Object?> value) =>
    value.isEmpty ? null : jsonEncode(value);
