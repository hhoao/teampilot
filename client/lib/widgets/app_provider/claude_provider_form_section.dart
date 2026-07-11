import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../dropdown/app_dropdown_field.dart';

const _apiKeyFields = ['ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY'];

class ClaudeProviderFormSection extends StatelessWidget {
  const ClaudeProviderFormSection({
    required this.apiKeyField,
    required this.onApiKeyFieldChanged,
    super.key,
  });

  final String apiKeyField;
  final ValueChanged<String> onApiKeyFieldChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          l10n.appProviderAdvancedOptions,
          style: styles.sectionTitle,
        ),
        children: [
          const SizedBox(height: 8),
          _FieldLabel(l10n.appProviderClaudeAuthField),
          const SizedBox(height: 6),
          AppDropdownField<String>(
            items: _apiKeyFields,
            initialItem: _effectiveItem(apiKeyField, _apiKeyFields),
            itemLabel: l10n.appProviderClaudeAuthFieldOption,
            onChanged: (value) {
              if (value != null) onApiKeyFieldChanged(value);
            },
          ),
          const SizedBox(height: 6),
          Text(
            l10n.appProviderClaudeAuthFieldHint,
            style: styles.mutedBodySmall,
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
      child: Text(text, style: AppTextStyles.of(context).formLabel),
    );
  }
}

T _effectiveItem<T>(T value, List<T> items) {
  return items.contains(value) ? value : items.first;
}
