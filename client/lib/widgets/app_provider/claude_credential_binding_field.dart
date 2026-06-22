import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/provider/credential_binding.dart';
import '../dropdown/app_dropdown_field.dart';

/// Official Claude OAuth: follow global `~/.claude` or use an isolated copy.
class ClaudeCredentialBindingField extends StatelessWidget {
  const ClaudeCredentialBindingField({
    required this.value,
    this.onChanged,
    super.key,
  });

  final CredentialBindingKind value;

  /// When null, the field is read-only (detail view).
  final ValueChanged<CredentialBindingKind>? onChanged;

  static const _items = [
    CredentialBindingKind.linked,
    CredentialBindingKind.isolated,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final readOnly = onChanged == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.appProviderClaudeCredentialBinding,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        AppDropdownField<CredentialBindingKind>(
          items: _items,
          initialItem: value,
          enabled: !readOnly,
          itemLabel: (kind) => switch (kind) {
            CredentialBindingKind.linked =>
              l10n.appProviderClaudeCredentialBindingLinked,
            CredentialBindingKind.isolated =>
              l10n.appProviderClaudeCredentialBindingIsolated,
          },
          onChanged: (kind) {
            if (readOnly || kind == null) return;
            onChanged!(kind);
          },
        ),
        const SizedBox(height: 6),
        Text(
          value == CredentialBindingKind.linked
              ? l10n.appProviderClaudeCredentialBindingLinkedHint
              : l10n.appProviderClaudeCredentialBindingIsolatedHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
