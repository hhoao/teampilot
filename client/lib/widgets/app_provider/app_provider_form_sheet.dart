import 'dart:convert';

import 'package:flutter/material.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/provider_presets/claude_provider_presets.dart';
import '../../models/provider_presets/codex_provider_presets.dart';
import '../../models/provider_presets/flashskyai_provider_presets.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/debounce/debounce.dart';
import '../dropdown/flashsky_dropdown_field.dart';
import '../dropdown/flashskyai_dropdown_decoration.dart';

List<AppProviderPreset> appProviderPresetsFor(AppProviderCli cli) {
  return switch (cli) {
    AppProviderCli.claude => ClaudeProviderPresets.all,
    AppProviderCli.codex => CodexProviderPresets.all,
    AppProviderCli.flashskyai => FlashskyaiProviderPresets.all,
  };
}

class AppProviderFormPage extends StatefulWidget {
  const AppProviderFormPage({
    required this.cli,
    required this.onCancel,
    required this.onSaved,
    this.existing,
    this.onCliChanged,
    super.key,
  });

  final AppProviderCli cli;
  final AppProviderConfig? existing;
  final ValueChanged<AppProviderCli>? onCliChanged;
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
  late final TextEditingController _haikuModelCtl;
  late final TextEditingController _sonnetModelCtl;
  late final TextEditingController _opusModelCtl;
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
  late String _claudeApiFormat;
  late bool _showAdvancedJson;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtl = TextEditingController(text: e?.name ?? '');
    _notesCtl = TextEditingController(text: e?.notes ?? '');
    _websiteCtl = TextEditingController(text: e?.websiteUrl ?? '');
    _apiKeyCtl = TextEditingController(text: _isEditing ? '' : e?.apiKey ?? '');
    _baseUrlCtl = TextEditingController(text: e?.baseUrl ?? '');
    _defaultModelCtl = TextEditingController(text: e?.defaultModel ?? '');
    _presetId = 'custom';
    _category = e?.category ?? AppProviderCategory.custom;
    _apiKeyField = _initialApiKeyField(widget.cli, e?.apiKeyField);
    _apiKeyUrl = e?.apiKeyUrl ?? '';
    _icon = e?.icon ?? '';
    _iconColor = e?.iconColor ?? '';
    _isOfficial = e?.isOfficial ?? false;
    _isPartner = e?.isPartner ?? false;
    _partnerPromotionKey = e?.partnerPromotionKey ?? '';
    _endpointCandidates = e?.endpointCandidates.toList() ?? const [];
    _config = Map<String, Object?>.from(
      e?.config ?? _defaultConfig(widget.cli),
    );
    final env = _claudeEnvFromConfig(_config);
    _haikuModelCtl = TextEditingController(
      text: env['ANTHROPIC_DEFAULT_HAIKU_MODEL']?.toString() ?? '',
    );
    _sonnetModelCtl = TextEditingController(
      text: env['ANTHROPIC_DEFAULT_SONNET_MODEL']?.toString() ?? '',
    );
    _opusModelCtl = TextEditingController(
      text: env['ANTHROPIC_DEFAULT_OPUS_MODEL']?.toString() ?? '',
    );
    _claudeApiFormat = _config['apiFormat']?.toString() ?? 'anthropic';
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
      _syncStateForCli(widget.cli);
    }
  }

  void _syncStateForCli(AppProviderCli cli) {
    final presetIds = appProviderPresetsFor(cli).map((p) => p.id);
    if (_presetId != 'custom' && !presetIds.contains(_presetId)) {
      _presetId = 'custom';
    }
    _config = _defaultConfig(cli);
    _apiKeyField = _defaultApiKeyField(cli);
    _claudeApiFormat = _config['apiFormat']?.toString() ?? 'anthropic';
    if (cli != AppProviderCli.claude) {
      _haikuModelCtl.clear();
      _sonnetModelCtl.clear();
      _opusModelCtl.clear();
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _notesCtl.dispose();
    _websiteCtl.dispose();
    _apiKeyCtl.dispose();
    _baseUrlCtl.dispose();
    _defaultModelCtl.dispose();
    _haikuModelCtl.dispose();
    _sonnetModelCtl.dispose();
    _opusModelCtl.dispose();
    _jsonCtl.dispose();
    super.dispose();
  }

  void _applyPreset(String presetId) {
    if (presetId == 'custom') {
      setState(() => _presetId = presetId);
      return;
    }
    final preset = appProviderPresetsFor(
      widget.cli,
    ).where((p) => p.id == presetId).firstOrNull;
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
      _claudeApiFormat = _config['apiFormat']?.toString() ?? 'anthropic';
      _nameCtl.text = t.name;
      _websiteCtl.text = t.websiteUrl;
      _baseUrlCtl.text = t.baseUrl;
      _defaultModelCtl.text = t.defaultModel;
      final env = _claudeEnvFromConfig(_config);
      _haikuModelCtl.text =
          env['ANTHROPIC_DEFAULT_HAIKU_MODEL']?.toString() ?? '';
      _sonnetModelCtl.text =
          env['ANTHROPIC_DEFAULT_SONNET_MODEL']?.toString() ?? '';
      _opusModelCtl.text =
          env['ANTHROPIC_DEFAULT_OPUS_MODEL']?.toString() ?? '';
      _jsonCtl.text = const JsonEncoder.withIndent(
        '  ',
      ).convert(_buildNormalDraft().toJson());
    });
  }

  AppProviderConfig _buildNormalDraft() {
    final name = _nameCtl.text.trim();
    final baseId = widget.existing?.id ?? AppProviderCubit.slugifyId(name);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final config = _buildConfigFromFields();
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
      unknownFields: widget.existing?.unknownFields ?? const {},
    );
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final presetItems = [
      'custom',
      ...appProviderPresetsFor(widget.cli).map((p) => p.id),
    ];

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
                    child: FlashskyDropdownField<AppProviderCli>(
                      items: AppProviderCli.values,
                      initialItem: widget.cli,
                      decoration: FlashskyDropdownDecorations.denseField(
                        context,
                      ),
                      itemLabel: l10n.appProviderCliLabel,
                      onChanged: (cli) {
                        if (cli != null && cli != widget.cli) {
                          widget.onCliChanged?.call(cli);
                        }
                      },
                    ),
                  ),
                IconButton(
                  tooltip: l10n.cancel,
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close),
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
                FlashskyDropdownField<String>(
                  key: ValueKey('app-provider-preset-${widget.cli.value}'),
                  items: presetItems,
                  initialItem: _effectiveItem(_presetId, presetItems),
                  decoration: FlashskyDropdownDecorations.denseField(context),
                  itemLabel: (id) {
                    if (id == 'custom') return l10n.appProviderPresetCustom;
                    return appProviderPresetsFor(widget.cli)
                            .where((p) => p.id == id)
                            .map((p) => p.label)
                            .firstOrNull ??
                        id;
                  },
                  onChanged: (id) {
                    if (id != null) _applyPreset(id);
                  },
                ),
                const SizedBox(height: 14),
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlCtl,
                    decoration: InputDecoration(labelText: l10n.baseUrl),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _defaultModelCtl,
                    decoration: InputDecoration(labelText: l10n.defaultModel),
                  ),
                  if (widget.cli == AppProviderCli.claude) ...[
                    const SizedBox(height: 16),
                    _ClaudeAdvancedOptions(
                      apiFormat: _claudeApiFormat,
                      apiKeyField: _apiKeyField,
                      haikuModelCtl: _haikuModelCtl,
                      sonnetModelCtl: _sonnetModelCtl,
                      opusModelCtl: _opusModelCtl,
                      onApiFormatChanged: (value) {
                        setState(() => _claudeApiFormat = value);
                      },
                      onApiKeyFieldChanged: (value) {
                        setState(() => _apiKeyField = value);
                      },
                    ),
                  ],
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
                      icon: const Icon(Icons.check),
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

  Map<String, Object?> _buildConfigFromFields() {
    if (widget.cli != AppProviderCli.claude) return _config;

    final config = Map<String, Object?>.from(_config);
    final env = _claudeEnvFromConfig(config);
    final baseUrl = _baseUrlCtl.text.trim();
    final mainModel = _defaultModelCtl.text.trim();
    final haikuModel = _haikuModelCtl.text.trim();
    final sonnetModel = _sonnetModelCtl.text.trim();
    final opusModel = _opusModelCtl.text.trim();

    void setOrRemove(String key, String value) {
      if (value.isEmpty) {
        env.remove(key);
      } else {
        env[key] = value;
      }
    }

    setOrRemove('ANTHROPIC_BASE_URL', baseUrl);
    setOrRemove('ANTHROPIC_MODEL', mainModel);
    setOrRemove('ANTHROPIC_DEFAULT_HAIKU_MODEL', haikuModel);
    setOrRemove('ANTHROPIC_DEFAULT_SONNET_MODEL', sonnetModel);
    setOrRemove('ANTHROPIC_DEFAULT_OPUS_MODEL', opusModel);

    config['env'] = env;
    config['apiFormat'] = _claudeApiFormat;
    config['api_key_field'] = _apiKeyField;
    return config;
  }
}

