import 'package:flutter/material.dart';

import '../../../../l10n/l10n_extensions.dart';
import 'package:shared_ui/shared_ui.dart';

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
    final styles = TpTextStyles.of(context);
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          l10n.appProviderAdvancedOptions,
          style: styles.mdSemiboldTightSnug,
        ),
        children: [
          const SizedBox(height: 8),
          _FieldLabel(l10n.appProviderClaudeAuthField),
          const SizedBox(height: 6),
          TpSelect<String>(
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
            style: styles.mutedSm,
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
      child: Text(text, style: TpTextStyles.of(context).mdSnug),
    );
  }
}

T _effectiveItem<T>(T value, List<T> items) {
  return items.contains(value) ? value : items.first;
}
