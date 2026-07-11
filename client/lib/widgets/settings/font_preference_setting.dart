import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/font_catalog.dart';
import 'workspace_settings_widgets.dart';

/// Compact dropdown for a single font preference role (UI or monospace).
class FontPreferenceSetting extends StatelessWidget {
  const FontPreferenceSetting({
    required this.role,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final FontRole role;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final options = role == FontRole.ui
        ? FontCatalog.uiOptions
        : FontCatalog.monoOptions;
    return SettingsCompactDropdown<String>(
      value: value,
      entries: [
        for (final entry in options)
          (entry.id, _labelForFontId(l10n, entry.id)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

String _labelForFontId(AppLocalizations l10n, String id) {
  switch (id) {
    case FontCatalog.systemId:
      return l10n.fontOptionSystem;
    case 'notoSansSc':
      return l10n.fontOptionNotoSansSc;
    case 'jetbrainsMono':
      return l10n.fontOptionJetbrainsMono;
    case 'ubuntuSansMono':
      return l10n.fontOptionUbuntuSansMono;
    default:
      return id;
  }
}
