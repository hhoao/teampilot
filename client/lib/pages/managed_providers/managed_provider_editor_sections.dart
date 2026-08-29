import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/managed_provider_editor_schema.dart';
import '../../services/provider_usage/managed_provider_presets.dart';
import 'managed_provider_editor_validation.dart';

class ManagedProviderBasicsSection extends StatelessWidget {
  const ManagedProviderBasicsSection({
    required this.schema,
    required this.showPresetSelector,
    required this.selectedPreset,
    required this.nameController,
    required this.credentialSecretController,
    required this.credentialConfigured,
    required this.enabled,
    required this.onPresetChanged,
    required this.onEnabledChanged,
    this.credentialSecretFocusNode,
    super.key,
  });

  final ManagedProviderEditorSchema schema;
  final bool showPresetSelector;
  final ManagedProviderPreset? selectedPreset;
  final TextEditingController nameController;
  final TextEditingController credentialSecretController;
  final FocusNode? credentialSecretFocusNode;
  final bool credentialConfigured;
  final bool enabled;
  final ValueChanged<ManagedProviderPreset> onPresetChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showPresetSelector) ...[
          _LabeledControl(
            label: l10n.managedProvidersQuickPresetTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpSelect<ManagedProviderPreset>(
                  key: const Key('managed-provider-quick-preset'),
                  items: builtInManagedProviderPresets,
                  initialItem: selectedPreset,
                  itemLabel: (preset) =>
                      l10n.managedProviderPresetLabel(preset.labelId),
                  listItemKey: (preset) =>
                      Key('managed-provider-quick-preset-${preset.id}'),
                  onChanged: (preset) {
                    if (preset != null) onPresetChanged(preset);
                  },
                  decoration: TpSelectDecorations.themed(context),
                  searchMinItems: 0,
                ),
                const SizedBox(height: 6),
                Text(
                  selectedPreset == null
                      ? l10n.managedProvidersQuickPresetHint
                      : l10n.managedProviderPresetHint(selectedPreset!.hintId),
                  style: TpTextStyles.of(
                    context,
                  ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          l10n.managedProvidersBasicsSummary,
          style: TpTextStyles.of(
            context,
          ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (schema.hasField('name'))
          TpInputFormField(
            key: const Key('managed-provider-name'),
            label: Text(l10n.managedProvidersName),
            controller: nameController,
            decoration: InputDecoration(hintText: l10n.managedProvidersNameHint),
            validator: (value) =>
                (value == null || value.trim().isEmpty)
                    ? context.l10n.formFieldRequired
                    : null,
          ),
        if (schema.hasField('enabled'))
          SwitchListTile.adaptive(
            key: const Key('managed-provider-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.managedProvidersEnabledTitle,
              style: TpTextStyles.of(context).md,
            ),
            subtitle: Text(
              l10n.managedProvidersEnabledSubtitle,
              style: TpTextStyles.of(context).mutedSm,
            ),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
        if (_hasRequiredSecret(schema)) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-secret'),
            label: l10n.managedProvidersCredentialSecret,
            controller: credentialSecretController,
            focusNode: credentialSecretFocusNode,
            hint: credentialConfigured
                ? l10n.managedProvidersCredentialSecretExistingHint
                : l10n.managedProvidersCredentialSecretHint,
            obscureText: true,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.managedProvidersCredentialSecretHelper,
            style: TpTextStyles.of(
              context,
            ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class ManagedProviderQuerySection extends StatelessWidget {
  const ManagedProviderQuerySection({
    required this.schema,
    required this.endpointController,
    required this.method,
    required this.responsePathController,
    required this.measuresPathController,
    required this.requestMappingController,
    required this.fieldMappingsController,
    required this.headersController,
    required this.windowsController,
    required this.onMethodChanged,
    this.strictEndpointResolver = _defaultStrictEndpointResolver,
    super.key,
  });

  static bool _defaultStrictEndpointResolver() => false;

  final ManagedProviderEditorSchema schema;
  final TextEditingController endpointController;
  final String method;
  final TextEditingController responsePathController;
  final TextEditingController measuresPathController;
  final TextEditingController requestMappingController;
  final TextEditingController fieldMappingsController;
  final TextEditingController headersController;
  final TextEditingController windowsController;
  final ValueChanged<String> onMethodChanged;

  /// Evaluated inside the endpoint validator so the freshness of the adapter
  /// / kind inputs is captured at validate time, not at build time.
  final bool Function() strictEndpointResolver;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (schema.hasField('endpointConfig.url'))
          TpInputFormField(
            key: const Key('managed-provider-endpoint'),
            label: Text(l10n.managedProvidersEndpoint),
            controller: endpointController,
            decoration: InputDecoration(
              hintText: l10n.managedProvidersEndpointHint,
            ),
            keyboardType: TextInputType.url,
            validator: (value) =>
                isAllowedManagedProviderEndpoint(
                  value ?? '',
                  allowHttpLocalhost: strictEndpointResolver(),
                )
                ? null
                : context.l10n.managedProvidersEndpointError,
          ),
        if (schema.hasField('endpointConfig.method')) ...[
          const SizedBox(height: 12),
          _LabeledControl(
            label: l10n.managedProvidersMethod,
            child: TpSelect<String>(
              key: const Key('managed-provider-method'),
              items: const ['GET', 'POST'],
              initialItem: method,
              itemLabel: (method) => method,
              onChanged: (value) {
                if (value != null) onMethodChanged(value);
              },
              decoration: TpSelectDecorations.themed(context),
              searchable: false,
            ),
          ),
        ],
        if (schema.hasField('endpointConfig.responsePath')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-response-path'),
            label: l10n.managedProvidersResponsePath,
            controller: responsePathController,
            hint: r'$.data',
          ),
        ],
        if (schema.hasField('endpointConfig.measuresPath')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-measures-path'),
            label: l10n.managedProvidersMeasuresPath,
            controller: measuresPathController,
            hint: r'$.data.measures',
          ),
        ],
        if (schema.hasField('endpointConfig.body')) ...[
          const SizedBox(height: 12),
          TpTextareaFormField(
            key: const Key('managed-provider-request-mapping'),
            label: Text(l10n.managedProvidersRequestMapping),
            controller: requestMappingController,
            minHeight: 90,
            maxHeight: 180,
            decoration: const InputDecoration(hintText: '{"region": "us"}'),
            validator: (value) {
              final parsed = decodeJsonObject(value ?? '');
              if (parsed == null || mappingContainsCredentialKey(parsed)) {
                return context.l10n.managedProvidersRequestMappingError;
              }
              return null;
            },
          ),
        ],
        if (schema.hasField('endpointConfig.fieldMappings')) ...[
          const SizedBox(height: 12),
          TpTextareaFormField(
            key: const Key('managed-provider-field-mappings'),
            label: Text(l10n.managedProvidersFieldMappings),
            controller: fieldMappingsController,
            minHeight: 90,
            maxHeight: 180,
            decoration: const InputDecoration(hintText: '{"region": "us"}'),
            validator: (value) {
              final parsed = decodeJsonObject(value ?? '');
              if (parsed == null || mappingContainsCredentialKey(parsed)) {
                return context.l10n.managedProvidersFieldMappingError;
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          Text(
            schema.hasField('endpointConfig.fieldMappings.currency')
                ? l10n.managedProvidersDynamicCurrencyHelper
                : l10n.managedProvidersCurrencyMappingHelper,
            style: TpTextStyles.of(
              context,
            ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
        if (schema.hasField('endpointConfig.headers')) ...[
          const SizedBox(height: 12),
          TpTextareaFormField(
            key: const Key('managed-provider-headers'),
            label: const Text('Headers'),
            controller: headersController,
            minHeight: 90,
            maxHeight: 180,
            decoration: const InputDecoration(hintText: '{"Accept": "application/json"}'),
            validator: (value) {
              final parsed = decodeJsonObject(value ?? '');
              if (parsed == null || mappingContainsCredentialKey(parsed)) {
                return context.l10n.managedProvidersRequestMappingError;
              }
              return null;
            },
          ),
        ],
        if (schema.hasField('endpointConfig.windows')) ...[
          const SizedBox(height: 12),
          TpTextareaFormField(
            key: const Key('managed-provider-windows'),
            label: const Text('Windows'),
            controller: windowsController,
            minHeight: 120,
            maxHeight: 220,
            decoration: InputDecoration(
              hintText: r'[{"label":"Plan","used":"$.plan.used","unit":"%"}]',
            ),
          ),
        ],
      ],
    );
  }
}

class ManagedProviderCredentialsSection extends StatelessWidget {
  const ManagedProviderCredentialsSection({
    required this.schema,
    required this.credentialNameController,
    required this.credentialFieldController,
    required this.credentialPlacementController,
    required this.credentialSourceController,
    required this.credentialTemplateController,
    required this.credentialConfigured,
    this.onCredentialFieldChanged,
    super.key,
  });

  final ManagedProviderEditorSchema schema;
  final TextEditingController credentialNameController;
  final TextEditingController credentialFieldController;
  final TextEditingController credentialPlacementController;
  final TextEditingController credentialSourceController;
  final TextEditingController credentialTemplateController;
  final bool credentialConfigured;
  final ValueChanged<String>? onCredentialFieldChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasMetadata =
        schema.hasField('endpointConfig.credentialName') ||
        schema.hasField('endpointConfig.credentialField') ||
        schema.hasField('endpointConfig.credentialPlacement') ||
        schema.hasField('endpointConfig.credentialSource') ||
        schema.hasField('endpointConfig.credentialTemplate');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          credentialConfigured
              ? l10n.managedProvidersCredentialConfigured
              : l10n.managedProvidersCredentialNone,
          style: TpTextStyles.of(
            context,
          ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (hasMetadata) const SizedBox(height: 12),
        if (schema.hasField('endpointConfig.credentialName'))
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-name'),
            label: l10n.managedProvidersCredentialName,
            controller: credentialNameController,
            hint: l10n.managedProvidersCredentialNameHint,
          ),
        if (schema.hasField('endpointConfig.credentialField')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-field'),
            label: l10n.managedProvidersCredentialField,
            controller: credentialFieldController,
            hint: l10n.managedProvidersCredentialFieldHint,
            onChanged: onCredentialFieldChanged,
          ),
        ],
        if (schema.hasField('endpointConfig.credentialPlacement')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-placement'),
            label: l10n.managedProvidersCredentialPlacement,
            controller: credentialPlacementController,
            hint: l10n.managedProvidersCredentialPlacementHint,
          ),
        ],
        if (schema.hasField('endpointConfig.credentialSource')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-source'),
            label: 'Credential source',
            controller: credentialSourceController,
            hint: 'secret or cli:cursor-account',
          ),
        ],
        if (schema.hasField('endpointConfig.credentialTemplate')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-template'),
            label: 'Credential template',
            controller: credentialTemplateController,
          ),
        ],
      ],
    );
  }
}

class ManagedProviderDisplaySection extends StatelessWidget {
  const ManagedProviderDisplaySection({
    required this.schema,
    required this.currencyController,
    required this.unitController,
    required this.decimalPlacesController,
    required this.showPercent,
    required this.onShowPercentChanged,
    super.key,
  });

  final ManagedProviderEditorSchema schema;
  final TextEditingController currencyController;
  final TextEditingController unitController;
  final TextEditingController decimalPlacesController;
  final bool showPercent;
  final ValueChanged<bool> onShowPercentChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = <Widget>[
              if (schema.hasField('displayConfig.currency'))
                _ManagedProviderTextField(
                  fieldKey: const Key('managed-provider-currency'),
                  label: l10n.managedProvidersCurrency,
                  controller: currencyController,
                  hint: 'USD',
                ),
              if (schema.hasField('displayConfig.unit'))
                _ManagedProviderTextField(
                  fieldKey: const Key('managed-provider-unit'),
                  label: l10n.managedProvidersUnit,
                  controller: unitController,
                  hint: 'requests / tokens',
                ),
              if (schema.hasField('displayConfig.decimalPlaces'))
                TpInputFormField(
                  key: const Key('managed-provider-decimal-places'),
                  label: Text(l10n.managedProvidersDecimals),
                  controller: decimalPlacesController,
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      ((value ?? '').trim().isNotEmpty &&
                          int.tryParse(value!.trim()) == null)
                      ? context.l10n.managedProvidersDecimalError
                      : null,
                ),
            ];
            if (fields.isEmpty) return const SizedBox.shrink();
            if (constraints.maxWidth < 520) {
              return _SpacedColumn(children: fields);
            }
            return Row(
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  Expanded(child: fields[i]),
                  if (i != fields.length - 1) const SizedBox(width: 12),
                ],
              ],
            );
          },
        ),
        if (schema.hasField('displayConfig.showPercent'))
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.managedProvidersShowPercent,
              style: TpTextStyles.of(context).md,
            ),
            value: showPercent,
            onChanged: onShowPercentChanged,
          ),
      ],
    );
  }
}