class _ClaudeAdvancedOptions extends StatelessWidget {
  const _ClaudeAdvancedOptions({
    required this.apiFormat,
    required this.apiKeyField,
    required this.haikuModelCtl,
    required this.sonnetModelCtl,
    required this.opusModelCtl,
    required this.onApiFormatChanged,
    required this.onApiKeyFieldChanged,
  });

  final String apiFormat;
  final String apiKeyField;
  final TextEditingController haikuModelCtl;
  final TextEditingController sonnetModelCtl;
  final TextEditingController opusModelCtl;
  final ValueChanged<String> onApiFormatChanged;
  final ValueChanged<String> onApiKeyFieldChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          l10n.appProviderAdvancedOptions,
          style: theme.textTheme.titleSmall,
        ),
        children: [
          const SizedBox(height: 8),
          _FieldLabel(l10n.appProviderClaudeApiFormat),
          const SizedBox(height: 6),
          FlashskyDropdownField<String>(
            items: _claudeApiFormats,
            initialItem: _effectiveItem(apiFormat, _claudeApiFormats),
            decoration: FlashskyDropdownDecorations.denseField(context),
            itemLabel: l10n.appProviderClaudeApiFormatOption,
            onChanged: (value) {
              if (value != null) onApiFormatChanged(value);
            },
          ),
          const SizedBox(height: 6),
          Text(
            l10n.appProviderClaudeApiFormatHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(l10n.appProviderClaudeAuthField),
          const SizedBox(height: 6),
          FlashskyDropdownField<String>(
            items: _claudeApiKeyFields,
            initialItem: _effectiveItem(apiKeyField, _claudeApiKeyFields),
            decoration: FlashskyDropdownDecorations.denseField(context),
            itemLabel: l10n.appProviderClaudeAuthFieldOption,
            onChanged: (value) {
              if (value != null) onApiKeyFieldChanged(value);
            },
          ),
          const SizedBox(height: 6),
          Text(
            l10n.appProviderClaudeAuthFieldHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            l10n.appProviderClaudeModelMapping,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.appProviderClaudeModelMappingHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 680;
              final fields = [
                TextField(
                  controller: haikuModelCtl,
                  decoration: InputDecoration(
                    labelText: l10n.appProviderClaudeHaikuModel,
                  ),
                ),
                TextField(
                  controller: sonnetModelCtl,
                  decoration: InputDecoration(
                    labelText: l10n.appProviderClaudeSonnetModel,
                  ),
                ),
                TextField(
                  controller: opusModelCtl,
                  decoration: InputDecoration(
                    labelText: l10n.appProviderClaudeOpusModel,
                  ),
                ),
              ];
              if (!twoColumns) {
                return Column(
                  children: [
                    for (final field in fields) ...[
                      field,
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  fields[2],
                ],
              );
            },
          ),
        ],
      ),
    );
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

