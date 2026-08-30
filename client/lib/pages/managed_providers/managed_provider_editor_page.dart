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
import '../../services/provider_usage/managed_provider_credential_transaction.dart';
import '../../services/provider_usage/managed_provider_presets.dart';
import '../../services/provider_usage/managed_provider_secret_store.dart';
import '../../services/provider_usage/official_managed_provider_binding.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../../utils/managed_provider_error_localization.dart';
import 'managed_provider_editor_field_examples.dart';
import 'managed_provider_editor_section_shell.dart';
import 'managed_provider_editor_sections.dart';
import 'managed_provider_editor_validation.dart';
import 'managed_provider_official_credentials.dart';

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
  late final TextEditingController _requestMapping;
  late final TextEditingController _currency;
  late final TextEditingController _unit;
  late final TextEditingController _decimalPlaces;
  late final TextEditingController _credentialRef;
  late final TextEditingController _credentialSecret;
  late final FocusNode _credentialSecretFocus;
  late final TextEditingController _credentialName;
  late final TextEditingController _credentialField;
  late final TextEditingController _credentialPlacement;
  late final TextEditingController _credentialSource;
  late final TextEditingController _credentialTemplate;
  late final TextEditingController _headers;
  late final TextEditingController _windows;
  late ManagedProviderKind _kind;
  late String _method;
  late bool _enabled;
  late bool _showPercent;
  late ManagedProviderEditorSchema _schema;
  String? _credentialPrefix;
  ManagedProviderPreset? _selectedPreset;
  final _editorFormKey = GlobalKey<TpFormState>();
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
    _requestMapping = TextEditingController(
      text: _prettyJson(endpoint?.body ?? const <String, Object?>{}),
    );
    _currency = TextEditingController(text: display?.currency ?? '');
    _unit = TextEditingController(text: display?.unit ?? '');
    _decimalPlaces = TextEditingController(
      text: display?.decimalPlaces?.toString() ?? '',
    );
    _credentialRef = TextEditingController(text: provider?.credentialRef ?? '');
    _credentialSecret = TextEditingController();
    _credentialSecretFocus = FocusNode();
    _credentialName = TextEditingController(
      text: endpoint?.credentialName ?? '',
    );
    _credentialField = TextEditingController(
      text: endpoint?.credentialField ?? '',
    );
    _credentialPlacement = TextEditingController(
      text: endpoint?.credentialPlacement ?? 'header',
    );
    _credentialSource = TextEditingController(
      text: endpoint?.credentialSource ?? 'secret',
    );
    _credentialTemplate = TextEditingController(
      text: endpoint?.credentialTemplate ?? '',
    );
    _headers = TextEditingController(
      text: _prettyJson(
        endpoint?.headers.map((key, value) => MapEntry(key, value)) ??
            const <String, Object?>{},
      ),
    );
    _windows = TextEditingController(
      text: endpoint == null || endpoint.windows.isEmpty
          ? ''
          : const JsonEncoder.withIndent('  ').convert(
              endpoint.windows.map((window) => window.toJson()).toList(),
            ),
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
      _requestMapping,
      _currency,
      _unit,
      _decimalPlaces,
      _credentialRef,
      _credentialSecret,
      _credentialName,
      _credentialField,
      _credentialPlacement,
      _credentialSource,
      _credentialTemplate,
      _headers,
      _windows,
    ]) {
      controller.dispose();
    }
    _credentialSecretFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final l10n = context.l10n;
    final form = SafeArea(
      child: TpForm(
        key: _editorFormKey,

        // Non-lazy scrolling keeps every section's TpFormFields mounted:
        // click-time validation must see collapsed and off-screen sections
        // alike, and lazy recycling would unregister their fields.
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: widget.embedded
              ? const EdgeInsets.fromLTRB(0, 8, 0, 80)
              : const EdgeInsets.fromLTRB(20, 8, 20, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  credentialSecretFocusNode: _credentialSecretFocus,
                  credentialConfigured: _credentialRef.text.trim().isNotEmpty,
                  enabled: _enabled,
                  onQuickPresetChanged: _handleQuickPresetChanged,
                  onEnabledChanged: _setEnabled,
                ),
              ),
              if (_schema.hasSection(ManagedProviderEditorSection.query)) ...[
                const SizedBox(height: 12),
                ManagedProviderEditorSectionShell(
                  key: const Key('managed-provider-section-query'),
                  title: l10n.managedProvidersQuerySectionTitle,
                  subtitle: l10n.managedProvidersQuerySectionSubtitle,
                  referenceTip: managedProviderHttpJsonReferenceTip(l10n),
                  initiallyExpanded: _queryInitiallyExpanded,
                  child: ManagedProviderQuerySection(
                    schema: _schema,
                    endpointController: _endpoint,
                    method: _method,
                    responsePathController: _responsePath,
                    requestMappingController: _requestMapping,
                    headersController: _headers,
                    windowsController: _windows,
                    onMethodChanged: (value) => setState(() => _method = value),
                    strictEndpointResolver: () =>
                        _adapter.text.trim() == 'http-json' ||
                        _kind == ManagedProviderKind.customHttp,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ManagedProviderEditorSectionShell(
                key: const Key('managed-provider-section-credentials'),
                title: l10n.managedProvidersCredentialsSectionTitle,
                subtitle: l10n.managedProvidersCredentialsSectionSubtitle,
                referenceTip: _isCliCredentialSource
                    ? null
                    : managedProviderHttpJsonReferenceTip(l10n),
                initiallyExpanded: _credentialsInitiallyExpanded,
                badge: _credentialsInitiallyExpanded
                    ? l10n.managedProvidersSectionConfiguredBadge
                    : null,
                child: _isCliCredentialSource
                    ? ManagedProviderOfficialCredentials(
                        credentialSource: _credentialSource.text.trim(),
                      )
                    : ManagedProviderCredentialsSection(
                        schema: _schema,
                        credentialNameController: _credentialName,
                        credentialFieldController: _credentialField,
                        credentialPlacementController: _credentialPlacement,
                        credentialSourceController: _credentialSource,
                        credentialTemplateController: _credentialTemplate,
                        credentialConfigured: _credentialRef.text
                            .trim()
                            .isNotEmpty,
                        onCredentialFieldChanged: _handleCredentialFieldChanged,
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
              if (_schema.hasEditableAdvancedFields)
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
                    onKindChanged: _setKind,
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

  void _handleQuickPresetChanged(String id) {
    if (id == kManagedProviderQuickPresetCustomId) {
      _resetToCustomTemplate();
      return;
    }
    final preset = managedProviderPresetById(id);
    if (preset != null) {
      _applyPreset(preset);
    }
  }

  void _resetToCustomTemplate() {
    setState(() {
      _selectedPreset = null;
      _name.clear();
      _adapter.text = 'http-json';
      _endpoint.clear();
      _responsePath.clear();
      _requestMapping.text = _prettyJson(const <String, Object?>{});
      _kind = ManagedProviderKind.customHttp;
      _method = 'GET';
      _credentialRef.clear();
      _credentialSecret.clear();
      _credentialName.clear();
      _credentialField.clear();
      _credentialPlacement.text = 'header';
      _credentialSource.text = 'secret';
      _credentialTemplate.clear();
      _headers.text = _prettyJson(const <String, Object?>{});
      _windows.clear();
      _credentialPrefix = null;
      _currency.clear();
      _unit.clear();
      _decimalPlaces.clear();
      _enabled = true;
      _showPercent = false;
      _schema = ManagedProviderEditorSchema.fromProvider(_draftProvider());
      _formError = null;
    });
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
      _requestMapping.text = _prettyJson(endpoint.body);
      _kind = template.kind;
      _method = endpoint.method.toUpperCase();
      _credentialRef.clear();
      _credentialName.text = endpoint.credentialName ?? '';
      _credentialField.text = endpoint.credentialField ?? '';
      _credentialPlacement.text = endpoint.credentialPlacement;
      _credentialSource.text = endpoint.credentialSource;
      _credentialTemplate.text = endpoint.credentialTemplate ?? '';
      _headers.text = _prettyJson(
        endpoint.headers.map((key, value) => MapEntry(key, value)),
      );
      _windows.text = endpoint.windows.isEmpty
          ? ''
          : const JsonEncoder.withIndent('  ').convert(
              endpoint.windows.map((window) => window.toJson()).toList(),
            );
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
      if (_selectedPreset?.schema == null) {
        _schema = ManagedProviderEditorSchema.fromProvider(_draftProvider());
      }
    });
  }

  void _handleCredentialFieldChanged(String _) {
    if (_selectedPreset?.schema != null) return;
    final next = ManagedProviderEditorSchema.fromProvider(_draftProvider());
    if (next == _schema) return;
    setState(() {
      _schema = next;
      if (!_schemaRequiresSecret(next)) _credentialSecret.clear();
    });
  }

  ManagedProvider _draftProvider() {
    final windows = _decodeWindows(_windows.text);
    return ManagedProvider(
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
      body: decodeJsonObject(_requestMapping.text) ?? const {},
      headers: _decodeHeaders(_headers.text),
      windows: windows,
      credentialSource: _credentialSource.text.trim().isEmpty
          ? 'secret'
          : _credentialSource.text.trim(),
      credentialTemplate: _credentialTemplate.text.trim().isEmpty
          ? null
          : _credentialTemplate.text.trim(),
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
  }

  bool get _queryInitiallyExpanded =>
      _kind == ManagedProviderKind.customHttp ||
      _credentialSource.text.trim().startsWith('cli:') ||
      (_schema.firstQuery && _selectedPreset == null);

  bool get _isCliCredentialSource =>
      OfficialManagedProviderBinding.forCredentialSource(
        _credentialSource.text.trim(),
      ) !=
      null;

  bool get _credentialsInitiallyExpanded {
    if (_isCliCredentialSource) return true;
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
    if (!_schema.hasEditableAdvancedFields) return false;
    final provider = _provider;
    if (provider == null) return false;
    return provider.adapterId != 'http-json' ||
        provider.kind != ManagedProviderKind.customHttp;
  }

  bool _schemaRequiresSecret(ManagedProviderEditorSchema schema) =>
      schema.fields.any(
        (field) =>
            field.kind == ManagedProviderEditorFieldKind.secret &&
            field.required,
      );

  Future<void> _save() async {
    if (!(_editorFormKey.currentState?.validate() ?? false)) return;
    final name = _name.text.trim();
    final adapter = _adapter.text.trim();
    final endpoint = _endpoint.text.trim();
    final body = decodeJsonObject(_requestMapping.text) ?? const {};
    final decimalPlaces = int.tryParse(_decimalPlaces.text.trim());
    final windows = _decodeWindows(_windows.text);

    setState(() {
      _saving = true;
      _formError = null;
    });
    final cubit = context.read<ManagedProviderCubit>();
    final secretStore = context.read<ManagedProviderSecretStore>();
    final credentialTransaction = ManagedProviderCredentialTransaction(
      secretStore,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final current = _provider;
    final shouldRunFirstQuery = current == null && _schema.firstQuery;
    final providerId = current?.id ?? 'managed-$now';
    final credentialField = _credentialField.text.trim();
    var credentialRef = _credentialRef.text.trim();
    final credentialSecret = _credentialSecret.text.trim();
    var credentialValues = const <String, String>{};
    final requiredSecretFields = _requiredSecretFields(_schema);
    var requiredSecretsToKeep = requiredSecretFields;
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
      credentialValues = {credentialField: credentialSecret};
      requiredSecretsToKeep = requiredSecretFields
          .where((field) => field != credentialField)
          .toSet();
    }
    if (requiredSecretsToKeep.isNotEmpty) {
      final hasExisting = await _existingCredentialHasRequiredSecrets(
        store: secretStore,
        current: current,
        credentialRef: credentialRef,
        fields: requiredSecretsToKeep,
      );
      if (!mounted) return;
      if (!hasExisting) {
        setState(() {
          _saving = false;
          _formError = context.l10n.managedProvidersMissingCredential;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _credentialSecretFocus.requestFocus();
          final focusContext = _credentialSecretFocus.context;
          if (focusContext != null && focusContext.mounted) {
            Scrollable.ensureVisible(
              focusContext,
              alignment: 0.1,
              duration: const Duration(milliseconds: 200),
            );
          }
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
        body: body,
        headers: _decodeHeaders(_headers.text),
        windows: windows,
        unknownFields: current?.endpointConfig.unknownFields ?? const {},
        credentialSource: _credentialSource.text.trim().isEmpty
            ? 'secret'
            : _credentialSource.text.trim(),
        credentialTemplate: _credentialTemplate.text.trim().isEmpty
            ? null
            : _credentialTemplate.text.trim(),
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
    try {
      await credentialTransaction.run<void>(
        credentialRef: credentialRef,
        nextValues: credentialValues,
        persistProvider: () async {
          await cubit.upsert(next);
          if (cubit.state.errorCode != null) {
            throw const _ManagedProviderEditorPersistenceFailed();
          }
        },
      );
    } on _ManagedProviderEditorPersistenceFailed {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = managedProviderErrorMessage(
          context.l10n,
          providerCode: cubit.state.errorCode,
          detail: cubit.state.errorMessage,
        );
      });
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = context.l10n.managedProvidersCredentialSaveFailed;
      });
      return;
    }
    if (!mounted) return;
    if (shouldRunFirstQuery) {
      await context.read<ManagedProviderUsageCubit>().queryProvider(next);
      if (!mounted) return;
    }
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
    final body = decodeJsonObject(_requestMapping.text);
    if (name.isEmpty || adapter.isEmpty) {
      setState(
        () => _formError = context.l10n.managedProvidersNameAdapterError,
      );
      return null;
    }
    if (body == null || mappingContainsCredentialKey(body)) {
      setState(
        () => _formError = context.l10n.managedProvidersSecretMappingError,
      );
      return null;
    }
    final windows = _decodeWindows(_windows.text);
    final current = _provider;
    if ((adapter == 'http-json' || _kind == ManagedProviderKind.customHttp) &&
        !isAllowedManagedProviderEndpoint(endpoint, allowHttpLocalhost: true)) {
      setState(() => _formError = context.l10n.managedProvidersEndpointError);
      return null;
    }
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
        body: body,
        headers: _decodeHeaders(_headers.text),
        windows: windows,
        credentialSource: _credentialSource.text.trim().isEmpty
            ? 'secret'
            : _credentialSource.text.trim(),
        credentialTemplate: _credentialTemplate.text.trim().isEmpty
            ? null
            : _credentialTemplate.text.trim(),
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

  static String _prettyJson(Map<String, Object?> value) {
    if (value.isEmpty) return '{}';
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  static Map<String, String> _decodeHeaders(String raw) {
    final parsed = decodeJsonObject(raw);
    if (parsed == null) return const {};
    return {
      for (final entry in parsed.entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
  }

  static List<ManagedProviderUsageWindow> _decodeWindows(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map<String, Object?>)
            ManagedProviderUsageWindow.fromJson(item)
          else if (item is Map)
            ManagedProviderUsageWindow.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
      ];
    } on Object {
      return const [];
    }
  }
}

class _ManagedProviderEditorPersistenceFailed implements Exception {
  const _ManagedProviderEditorPersistenceFailed();
}

Set<String> _requiredSecretFields(ManagedProviderEditorSchema schema) => {
  for (final field in schema.fields)
    if (field.kind == ManagedProviderEditorFieldKind.secret && field.required)
      field.key,
};

Future<bool> _existingCredentialHasRequiredSecrets({
  required ManagedProviderSecretStore store,
  required ManagedProvider? current,
  required String credentialRef,
  required Set<String> fields,
}) async {
  final currentRef = current?.credentialRef?.trim() ?? '';
  if (fields.isEmpty) return true;
  if (current == null || credentialRef.isEmpty || credentialRef != currentRef) {
    return false;
  }
  try {
    final scope = await store.read(credentialRef);
    return fields.every((field) => scope.valueFor(field)?.isNotEmpty ?? false);
  } on Object {
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
        Expanded(child: Text(title, style: TpTextStyles.of(context).xl)),
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
    child: Text(
      message,
      style: TpTextStyles.of(
        context,
      ).smColored(Theme.of(context).colorScheme.onErrorContainer),
    ),
  );
}