class ManagedProviderAdvancedSection extends StatelessWidget {
  const ManagedProviderAdvancedSection({
    required this.schema,
    required this.kind,
    required this.adapterController,
    required this.credentialRefController,
    required this.onKindChanged,
    super.key,
  });

  final ManagedProviderEditorSchema schema;
  final ManagedProviderKind kind;
  final TextEditingController adapterController;
  final TextEditingController credentialRefController;
  final ValueChanged<ManagedProviderKind> onKindChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final adapterField = _fieldFor(schema, 'adapterId');
    final kindField = _fieldFor(schema, 'kind');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (schema.hasField('kind'))
          _LabeledControl(
            label: l10n.managedProvidersKind,
            child: TpSelect<ManagedProviderKind>(
              key: const Key('managed-provider-kind'),
              items: const [
                ManagedProviderKind.apiBalance,
                ManagedProviderKind.subscriptionQuota,
                ManagedProviderKind.customHttp,
              ],
              initialItem: kind,
              itemLabel: (kind) => kind.value,
              enabled: !(kindField?.readOnly ?? false),
              onChanged: (value) {
                if (value != null) onKindChanged(value);
              },
              decoration: TpSelectDecorations.themed(context),
            ),
          ),
        if (schema.hasField('adapterId')) ...[
          const SizedBox(height: 12),
          TpInputFormField(
            key: const Key('managed-provider-adapter'),
            label: Text(l10n.managedProvidersAdapter),
            controller: adapterController,
            decoration: InputDecoration(
              hintText: l10n.managedProvidersAdapterHint,
            ),
            readOnly: adapterField?.readOnly ?? false,
            validator: (value) =>
                (value == null || value.trim().isEmpty)
                    ? context.l10n.formFieldRequired
                    : null,
          ),
        ],
        if (schema.hasField('credentialRef')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-ref'),
            label: l10n.managedProvidersCredentialRef,
            controller: credentialRefController,
            hint: l10n.managedProvidersCredentialRefHint,
            readOnly: true,
          ),
        ],
      ],
    );
  }
}

class _ManagedProviderTextField extends StatelessWidget {
  const _ManagedProviderTextField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    this.hint,
    this.readOnly = false,
    this.obscureText = false,
    this.onChanged,
    this.focusNode,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool readOnly;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => _LabeledControl(
    label: label,
    child: TpInput(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(hintText: hint),
      readOnly: readOnly,
      obscureText: obscureText,
      onChanged: onChanged,
    ),
  );
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: TpTextStyles.of(context).smSemiboldColored(
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
      child,
    ],
  );
}

class _SpacedColumn extends StatelessWidget {
  const _SpacedColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i != children.length - 1) const SizedBox(height: 12),
      ],
    ],
  );
}

bool _hasRequiredSecret(ManagedProviderEditorSchema schema) =>
    schema.fields.any(
      (field) =>
          field.kind == ManagedProviderEditorFieldKind.secret && field.required,
    );

ManagedProviderEditorField? _fieldFor(
  ManagedProviderEditorSchema schema,
  String key,
) {
  for (final field in schema.fields) {
    if (field.key == key) return field;
  }
  return null;
}
