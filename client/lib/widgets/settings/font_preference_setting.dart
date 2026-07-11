import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/font_catalog.dart';
import '../../theme/installed_font_enumerator.dart';
import 'workspace_settings_widgets.dart';

/// Searchable mixed font picker: catalog presets, then installed families.
class FontPreferenceSetting extends StatefulWidget {
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
  State<FontPreferenceSetting> createState() => _FontPreferenceSettingState();
}

class _FontPreferenceSettingState extends State<FontPreferenceSetting> {
  List<String> _installed = const [];
  var _loadingInstalled = true;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    final families = await InstalledFontEnumerator.listFamilies();
    if (!mounted) return;
    setState(() {
      _installed = widget.role == FontRole.mono
          ? sortFamiliesForMonoPicker(families)
          : (List<String>.from(families)..sort());
      _loadingInstalled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final catalog = widget.role == FontRole.ui
        ? FontCatalog.uiOptions
        : FontCatalog.monoOptions;

    final entries = <(String, String)>[
      for (final entry in catalog)
        (entry.id, _labelForFontId(l10n, entry.id)),
    ];

    // Keep a selected installed face visible even before scan finishes.
    final selectedKey = installedFontKey(widget.value);
    if (selectedKey != null &&
        !_installed.contains(selectedKey) &&
        !entries.any((e) => e.$1 == widget.value)) {
      entries.add((widget.value, selectedKey));
    }

    if (!_loadingInstalled && _installed.isNotEmpty) {
      for (final family in _installed) {
        final id = installedFontId(family);
        if (entries.any((e) => e.$1 == id)) continue;
        entries.add((id, family));
      }
    }

    // Ensure current value is in the list (dropdown requires it).
    if (!entries.any((e) => e.$1 == widget.value)) {
      entries.insert(0, (widget.value, _labelForFontId(l10n, widget.value)));
    }

    return SettingsCompactDropdown<String>(
      value: widget.value,
      entries: entries,
      searchHintText: l10n.fontSearchHint,
      onChanged: (v) {
        if (v != null) widget.onChanged(v);
      },
    );
  }
}

String _labelForFontId(AppLocalizations l10n, String id) {
  final installed = installedFontKey(id);
  if (installed != null) return installed;
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
