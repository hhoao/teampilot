import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/provider/claude/claude_provider_form_capability.dart';
import '../dropdown/app_dropdown_field.dart';

const _apiFormats = [
  'anthropic',
  'openai_chat',
  'openai_responses',
  'gemini_native',
];

const _apiKeyFields = ['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY'];

class ClaudeProviderFormSection extends StatefulWidget {
  const ClaudeProviderFormSection({
    required this.apiKeyField,
    required this.extra,
    required this.onExtraChanged,
    required this.onApiKeyFieldChanged,
    super.key,
  });

  final String apiKeyField;
  final Map<String, Object?> extra;
  final ValueChanged<Map<String, Object?>> onExtraChanged;
  final ValueChanged<String> onApiKeyFieldChanged;

  @override
  State<ClaudeProviderFormSection> createState() =>
      _ClaudeProviderFormSectionState();
}

class _ClaudeProviderFormSectionState extends State<ClaudeProviderFormSection> {
  late final TextEditingController _haikuModelCtl;
  late final TextEditingController _sonnetModelCtl;
  late final TextEditingController _opusModelCtl;

  @override
  void initState() {
    super.initState();
    _haikuModelCtl = TextEditingController(text: _text(ClaudeFormExtraKeys.haikuModel));
    _sonnetModelCtl = TextEditingController(text: _text(ClaudeFormExtraKeys.sonnetModel));
    _opusModelCtl = TextEditingController(text: _text(ClaudeFormExtraKeys.opusModel));
  }

  @override
  void didUpdateWidget(covariant ClaudeProviderFormSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extra != widget.extra) {
      _syncController(_haikuModelCtl, ClaudeFormExtraKeys.haikuModel);
      _syncController(_sonnetModelCtl, ClaudeFormExtraKeys.sonnetModel);
      _syncController(_opusModelCtl, ClaudeFormExtraKeys.opusModel);
    }
  }

  @override
  void dispose() {
    _haikuModelCtl.dispose();
    _sonnetModelCtl.dispose();
    _opusModelCtl.dispose();
    super.dispose();
  }

  String _text(String key) => widget.extra[key]?.toString() ?? '';

  void _syncController(TextEditingController controller, String key) {
    final next = _text(key);
    if (controller.text != next) {
      controller.text = next;
    }
  }

  void _patchExtra(String key, String value) {
    widget.onExtraChanged({...widget.extra, key: value});
  }

  String get _apiFormat =>
      widget.extra[ClaudeFormExtraKeys.apiFormat]?.toString() ?? 'anthropic';

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
          AppDropdownField<String>(
            items: _apiFormats,
            initialItem: _effectiveItem(_apiFormat, _apiFormats),
            itemLabel: l10n.appProviderClaudeApiFormatOption,
            onChanged: (value) {
              if (value != null) {
                _patchExtra(ClaudeFormExtraKeys.apiFormat, value);
              }
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
          AppDropdownField<String>(
            items: _apiKeyFields,
            initialItem: _effectiveItem(widget.apiKeyField, _apiKeyFields),
            itemLabel: l10n.appProviderClaudeAuthFieldOption,
            onChanged: (value) {
              if (value != null) widget.onApiKeyFieldChanged(value);
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
                  controller: _haikuModelCtl,
                  decoration: InputDecoration(
                    labelText: l10n.appProviderClaudeHaikuModel,
                  ),
                  onChanged: (value) =>
                      _patchExtra(ClaudeFormExtraKeys.haikuModel, value),
                ),
                TextField(
                  controller: _sonnetModelCtl,
                  decoration: InputDecoration(
                    labelText: l10n.appProviderClaudeSonnetModel,
                  ),
                  onChanged: (value) =>
                      _patchExtra(ClaudeFormExtraKeys.sonnetModel, value),
                ),
                TextField(
                  controller: _opusModelCtl,
                  decoration: InputDecoration(
                    labelText: l10n.appProviderClaudeOpusModel,
                  ),
                  onChanged: (value) =>
                      _patchExtra(ClaudeFormExtraKeys.opusModel, value),
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

T _effectiveItem<T>(T value, List<T> items) {
  return items.contains(value) ? value : items.first;
}
