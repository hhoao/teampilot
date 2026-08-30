import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/managed_provider_editor_schema.dart';
import '../../services/provider_usage/managed_provider_presets.dart';
import 'managed_provider_editor_field_examples.dart';
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
    required this.onQuickPresetChanged,
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
  final ValueChanged<String> onQuickPresetChanged;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedQuickPresetId =
        selectedPreset?.id ?? kManagedProviderQuickPresetCustomId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showPresetSelector) ...[
          _LabeledControl(
            label: l10n.managedProvidersQuickPresetTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TpSelect<String>(
                  key: const Key('managed-provider-quick-preset'),
                  items: managedProviderQuickPresetOptionIds,
                  initialItem: selectedQuickPresetId,
                  itemLabel: l10n.managedProviderPresetLabel,
                  listItemKey: (id) => Key('managed-provider-quick-preset-$id'),
                  onChanged: (id) {
                    if (id != null) onQuickPresetChanged(id);
                  },
                  decoration: TpSelectDecorations.themed(context),
                  searchMinItems: 0,
                  overlayHeight: kTpSelectDefaultOverlayHeight,
                  overlayFillHeight: true,
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.managedProviderPresetHint(selectedQuickPresetId),
                  style: TpTextStyles.of(
                    context,
                  ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
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
            tip: managedProviderFieldTip(
              l10n,
              explanation: l10n.managedProvidersCredentialSecretHelper,
            ),
            obscureText: true,
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
    required this.requestMappingController,
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
  final TextEditingController requestMappingController;
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
            label: TpFormFieldLabel(
              text: l10n.managedProvidersEndpoint,
              tip: managedProviderFieldTip(
                l10n,
                explanation: l10n.managedProvidersEndpointHelper,
                example: 'https://api.deepseek.com/user/balance',
              ),
            ),
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
            tip: managedProviderFieldTip(
              l10n,
              explanation: l10n.managedProvidersMethodHelper,
              example: 'GET',
            ),
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
            hint: ManagedProviderEditorFieldExamples.responsePath,
            tip: managedProviderFieldTip(
              l10n,
              explanation: l10n.managedProvidersResponsePathHelper,
              example: ManagedProviderEditorFieldExamples.responsePath,
              seeAlso: l10n.managedProvidersJsonPathSeeAlso,
            ),
          ),
        ],
        if (schema.hasField('endpointConfig.body')) ...[
          const SizedBox(height: 12),
          TpTextareaFormField(
            key: const Key('managed-provider-request-mapping'),
            label: TpFormFieldLabel(
              text: l10n.managedProvidersRequestMapping,
              tip: managedProviderFieldTip(
                l10n,
                explanation: l10n.managedProvidersRequestMappingHelper,
                example: ManagedProviderEditorFieldExamples.requestBody,
              ),
            ),
            controller: requestMappingController,
            minHeight: 90,
            maxHeight: 180,
            decoration: const InputDecoration(
              hintText: ManagedProviderEditorFieldExamples.requestBody,
            ),
            validator: (value) {
              final parsed = decodeJsonObject(value ?? '');
              if (parsed == null || mappingContainsCredentialKey(parsed)) {
                return context.l10n.managedProvidersRequestMappingError;
              }
              return null;
            },
          ),
        ],
        if (schema.hasField('endpointConfig.headers')) ...[
          const SizedBox(height: 12),
          TpTextareaFormField(
            key: const Key('managed-provider-headers'),
            label: TpFormFieldLabel(
              text: l10n.managedProvidersHeaders,
              tip: managedProviderFieldTip(
                l10n,
                explanation: l10n.managedProvidersHeadersHelper,
                example: ManagedProviderEditorFieldExamples.headers,
                seeAlso: l10n.managedProvidersTemplateVariablesSeeAlsoQuery,
              ),
            ),
            controller: headersController,
            minHeight: 90,
            maxHeight: 180,
            decoration: const InputDecoration(
              hintText: ManagedProviderEditorFieldExamples.headers,
            ),
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
            label: TpFormFieldLabel(
              text: l10n.managedProvidersWindows,
              tip: managedProviderFieldTip(
                l10n,
                explanation: l10n.managedProvidersWindowsHelper,
                example: ManagedProviderEditorFieldExamples.windows,
                seeAlso: l10n.managedProvidersJsonPathSeeAlso,
              ),
            ),
            controller: windowsController,
            minHeight: 120,
            maxHeight: 220,
            decoration: const InputDecoration(
              hintText: ManagedProviderEditorFieldExamples.windows,
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
        schema.isFieldEditable('endpointConfig.credentialName') ||
        schema.isFieldEditable('endpointConfig.credentialField') ||
        schema.isFieldEditable('endpointConfig.credentialPlacement') ||
        schema.isFieldEditable('endpointConfig.credentialSource') ||
        schema.isFieldEditable('endpointConfig.credentialTemplate');
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
        if (schema.isFieldEditable('endpointConfig.credentialName'))
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-name'),
            label: l10n.managedProvidersCredentialName,
            controller: credentialNameController,
            hint: l10n.managedProvidersCredentialNameHint,
            tip: managedProviderFieldTip(
              l10n,
              explanation: l10n.managedProvidersCredentialNameHelper,
              example: 'Authorization',
            ),
          ),
        if (schema.isFieldEditable('endpointConfig.credentialField')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-field'),
            label: l10n.managedProvidersCredentialField,
            controller: credentialFieldController,
            hint: l10n.managedProvidersCredentialFieldHint,
            tip: managedProviderFieldTip(
              l10n,
              explanation: l10n.managedProvidersCredentialFieldHelper,
              example: 'apiKey',
            ),
            onChanged: onCredentialFieldChanged,
          ),
        ],
        if (schema.isFieldEditable('endpointConfig.credentialPlacement')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-placement'),
            label: l10n.managedProvidersCredentialPlacement,
            controller: credentialPlacementController,
            hint: l10n.managedProvidersCredentialPlacementHint,
            tip: managedProviderFieldTip(
              l10n,
              explanation: l10n.managedProvidersCredentialPlacementHelper,
              example: 'header',
            ),
          ),
        ],
        if (schema.isFieldEditable('endpointConfig.credentialSource')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-source'),
            label: l10n.managedProvidersCredentialSource,
            controller: credentialSourceController,
            hint: l10n.managedProvidersCredentialSourceHint,
            tip: managedProviderFieldTip(
              l10n,
              explanation: l10n.managedProvidersCredentialSourceHelper,
              example: 'cli:cursor-account',
              seeAlso: l10n.managedProvidersTemplateVariablesSeeAlsoCredentials,
            ),
          ),
        ],
        if (schema.isFieldEditable('endpointConfig.credentialTemplate')) ...[
          const SizedBox(height: 12),
          _ManagedProviderTextField(
            fieldKey: const Key('managed-provider-credential-template'),
            label: l10n.managedProvidersCredentialTemplate,
            controller: credentialTemplateController,
            hint: ManagedProviderEditorFieldExamples.credentialTemplate,
            tip: managedProviderFieldTip(
              l10n,
              explanation: l10n.managedProvidersCredentialTemplateHelper,
              example: ManagedProviderEditorFieldExamples.credentialTemplate,
              seeAlso: l10n.managedProvidersTemplateVariablesSeeAlsoCredentials,
            ),
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
    required this.onKindChanged,
    super.key,
  });

  final ManagedProviderEditorSchema schema;
  final ManagedProviderKind kind;
  final TextEditingController adapterController;
  final ValueChanged<ManagedProviderKind> onKindChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (schema.isFieldEditable('kind'))
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
              itemLabel: l10n.managedProviderKindLabel,
              onChanged: (value) {
                if (value != null) onKindChanged(value);
              },
              decoration: TpSelectDecorations.themed(context),
              searchable: false,
              anchor: const TpAnchor(
                childAlignment: Alignment.bottomCenter,
                overlayAlignment: Alignment.topCenter,
                offset: Offset(0, -4),
              ),
            ),
          ),
        if (schema.isFieldEditable('adapterId')) ...[
          if (schema.isFieldEditable('kind')) const SizedBox(height: 12),
          TpInputFormField(
            key: const Key('managed-provider-adapter'),
            label: Text(l10n.managedProvidersAdapter),
            controller: adapterController,
            decoration: InputDecoration(
              hintText: l10n.managedProvidersAdapterHint,
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty)
                    ? context.l10n.formFieldRequired
                    : null,
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
    this.tip,
    this.obscureText = false,
    this.onChanged,
    this.focusNode,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? tip;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => _LabeledControl(
    label: label,
    tip: tip,
    child: TpInput(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(hintText: hint),
      obscureText: obscureText,
      onChanged: onChanged,
    ),
  );
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({
    required this.label,
    required this.child,
    this.tip,
  });

  final String label;
  final String? tip;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TpFormFieldLabel(
          text: label,
          tip: tip,
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
