import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../services/cli/registry/capabilities/cli_effort_capability.dart';
import '../../services/cli/registry/capabilities/provider_credential_capability.dart';
import '../../services/cli/registry/capabilities/provider_form_capability.dart';
import '../../services/cli/registry/capabilities/provider_model_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/provider/codex/codex_provider_form_capability.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/debounce/debounce.dart';
import '../app_icon_button.dart';
import 'brand_dropdown_rows.dart';
import 'cli_effort_picker_field.dart';
import 'provider_credential_action_bar.dart';
import 'provider_model_picker_field.dart';
import '../dropdown/app_dropdown_field.dart';

class AppProviderFormPage extends StatefulWidget {
  const AppProviderFormPage({
    required this.cli,
    required this.onCancel,
    required this.onSaved,
    this.existing,
    this.onCliChanged,
    super.key,
  });

  final CliTool cli;
  final AppProviderConfig? existing;
  final ValueChanged<CliTool>? onCliChanged;
  final VoidCallback onCancel;
  final ValueChanged<AppProviderConfig> onSaved;

  @override
  State<AppProviderFormPage> createState() => _AppProviderFormPageState();
}

class _AppProviderFormPageState extends State<AppProviderFormPage> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _notesCtl;
  late final TextEditingController _websiteCtl;
  late final TextEditingController _apiKeyCtl;
  late final TextEditingController _baseUrlCtl;
  late final TextEditingController _defaultModelCtl;
  late final TextEditingController _jsonCtl;

  late String _presetId;
  late AppProviderCategory _category;
  late String _apiKeyField;
  late String _apiKeyUrl;
  late String _icon;
  late String _iconColor;
  late bool _isOfficial;
  late bool _isPartner;
  late String _partnerPromotionKey;
  late List<String> _endpointCandidates;
  late Map<String, Object?> _config;
  late Map<String, Object?> _extra;
  late bool _showAdvancedJson;

  bool get _isEditing => widget.existing != null;

  CliToolRegistry _registry([BuildContext? context]) =>
      (context != null ? CliToolRegistryScope.maybeOf(context) : null) ??
      CliToolRegistry.builtIn();

  ProviderFormCapability _formCap([BuildContext? context]) {
    final cap = _registry(context).capability<ProviderFormCapability>(widget.cli);
    assert(cap != null, '${widget.cli.value} missing ProviderFormCapability');
    return cap!;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final formCap = _formCap();
    _nameCtl = TextEditingController(text: e?.name ?? '');
    _notesCtl = TextEditingController(text: e?.notes ?? '');
    _websiteCtl = TextEditingController(text: e?.websiteUrl ?? '');
    _apiKeyCtl = TextEditingController(text: _isEditing ? '' : e?.apiKey ?? '');
    _baseUrlCtl = TextEditingController(text: e?.baseUrl ?? '');
    _defaultModelCtl = TextEditingController(text: e?.defaultModel ?? '');
    _presetId = _initialPresetId(formCap, e);
    _category = e?.category ?? AppProviderCategory.custom;
    _apiKeyField = formCap.normalizeApiKeyField(e?.apiKeyField);
    _apiKeyUrl = e?.apiKeyUrl ?? '';
    _icon = e?.icon ?? '';
    _iconColor = e?.iconColor ?? '';
    _isOfficial = e?.isOfficial ?? false;
    _isPartner = e?.isPartner ?? false;
    _partnerPromotionKey = e?.partnerPromotionKey ?? '';
    _endpointCandidates = e?.endpointCandidates.toList() ?? const [];
    _config = Map<String, Object?>.from(
      e?.config ?? formCap.defaultConfig(),
    );
    _extra = formCap.extraFromExisting(e);
    _showAdvancedJson = false;
    _jsonCtl = TextEditingController(
      text: e != null
          ? const JsonEncoder.withIndent('  ').convert(e.toJson())
          : '{}',
    );
  }

  @override
  void didUpdateWidget(covariant AppProviderFormPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cli != widget.cli) {
      _syncStateForCli();
    }
  }

  void _syncStateForCli() {
    final formCap = _formCap();
    final presetIds = formCap.presets.map((p) => p.id);
    if (_presetId != 'custom' && !presetIds.contains(_presetId)) {
      _presetId = 'custom';
    }
    _config = formCap.configForCliSwitch();
    _apiKeyField = formCap.defaultApiKeyField();
    _extra = const {};
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _notesCtl.dispose();
    _websiteCtl.dispose();
    _apiKeyCtl.dispose();
    _baseUrlCtl.dispose();
    _defaultModelCtl.dispose();
    _jsonCtl.dispose();
    super.dispose();
  }

  void _applyPreset(String presetId) {
    if (presetId == 'custom') {
      setState(() => _presetId = presetId);
      return;
    }
    final formCap = _formCap();
    final preset = formCap.presets.where((p) => p.id == presetId).firstOrNull;
    if (preset == null) return;
    final t = preset.template;
    setState(() {
      _presetId = presetId;
      _category = t.category;
      _apiKeyField = t.apiKeyField;
      _apiKeyUrl = t.apiKeyUrl;
      _icon = t.icon;
      _iconColor = t.iconColor;
      _isOfficial = t.isOfficial;
      _isPartner = t.isPartner;
      _partnerPromotionKey = t.partnerPromotionKey;
      _endpointCandidates = t.endpointCandidates.toList();
      _config = Map<String, Object?>.from(t.config);
      _extra = formCap.extraFromPreset(preset);
      _nameCtl.text = t.name;
      _websiteCtl.text = t.websiteUrl;
      _baseUrlCtl.text = t.baseUrl;
      _defaultModelCtl.text = t.defaultModel;
      _jsonCtl.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(_buildNormalDraft().toJson());
    });
  }

  ProviderFormInput _formInput() {
    return ProviderFormInput(
      baseUrl: _baseUrlCtl.text,
      defaultModel: _defaultModelCtl.text,
      apiKeyField: _apiKeyField,
      config: _config,
      extra: _extra,
    );
  }

  AppProviderConfig _buildNormalDraft() {
    final name = _nameCtl.text.trim();
    final baseId = widget.existing?.id ?? AppProviderCubit.slugifyId(name);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final config = _formCap().buildConfig(_formInput());
    return AppProviderConfig(
      id: baseId,
      cli: widget.cli,
      name: name,
      notes: _notesCtl.text.trim(),
      websiteUrl: _websiteCtl.text.trim(),
      apiKeyUrl: _apiKeyUrl,
      category: _category,
      apiKey: _apiKeyCtl.text.trim(),
      apiKeyField: _apiKeyField,
      baseUrl: _baseUrlCtl.text.trim(),
      defaultModel: _defaultModelCtl.text.trim(),
      icon: _icon,
      iconColor: _iconColor,
      isOfficial: _isOfficial,
      isPartner: _isPartner,
      partnerPromotionKey: _partnerPromotionKey,
      endpointCandidates: _endpointCandidates,
      config: config,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      credentialStatus: widget.existing?.credentialStatus ?? 'missing',
      credentialUpdatedAt: widget.existing?.credentialUpdatedAt ?? 0,
      unknownFields: widget.existing?.unknownFields ?? const {},
    );
  }

  AppProviderConfig _credentialProvider(AppProviderState state) {
    final draft = _buildNormalDraft();
    final saved = state.providersFor(widget.cli)
        .where((p) => p.id == draft.id)
        .firstOrNull;
    return saved ?? draft;
  }

  AppProviderConfig? _buildResult() {
    if (_showAdvancedJson) {
      try {
        final decoded = jsonDecode(_jsonCtl.text);
        if (decoded is! Map) return null;
        return AppProviderConfig.fromJson(
          Map<String, Object?>.from(decoded),
          cliFallback: widget.cli,
        ).copyWith(cli: widget.cli);
      } on Object {
        return null;
      }
    }

    if (_nameCtl.text.trim().isEmpty) return null;
    return _buildNormalDraft();
  }

  String get _codexEffort =>
      _extra[CodexFormExtraKeys.effort]?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final formCap = _formCap(context);
    final presetItems = ['custom', ...formCap.presets.map((p) => p.id)];

    return Material(
      color: cs.workspaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? l10n.editProvider : l10n.addProvider,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                if (!_isEditing && widget.onCliChanged != null)
                  SizedBox(
                    width: 180,
                    child: AppDropdownField<CliTool>(
                      items: CliTool.values,
                      initialItem: widget.cli,
                      itemBuilder: (context, cli) => cliDropdownRow(
                        context,
                        cli: cli,
                        label: l10n.appProviderToolLabel(cli),
                      ),
                      onChanged: (cli) {
                        if (cli != null && cli != widget.cli) {
                          widget.onCliChanged?.call(cli);
                        }
                      },
                    ),
                  ),
                AppIconButton(
                  icon: Icons.close,
                  tooltip: l10n.cancel,
                  onTap: widget.onCancel,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: [
                Text(
                  l10n.appProviderPresetLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                AppDropdownField<String>(
                  key: ValueKey('app-provider-preset-${widget.cli.value}'),
                  items: presetItems,
                  initialItem: _effectiveItem(_presetId, presetItems),
                  itemBuilder: (context, id) {
                    if (id == 'custom') {
                      return Text(l10n.appProviderPresetCustom);
                    }
                    final preset = formCap.presets
                        .where((p) => p.id == id)
                        .firstOrNull;
                    final label = preset?.label ?? id;
                    return providerDropdownRow(
                      context,
                      label: label,
                      provider: preset?.template,
                    );
                  },
                  onChanged: (id) {
                    if (id != null) _applyPreset(id);
                  },
                ),
                const SizedBox(height: 14),
                if (!_showAdvancedJson && _usesCredentialSetup(context)) ...[
                  BlocBuilder<AppProviderCubit, AppProviderState>(
                    builder: (context, state) {
                      return ProviderCredentialActionBar(
                        provider: _credentialProvider(state),
                        ensureSaved: () async {
                          final next = _buildNormalDraft();
                          if (next.name.trim().isEmpty) return null;
                          final cubit = context.read<AppProviderCubit>();
                          await cubit.upsertProvider(next);
                          return cubit.state.providersFor(widget.cli)
                                  .where((p) => p.id == next.id)
                                  .firstOrNull ??
                              next;
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.appProviderAdvancedJson),
                    value: _showAdvancedJson,
                    onChanged: (v) {
                      setState(() {
                        if (v) {
                          _jsonCtl.text = const JsonEncoder.withIndent(
                            '  ',
                          ).convert(_buildNormalDraft().toJson());
                        }
                        _showAdvancedJson = v;
                      });
                    },
                  ),
                ),
                if (_showAdvancedJson)
                  TextField(
                    controller: _jsonCtl,
                    minLines: 16,
                    maxLines: 28,
                    decoration: const InputDecoration(),
                  )
                else ...[
                  TextField(
                    controller: _nameCtl,
                    decoration: InputDecoration(labelText: l10n.providerName),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _websiteCtl,
                    decoration: InputDecoration(
                      labelText: l10n.appProviderWebsite,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesCtl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: l10n.notes),
                  ),
                  if (!_hidesApiKeyFields(context)) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyCtl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.apiKey,
                        hintText: _isEditing
                            ? l10n.appProviderApiKeyEditHint
                            : null,
                      ),
                    ),
                  ],
                  if (!_hidesApiKeyFields(context)) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _baseUrlCtl,
                      decoration: InputDecoration(labelText: l10n.baseUrl),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _DefaultModelField(
                    cli: widget.cli,
                    draftProvider: _buildNormalDraft,
                    controller: _defaultModelCtl,
                    label: l10n.defaultModel,
                    onChanged: () => setState(() {}),
                  ),
                  if (_showsProviderEffortPicker(context)) ...[
                    const SizedBox(height: 12),
                    _FieldLabel(l10n.providerEffortLevel),
                    const SizedBox(height: 6),
                    CliEffortPickerField(
                      cli: widget.cli,
                      value: _codexEffort,
                      provider: _buildNormalDraft(),
                      model: _defaultModelCtl.text,
                      onChanged: (value) => setState(() {
                        _extra = {
                          ..._extra,
                          CodexFormExtraKeys.effort: value,
                        };
                      }),
                    ),
                  ],
                  formCap.buildExtraSection(
                    context,
                    ProviderFormSectionProps(
                      config: _config,
                      apiKeyField: _apiKeyField,
                      baseUrl: _baseUrlCtl.text,
                      defaultModel: _defaultModelCtl.text,
                      extra: _extra,
                      onExtraChanged: (next) => setState(() => _extra = next),
                      onApiKeyFieldChanged: (value) =>
                          setState(() => _apiKeyField = value),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onCancel,
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: throttledOnPressed(
                        'app_provider_form_save',
                        () {
                          final result = _buildResult();
                          if (result == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l10n.invalidJson)),
                            );
                            return;
                          }
                          widget.onSaved(result);
                        },
                      ),
                      icon: Icon(Icons.check),
                      label: Text(l10n.save),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _usesCredentialSetup(BuildContext context) {
    final capability = _registry(
      context,
    ).capability<ProviderCredentialCapability>(widget.cli);
    if (capability == null) return false;
    final draft = _buildNormalDraft();
    if (capability.appliesTo(draft)) return true;
    final existing = widget.existing;
    return existing != null && capability.appliesTo(existing);
  }

  bool _showsProviderEffortPicker(BuildContext context) {
    final capability = _registry(context).capability<CliEffortCapability>(widget.cli);
    if (capability == null) return false;
    final draft = _buildNormalDraft();
    if (capability.providerPickerPlacement(draft) !=
        EffortPickerPlacement.provider) {
      return false;
    }
    return capability.isApplicable(model: _defaultModelCtl.text);
  }

  bool _hidesApiKeyFields(BuildContext context) {
    final capability = _registry(
      context,
    ).capability<ProviderCredentialCapability>(widget.cli);
    if (capability == null) return false;
    final draft = _buildNormalDraft();
    if (capability.hidesApiKeyFields(draft)) return true;
    final existing = widget.existing;
    return existing != null && capability.hidesApiKeyFields(existing);
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _DefaultModelField extends StatelessWidget {
  const _DefaultModelField({
    required this.cli,
    required this.draftProvider,
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final CliTool cli;
  final AppProviderConfig Function() draftProvider;
  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final draft = draftProvider();
    final registry = CliToolRegistryScope.maybeOf(context) ?? CliToolRegistry.builtIn();
    final capability = registry.capability<ProviderModelCapability>(cli);
    if (capability != null &&
        capability.pickerMode(draft) != ProviderModelPickerMode.hidden) {
      return ProviderModelPickerField(
        cli: cli,
        providerId: draft.id,
        provider: draft,
        value: controller.text,
        hintText: label,
        onChanged: (value) {
          controller.text = value;
          onChanged();
        },
      );
    }

    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => onChanged(),
    );
  }
}

T _effectiveItem<T>(T value, List<T> items) {
  return items.contains(value) ? value : items.first;
}

String _initialPresetId(ProviderFormCapability formCap, AppProviderConfig? existing) {
  if (existing == null) return 'custom';
  for (final preset in formCap.presets) {
    if (preset.id == existing.id) return preset.id;
  }
  return 'custom';
}