String _defaultApiKeyField(AppProviderCli cli) {
  return switch (cli) {
    AppProviderCli.claude => 'ANTHROPIC_AUTH_TOKEN',
    AppProviderCli.codex => 'OPENAI_API_KEY',
    AppProviderCli.flashskyai => 'api_key',
  };
}

String _initialApiKeyField(AppProviderCli cli, String? raw) {
  final value = raw?.trim() ?? '';
  if (cli == AppProviderCli.claude) {
    return _claudeApiKeyFields.contains(value)
        ? value
        : _defaultApiKeyField(cli);
  }
  return value.isEmpty ? _defaultApiKeyField(cli) : value;
}

Map<String, Object?> _defaultConfig(AppProviderCli cli) {
  return switch (cli) {
    AppProviderCli.claude => {'env': <String, Object?>{}},
    AppProviderCli.codex => {'auth': <String, Object?>{}},
    AppProviderCli.flashskyai => {'provider_type': 'openai'},
  };
}

Map<String, Object?> _claudeEnvFromConfig(Map<String, Object?> config) {
  final raw = config['env'];
  return raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{};
}

const _claudeApiFormats = [
  'anthropic',
  'openai_chat',
  'openai_responses',
  'gemini_native',
];

const _claudeApiKeyFields = ['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY'];

T _effectiveItem<T>(T value, List<T> items) {
  return items.contains(value) ? value : items.first;
}
