import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/managed_provider.dart';
import '../../models/managed_provider_editor_schema.dart';
import '../../models/provider_usage_snapshot.dart';
import '../../services/provider_usage/managed_provider_presets.dart';
import '../../services/provider_usage/managed_provider_secret_store.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../utils/managed_provider_error_localization.dart';
import 'managed_provider_editor_section_shell.dart';
import 'managed_provider_editor_sections.dart';

class ManagedProviderEditorPage extends StatefulWidget {
  const ManagedProviderEditorPage({
    this.provider,
    this.embedded = false,
    this.onBack,
    super.key,
  });

  final ManagedProvider? provider;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  State<ManagedProviderEditorPage> createState() =>
      _ManagedProviderEditorPageState();
}

class _ManagedProviderEditorPageState extends State<ManagedProviderEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _adapter;
  late final TextEditingController _endpoint;
  late final TextEditingController _responsePath;
  late final TextEditingController _measuresPath;
  late final TextEditingController _requestMapping;
  late final TextEditingController _fieldMappings;
  late final TextEditingController _currency;
  late final TextEditingController _unit;
  late final TextEditingController _decimalPlaces;
  late final TextEditingController _credentialRef;
  late final TextEditingController _credentialSecret;
  late final TextEditingController _credentialName;
  late final TextEditingController _credentialField;
  late final TextEditingController _credentialPlacement;
  late ManagedProviderKind _kind;
  late String _method;
  late bool _enabled;
  late bool _showPercent;
  late ManagedProviderEditorSchema _schema;
  String? _credentialPrefix;
  ManagedProviderPreset? _selectedPreset;
  String? _formError;
  bool _saving = false;

  ManagedProvider? get _provider => widget.provider;

  @override
  void initState() {
    super.initState();
    final provider = _provider;
    final endpoint = provider?.endpointConfig;
    final display = provider?.displayConfig;
    _name = TextEditingController(text: provider?.name ?? '');
    _adapter = TextEditingController(text: provider?.adapterId ?? 'http-json');
    _endpoint = TextEditingController(text: endpoint?.url ?? '');
    _responsePath = TextEditingController(text: endpoint?.responsePath ?? '');
    _measuresPath = TextEditingController(text: endpoint?.measuresPath ?? '');
    _requestMapping = TextEditingController(
      text: _prettyJson(endpoint?.body ?? const <String, Object?>{}),
    );
    _fieldMappings = TextEditingController(
      text: _prettyJson(endpoint?.fieldMappings ?? const <String, Object?>{}),
    );
    _currency = TextEditingController(text: display?.currency ?? '');
    _unit = TextEditingController(text: display?.unit ?? '');
    _decimalPlaces = TextEditingController(
      text: display?.decimalPlaces?.toString() ?? '',
    );
    _credentialRef = TextEditingController(text: provider?.credentialRef ?? '');
    _credentialSecret = TextEditingController();
    _credentialName = TextEditingController(
      text: endpoint?.credentialName ?? '',
    );
    _credentialField = TextEditingController(
      text: endpoint?.credentialField ?? '',
    );
    _credentialPlacement = TextEditingController(
      text: endpoint?.credentialPlacement ?? 'header',
    );
    _credentialPrefix = endpoint?.credentialPrefix;
    _kind = provider?.kind == ManagedProviderKind.unknown
        ? ManagedProviderKind.customHttp
        : provider?.kind ?? ManagedProviderKind.customHttp;
    _method = endpoint?.method.toUpperCase() ?? 'GET';
    _enabled = provider?.enabled ?? true;
    _showPercent = display?.showPercent ?? false;
    _schema = ManagedProviderEditorSchema.fromProvider(_draftProvider());
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _adapter,
      _endpoint,
      _responsePath,
      _measuresPath,
      _requestMapping,
      _fieldMappings,
      _currency,
      _unit,
      _decimalPlaces,
      _credentialRef,
      _credentialSecret,
      _credentialName,
      _credentialField,
      _credentialPlacement,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final l10n = context.l10n;
    final form = SafeArea(
      child: Form(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
          children: [
            if (_formError != null) _ErrorBanner(message: _formError!),
            ManagedProviderEditorSectionShell(
              key: const Key('managed-provider-section-basics'),
              title: l10n.managedProvidersBasicsSectionTitle,
              subtitle: l10n.managedProvidersBasicsSectionSubtitle,
              initiallyExpanded: true,
              child: ManagedProviderBasicsSection(
                schema: _schema,
                showPresetSelector: provider == null,
                selectedPreset: _selectedPreset,
                nameController: _name,
                credentialSecretController: _credentialSecret,
                credentialConfigured: _credentialRef.text.trim().isNotEmpty,
                onPresetChanged: _applyPreset,
              ),
            ),
            if (_schema.hasSection(ManagedProviderEditorSection.query)) ...[
              const SizedBox(height: 12),
              ManagedProviderEditorSectionShell(
                key: const Key('managed-provider-section-query'),
                title: l10n.managedProvidersQuerySectionTitle,
                subtitle: l10n.managedProvidersQuerySectionSubtitle,
                initiallyExpanded: _queryInitiallyExpanded,
                child: ManagedProviderQuerySection(
                  schema: _schema,
                  endpointController: _endpoint,
                  method: _method,
                  responsePathController: _responsePath,
                  measuresPathController: _measuresPath,
                  requestMappingController: _requestMapping,
                  fieldMappingsController: _fieldMappings,
                  onMethodChanged: (value) => setState(() => _method = value),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ManagedProviderEditorSectionShell(
              key: const Key('managed-provider-section-credentials'),
              title: l10n.managedProvidersCredentialsSectionTitle,
              subtitle: l10n.managedProvidersCredentialsSectionSubtitle,
              initiallyExpanded: _credentialsInitiallyExpanded,
              badge: _credentialsInitiallyExpanded
                  ? l10n.managedProvidersSectionConfiguredBadge
                  : null,
              child: ManagedProviderCredentialsSection(
                schema: _schema,
                credentialNameController: _credentialName,
                credentialFieldController: _credentialField,
                credentialPlacementController: _credentialPlacement,
                credentialConfigured: _credentialRef.text.trim().isNotEmpty,
              ),
            ),
            const SizedBox(height: 12),
            ManagedProviderEditorSectionShell(
              key: const Key('managed-provider-section-display'),
              title: l10n.managedProvidersDisplaySectionTitle,
              subtitle: l10n.managedProvidersDisplaySectionSubtitle,
              initiallyExpanded: _displayInitiallyExpanded,
              badge: _displayInitiallyExpanded
                  ? l10n.managedProvidersSectionConfiguredBadge
                  : null,
              child: ManagedProviderDisplaySection(
                schema: _schema,
                currencyController: _currency,
                unitController: _unit,
                decimalPlacesController: _decimalPlaces,
                showPercent: _showPercent,
                onShowPercentChanged: (value) =>
                    setState(() => _showPercent = value),
              ),
            ),
            const SizedBox(height: 12),
            ManagedProviderEditorSectionShell(
              key: const Key('managed-provider-section-advanced'),
              title: l10n.managedProvidersAdvancedSectionTitle,
              subtitle: l10n.managedProvidersAdvancedSectionSubtitle,
              initiallyExpanded: _advancedInitiallyExpanded,
              badge: _advancedInitiallyExpanded
                  ? l10n.managedProvidersSectionConfiguredBadge
                  : null,
              child: ManagedProviderAdvancedSection(
                schema: _schema,
                kind: _kind,
                adapterController: _adapter,
                credentialRefController: _credentialRef,
                enabled: _enabled,
                onKindChanged: _setKind,
                onEnabledChanged: _setEnabled,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TpButton(
                    key: const Key('managed-provider-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(
                      _saving
                          ? l10n.managedProvidersSaving
                          : l10n.managedProvidersSaveProvider,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TpButton(
                    key: const Key('managed-provider-test-query'),
                    variant: TpButtonVariant.outline,
                    onPressed: _saving ? null : _testQuery,
                    child: Text(l10n.managedProvidersTestProviderQuery),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) {
      return Column(
        children: [
          _EmbeddedEditorHeader(
            title: provider == null
                ? l10n.managedProvidersNewTitle
                : l10n.managedProvidersEditTitle,
            showDelete: provider != null,
            deleteEnabled: !_saving,
            onBack: _handleBack,
            onDelete: _delete,
          ),
          Expanded(child: form),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          provider == null
              ? l10n.managedProvidersNewTitle
              : l10n.managedProvidersEditTitle,
        ),
        actions: [
          if (provider != null)
            IconButton(
              key: const Key('managed-provider-delete'),
              tooltip: l10n.managedProvidersDelete,
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: form,
    );
  }

  void _applyPreset(ManagedProviderPreset preset) {
    final template = preset.template;
    final endpoint = template.endpointConfig;
    final display = template.displayConfig;
    final schema =
        preset.schema ?? ManagedProviderEditorSchema.fromProvider(template);
    setState(() {
      _selectedPreset = preset;
      _name.text = template.name;
      _adapter.text = template.adapterId;
      _endpoint.text = endpoint.url;
      _responsePath.text = endpoint.responsePath ?? '';
      _measuresPath.text = endpoint.measuresPath ?? '';
      _requestMapping.text = _prettyJson(endpoint.body);
      _fieldMappings.text = _prettyJson(endpoint.fieldMappings);
      _kind = template.kind;
      _method = endpoint.method.toUpperCase();
      _credentialRef.clear();
      _credentialName.text = endpoint.credentialName ?? '';
      _credentialField.text = endpoint.credentialField ?? '';
      _credentialPlacement.text = endpoint.credentialPlacement;
      _credentialPrefix = endpoint.credentialPrefix;
      _currency.text = display.currency ?? '';
      _unit.text = display.unit ?? '';
      _decimalPlaces.text = display.decimalPlaces?.toString() ?? '';
      _enabled = template.enabled;
      _showPercent = display.showPercent;
      _schema = schema;
      if (!_schemaRequiresSecret(schema)) _credentialSecret.clear();
      _formError = null;
    });
  }

  void _handleBack() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.of(context).pop();
  }

  void _setKind(ManagedProviderKind value) {
    setState(() {
      _kind = value;
      _schema = ManagedProviderEditorSchema.fromProvider(_draftProvider());
    });
  }

  ManagedProvider _draftProvider() => ManagedProvider(
    id: _provider?.id ?? '',
    name: _name.text.trim(),
    kind: _kind,
    adapterId: _adapter.text.trim().isEmpty
        ? 'http-json'
        : _adapter.text.trim(),
    endpointConfig: ManagedProviderEndpointConfig(
      url: _endpoint.text.trim(),
      method: _method,
      responsePath: _responsePath.text.trim().isEmpty
          ? null
          : _responsePath.text.trim(),
      measuresPath: _measuresPath.text.trim().isEmpty
          ? null
          : _measuresPath.text.trim(),
      body: _decodeObject(_requestMapping.text) ?? const {},
      fieldMappings: _decodeObject(_fieldMappings.text) ?? const {},
      credentialName: _credentialName.text.trim().isEmpty
          ? null
          : _credentialName.text.trim(),
      credentialField: _credentialField.text.trim().isEmpty
          ? null
          : _credentialField.text.trim(),
      credentialPlacement: _credentialPlacement.text.trim().isEmpty
          ? 'header'
          : _credentialPlacement.text.trim().toLowerCase(),
      credentialPrefix: _credentialPrefix,
    ),
    credentialRef: _credentialRef.text.trim().isEmpty
        ? null
        : _credentialRef.text.trim(),
    displayConfig: ManagedProviderDisplayConfig(
      currency: _currency.text.trim().isEmpty ? null : _currency.text.trim(),
      unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      decimalPlaces: int.tryParse(_decimalPlaces.text.trim()),
      showPercent: _showPercent,
    ),
    enabled: _enabled,
  );

  bool get _queryInitiallyExpanded =>
      _kind == ManagedProviderKind.customHttp ||
      _schema.firstQuery && _selectedPreset == null;

  bool get _credentialsInitiallyExpanded {
    final provider = _provider;
    if (provider == null) return false;
    final endpoint = provider.endpointConfig;
    return provider.credentialRef != null &&
            provider.credentialRef!.isNotEmpty ||
        endpoint.credentialName != null &&
            endpoint.credentialName!.isNotEmpty ||
        endpoint.credentialField != null &&
            endpoint.credentialField!.isNotEmpty ||
        endpoint.credentialPlacement != 'header' ||
        endpoint.credentialPrefix != null &&
            endpoint.credentialPrefix!.isNotEmpty;
  }

  bool get _displayInitiallyExpanded {
    final provider = _provider;
    if (provider == null) return false;
    final display = provider.displayConfig;
    return display.currency != null && display.currency!.isNotEmpty ||
        display.unit != null && display.unit!.isNotEmpty ||
        display.decimalPlaces != null ||
        display.showPercent;
  }

  bool get _advancedInitiallyExpanded {
    final provider = _provider;
    if (provider == null) return false;
    return provider.adapterId != 'http-json' ||
        provider.kind != ManagedProviderKind.customHttp ||
        !provider.enabled ||
        provider.credentialRef != null && provider.credentialRef!.isNotEmpty;
  }

  bool _schemaRequiresSecret(ManagedProviderEditorSchema schema) =>
      schema.fields.any(
        (field) =>
            field.kind == ManagedProviderEditorFieldKind.secret &&
            field.required,
      );

  Future<void> _save() async {
    final name = _name.text.trim();
    final adapter = _adapter.text.trim();
    final endpoint = _endpoint.text.trim();
    if (name.isEmpty || adapter.isEmpty) {
      setState(
        () => _formError = context.l10n.managedProvidersNameAdapterError,
      );
      return;
    }

    final body = _decodeObject(_requestMapping.text);
    final fieldMappings = _decodeObject(_fieldMappings.text);
    final decimalPlaces = int.tryParse(_decimalPlaces.text.trim());
    if (body == null ||
        _requestMapping.text.trim().isNotEmpty &&
            body.isEmpty &&
            _requestMapping.text.trim() != '{}') {
      setState(
        () => _formError = context.l10n.managedProvidersRequestMappingError,
      );
      return;
    }
    if (_containsCredentialKey(body)) {
      setState(
        () => _formError = context.l10n.managedProvidersSecretMappingError,
      );
      return;
    }
    if (fieldMappings == null || _containsCredentialKey(fieldMappings)) {
      setState(
        () => _formError = context.l10n.managedProvidersFieldMappingError,
      );
      return;
    }
    if (_decimalPlaces.text.trim().isNotEmpty && decimalPlaces == null) {
      setState(() => _formError = context.l10n.managedProvidersDecimalError);
      return;
    }
    if ((adapter == 'http-json' || _kind == ManagedProviderKind.customHttp) &&
        !_isAllowedEndpoint(endpoint)) {
      setState(() => _formError = context.l10n.managedProvidersEndpointError);
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });
    final cubit = context.read<ManagedProviderCubit>();
    final secretStore = context.read<ManagedProviderSecretStore>();
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = _provider;
    final providerId = current?.id ?? 'managed-$now';
    final credentialField = _credentialField.text.trim();
    var credentialRef = _credentialRef.text.trim();
    final credentialSecret = _credentialSecret.text.trim();
    if (credentialSecret.isNotEmpty) {
      if (credentialField.isEmpty) {
        setState(() {
          _saving = false;
          _formError = context.l10n.managedProvidersCredentialFieldRequired;
        });
        return;
      }
      credentialRef = credentialRef.isEmpty
          ? 'managed-provider:$providerId'
          : credentialRef;
      try {
        await secretStore.write(credentialRef, {
          credentialField: credentialSecret,
        });
      } on Object {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _formError = context.l10n.managedProvidersCredentialSaveFailed;
        });
        return;
      }
    }
    final next = ManagedProvider(
      id: providerId,
      name: name,
      kind: _kind,
      adapterId: adapter,
      brand: current?.brand,
      websiteUrl: current?.websiteUrl ?? '',
      endpointConfig: ManagedProviderEndpointConfig(
        url: endpoint,
        method: _method,
        responsePath: _responsePath.text.trim().isEmpty
            ? null
            : _responsePath.text.trim(),
        measuresPath: _measuresPath.text.trim().isEmpty
            ? null
            : _measuresPath.text.trim(),
        body: body,
        headers: current?.endpointConfig.headers ?? const {},
        fieldMappings: fieldMappings,
        unknownFields: current?.endpointConfig.unknownFields ?? const {},
        credentialName: _credentialName.text.trim().isEmpty
            ? null
            : _credentialName.text.trim(),
        credentialField: _credentialField.text.trim().isEmpty
            ? null
            : _credentialField.text.trim(),
        credentialPlacement: _credentialPlacement.text.trim().isEmpty
            ? 'header'
            : _credentialPlacement.text.trim().toLowerCase(),
        credentialPrefix: _credentialPrefix,
      ),
      credentialRef: credentialRef.isEmpty ? null : credentialRef,
      displayConfig: ManagedProviderDisplayConfig(
        currency: _currency.text.trim().isEmpty ? null : _currency.text.trim(),
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        decimalPlaces: decimalPlaces,
        showPercent: _showPercent,
        unknownFields: current?.displayConfig.unknownFields ?? const {},
      ),
      unknownFields: current?.unknownFields ?? const {},
      enabled: _enabled,
      createdAt: current == null || current.createdAt == 0
          ? now
          : current.createdAt,
      updatedAt: now,
    );
    await cubit.upsert(next);
    if (!mounted) return;
    setState(() => _saving = false);
    if (cubit.state.errorCode != null) {
      setState(
        () => _formError = managedProviderErrorMessage(
          context.l10n,
          providerCode: cubit.state.errorCode,
          detail: cubit.state.errorMessage,
        ),
      );
      return;
    }
    AppToast.show(
      context,
      message: context.l10n.managedProvidersSaved,
      variant: TpToastVariant.success,
    );
    _handleBack();
  }

  Future<void> _delete() async {
    final provider = _provider;
    if (provider == null) return;
    setState(() => _saving = true);
    await context.read<ManagedProviderCubit>().delete(provider.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (context.read<ManagedProviderCubit>().state.errorCode != null) {
      setState(
        () => _formError = managedProviderErrorMessage(
          context.l10n,
          providerCode: context.read<ManagedProviderCubit>().state.errorCode,
          detail: context.read<ManagedProviderCubit>().state.errorMessage,
        ),
      );
      return;
    }
    _handleBack();
  }

  Future<void> _testQuery() async {
    final draft = _draftProviderForQuery();
    if (draft == null) return;
    setState(() => _saving = true);
    final snapshot = await context
        .read<ManagedProviderUsageCubit>()
        .queryProvider(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    final failed =
        snapshot?.status == ProviderUsageStatus.error ||
        snapshot?.status == ProviderUsageStatus.unsupported;
    AppToast.show(
      context,
      message: failed
          ? snapshot?.status == ProviderUsageStatus.unsupported
                ? context.l10n.managedProvidersQueryUnsupported
                : snapshot == null
                ? context.l10n.managedProvidersQueryFailed
                : managedProviderSnapshotErrorMessage(context.l10n, snapshot)
          : context.l10n.managedProvidersQueryCompleted,
      variant: failed ? TpToastVariant.error : TpToastVariant.success,
    );
  }

  ManagedProvider? _draftProviderForQuery() {
    final name = _name.text.trim();
    final adapter = _adapter.text.trim();
    final endpoint = _endpoint.text.trim();
    final body = _decodeObject(_requestMapping.text);
    final fieldMappings = _decodeObject(_fieldMappings.text);
    if (name.isEmpty || adapter.isEmpty) {
      setState(
        () => _formError = context.l10n.managedProvidersNameAdapterError,
      );
      return null;
    }
    if (body == null || _containsCredentialKey(body)) {
      setState(
        () => _formError = context.l10n.managedProvidersSecretMappingError,
      );
      return null;
    }
    if (fieldMappings == null || _containsCredentialKey(fieldMappings)) {
      setState(
        () => _formError = context.l10n.managedProvidersFieldMappingError,
      );
      return null;
    }
    if ((adapter == 'http-json' || _kind == ManagedProviderKind.customHttp) &&
        !_isAllowedEndpoint(endpoint)) {
      setState(() => _formError = context.l10n.managedProvidersEndpointError);
      return null;
    }
    final current = _provider;
    return ManagedProvider(
      id: current?.id ?? 'managed-query',
      name: name,
      kind: _kind,
      adapterId: adapter,
      endpointConfig: ManagedProviderEndpointConfig(
        url: endpoint,
        method: _method,
        responsePath: _responsePath.text.trim().isEmpty
            ? null
            : _responsePath.text.trim(),
        measuresPath: _measuresPath.text.trim().isEmpty
            ? null
            : _measuresPath.text.trim(),
        body: body,
        headers: current?.endpointConfig.headers ?? const {},
        fieldMappings: fieldMappings,
        credentialName: _credentialName.text.trim().isEmpty
            ? null
            : _credentialName.text.trim(),
        credentialField: _credentialField.text.trim().isEmpty
            ? null
            : _credentialField.text.trim(),
        credentialPlacement: _credentialPlacement.text.trim().isEmpty
            ? 'header'
            : _credentialPlacement.text.trim().toLowerCase(),
        credentialPrefix: _credentialPrefix,
      ),
      credentialRef: _credentialRef.text.trim().isEmpty
          ? null
          : _credentialRef.text.trim(),
      displayConfig: current?.displayConfig,
      enabled: _enabled,
    );
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    final id = _provider?.id;
    if (id == null) return;
    final cubit = context.read<ManagedProviderCubit>();
    if (value) {
      await cubit.enable(id);
    } else {
      await cubit.disable(id);
    }
  }

  static Map<String, Object?>? _decodeObject(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const {};
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } on Object {
      return null;
    }
  }

  static String _prettyJson(Map<String, Object?> value) {
    if (value.isEmpty) return '{}';
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  static bool _isAllowedEndpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    const loopback = {'localhost', '127.0.0.1', '::1'};
    return loopback.contains(uri.host.toLowerCase()) &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static bool _containsCredentialKey(Map<String, Object?> value) {
    for (final entry in value.entries) {
      if (isManagedProviderCredentialKey(entry.key)) return true;
      final nested = entry.value;
      if (nested is Map &&
          _containsCredentialKey(Map<String, Object?>.from(nested))) {
        return true;
      }
      if (nested is List) {
        for (final item in nested) {
          if (item is Map &&
              _containsCredentialKey(Map<String, Object?>.from(item))) {
            return true;
          }
        }
      }
    }
    return false;
  }
}

class _EmbeddedEditorHeader extends StatelessWidget {
  const _EmbeddedEditorHeader({
    required this.title,
    required this.showDelete,
    required this.deleteEnabled,
    required this.onBack,
    required this.onDelete,
  });

  final String title;
  final bool showDelete;
  final bool deleteEnabled;
  final VoidCallback onBack;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    height: kToolbarHeight,
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        IconButton(
          key: const Key('managed-provider-editor-back'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(title, style: TpTextStyles.of(context).lgSemibold),
        ),
        if (showDelete)
          IconButton(
            key: const Key('managed-provider-delete'),
            tooltip: context.l10n.managedProvidersDelete,
            onPressed: deleteEnabled ? onDelete : null,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('managed-provider-editor-error'),
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message),
  );
}
