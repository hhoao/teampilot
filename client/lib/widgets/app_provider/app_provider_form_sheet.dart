import 'dart:convert';

import 'package:flutter/material.dart';
import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../app_outline_text_field.dart';
import '../dropdown/flashsky_dropdown_field.dart';
import '../dropdown/flashskyai_dropdown_decoration.dart';

/// Full add/edit panel for a unified app-level provider.
Future<AppProviderConfig?> showAppProviderFormSheet(
  BuildContext context, {
  AppProviderConfig? existing,
}) {
  return showModalBottomSheet<AppProviderConfig>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AppProviderFormSheet(existing: existing),
  );
}

class _AppProviderFormSheet extends StatefulWidget {
  const _AppProviderFormSheet({this.existing});

  final AppProviderConfig? existing;

  @override
  State<_AppProviderFormSheet> createState() => _AppProviderFormSheetState();
}

class _AppProviderFormSheetState extends State<_AppProviderFormSheet> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _notesCtl;
  late final TextEditingController _websiteCtl;
  late final TextEditingController _apiKeyCtl;
  late final TextEditingController _baseUrlCtl;
  late final TextEditingController _defaultModelCtl;
  late final TextEditingController _jsonCtl;

  late String _presetId;
  late AppProviderCategory _category;
  late Set<AppProviderTool> _enabledTools;
  late AppProviderToolConfigs _toolConfigs;
  late String _apiKeyField;
  late String _icon;
  late String _managedAccountId;
  late bool _showAdvancedJson;
  late bool _isEditing;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _isEditing = e != null;
    _nameCtl = TextEditingController(text: e?.name ?? '');
    _notesCtl = TextEditingController(text: e?.notes ?? '');
    _websiteCtl = TextEditingController(text: e?.websiteUrl ?? '');
    _apiKeyCtl = TextEditingController(text: _isEditing ? '' : (e?.apiKey ?? ''));
    _baseUrlCtl = TextEditingController(text: e?.baseUrl ?? '');
    _defaultModelCtl = TextEditingController(text: e?.defaultModel ?? '');
    _presetId = 'custom';
    _category = e?.category ?? AppProviderCategory.custom;
    _enabledTools = e != null
        ? e.enabledTools.toSet()
        : {AppProviderTool.flashskyai};
    _toolConfigs = e?.toolConfigs ?? const AppProviderToolConfigs();
    _apiKeyField = e?.apiKeyField ?? 'api_key';
    _icon = e?.icon ?? '';
    _managedAccountId = e?.managedAccountId ?? '';
    _showAdvancedJson = false;
    _jsonCtl = TextEditingController(
      text: e != null
          ? const JsonEncoder.withIndent('  ').convert(e.toJson())
          : '{}',
    );
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
    final preset = AppProviderPresets.byId(presetId);
    if (preset == null) return;
    final t = preset.template;
    setState(() {
      _presetId = presetId;
      _category = t.category;
      _enabledTools = t.enabledTools.toSet();
      _toolConfigs = t.toolConfigs;
      _apiKeyField = t.apiKeyField;
      _icon = t.icon;
      _managedAccountId = t.managedAccountId;
      _nameCtl.text = t.name;
      _websiteCtl.text = t.websiteUrl;
      _baseUrlCtl.text = t.baseUrl;
      _defaultModelCtl.text = t.defaultModel;
      _jsonCtl.text = const JsonEncoder.withIndent('  ').convert(t.toJson());
    });
  }

  AppProviderConfig _buildNormalDraft() {
    final name = _nameCtl.text.trim();
    final baseId = widget.existing?.id ?? AppProviderCubit.slugifyId(name);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    return AppProviderConfig(
      id: baseId,
      name: name,
      notes: _notesCtl.text.trim(),
      websiteUrl: _websiteCtl.text.trim(),
      category: _category,
      apiKey: _apiKeyCtl.text.trim(),
      apiKeyField: _apiKeyField,
      baseUrl: _baseUrlCtl.text.trim(),
      defaultModel: _defaultModelCtl.text.trim(),
      icon: _icon,
      enabledTools: AppProviderTool.values
          .where((t) => _enabledTools.contains(t))
          .toList(growable: false),
      toolConfigs: _toolConfigs,
      commonConfigEnabled: widget.existing?.commonConfigEnabled ?? false,
      managedAccountId: _managedAccountId,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      unknownFields: widget.existing?.unknownFields ?? const {},
    );
  }

  AppProviderConfig? _buildResult() {
    if (_showAdvancedJson) {
      try {
        final decoded = jsonDecode(_jsonCtl.text);
        if (decoded is! Map) return null;
        return AppProviderConfig.fromJson(Map<String, Object?>.from(decoded));
      } on Object {
        return null;
      }
    }

    final name = _nameCtl.text.trim();
    if (name.isEmpty) return null;
    return _buildNormalDraft();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final requiresApiKey =
        _category == AppProviderCategory.thirdParty ||
        _category == AppProviderCategory.aggregator;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Material(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEditing ? l10n.editProvider : l10n.addProvider,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      Text(
                        l10n.appProviderPresetLabel,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      FlashskyDropdownField<String>(
                        items: AppProviderPresets.all.map((p) => p.id).toList(),
                        initialItem: _presetId,
                        decoration: FlashskyDropdownDecorations.denseField(
                          context,
                        ),
                        itemLabel: (id) =>
                            AppProviderPresets.byId(id)?.label ?? id,
                        onChanged: (id) {
                          if (id != null) _applyPreset(id);
                        },
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
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
                      if (_showAdvancedJson) ...[
                        AppOutlineTextField(
                          controller: _jsonCtl,
                          minLines: 12,
                          maxLines: 24,
                        ),
                      ] else ...[
                        AppOutlineTextField(
                          controller: _nameCtl,
                          labelText: l10n.providerName,
                        ),
                        const SizedBox(height: 12),
                        AppOutlineTextField(
                          controller: _websiteCtl,
                          labelText: l10n.appProviderWebsite,
                        ),
                        const SizedBox(height: 12),
                        AppOutlineTextField(
                          controller: _notesCtl,
                          labelText: l10n.notes,
                          minLines: 2,
                          maxLines: 4,
                        ),
                        if (requiresApiKey) ...[
                          const SizedBox(height: 12),
                          AppOutlineTextField(
                            controller: _apiKeyCtl,
                            labelText: l10n.apiKey,
                            hintText: _isEditing ? l10n.appProviderApiKeyEditHint : null,
                            obscureText: true,
                          ),
                          const SizedBox(height: 12),
                          AppOutlineTextField(
                            controller: _baseUrlCtl,
                            labelText: l10n.baseUrl,
                          ),
                          const SizedBox(height: 12),
                          AppOutlineTextField(
                            controller: _defaultModelCtl,
                            labelText: l10n.defaultModel,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          l10n.appProviderEnabledTools,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        for (final tool in AppProviderTool.values)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_toolLabel(l10n, tool)),
                            value: _enabledTools.contains(tool),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _enabledTools.add(tool);
                                } else {
                                  _enabledTools.remove(tool);
                                }
                              });
                            },
                          ),
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(l10n.cancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final result = _buildResult();
                              if (result == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.invalidJson)),
                                );
                                return;
                              }
                              Navigator.pop(context, result);
                            },
                            child: Text(l10n.save),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _toolLabel(dynamic l10n, AppProviderTool tool) {
    return switch (tool) {
      AppProviderTool.flashskyai => l10n.appProviderToolFlashskyai,
      AppProviderTool.codex => l10n.appProviderToolCodex,
      AppProviderTool.claude => l10n.appProviderToolClaude,
    };
  }
}
