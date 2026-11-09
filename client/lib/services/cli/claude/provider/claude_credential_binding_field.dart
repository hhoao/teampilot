import 'package:flutter/material.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../provider/credential_binding.dart';
import 'package:shared_ui/shared_ui.dart';

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
    final styles = TpTextStyles.of(context);
    final readOnly = onChanged == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.appProvider.claudeCredentialBinding, style: styles.mdSnug),
        const SizedBox(height: 6),
        TpSelect<CredentialBindingKind>(
          items: _items,
          initialItem: value,
          enabled: !readOnly,
          itemLabel: (kind) => switch (kind) {
            CredentialBindingKind.linked =>
              l10n.appProvider.claudeCredentialBindingLinked,
            CredentialBindingKind.isolated =>
              l10n.appProvider.claudeCredentialBindingIsolated,
          },
          onChanged: (kind) {
            if (readOnly || kind == null) return;
            onChanged!(kind);
          },
        ),
        const SizedBox(height: 6),
        Text(
          value == CredentialBindingKind.linked
              ? l10n.appProvider.claudeCredentialBindingLinkedHint
              : l10n.appProvider.claudeCredentialBindingIsolatedHint,
          style: styles.mutedSm,
        ),
      ],
    );
  }
}
