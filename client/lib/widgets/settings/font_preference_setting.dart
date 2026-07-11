import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_toast_theme.dart';
import '../../theme/font_catalog.dart';
import '../../theme/installed_font_enumerator.dart';
import '../app_toast/app_toast.dart';
import 'workspace_settings_widgets.dart';

/// Searchable mixed font picker: catalog presets, then installed families.
///
/// Saves immediately; theme fonts apply on the next app restart (full
/// [ThemeData] font swaps are multi-second). No live face preview — hover
/// / open-time shaping was janking the settings dialog.
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
    // Defer fc-list so opening the settings dialog is not competing with
    // enumerating hundreds of families on the first frames.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadInstalled();
    });
  }

  @override
  void didUpdateWidget(covariant FontPreferenceSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role) {
      _loadInstalled();
    }
  }

  Future<void> _loadInstalled() async {
    setState(() => _loadingInstalled = true);
    final families = await InstalledFontEnumerator.listFamilies();
    if (!mounted) return;
    setState(() {
      _installed = widget.role == FontRole.mono
          ? sortFamiliesForMonoPicker(families)
          : (List<String>.from(families)..sort());
      _loadingInstalled = false;
    });
  }

  void _onSelect(String id) {
    if (id == widget.value) return;
    widget.onChanged(id);
    AppToast.show(
      context,
      message: context.l10n.fontChangeAppliesOnRestart,
      variant: AppToastVariant.info,
    );
  }

  List<(String, String)> _buildEntries(AppLocalizations l10n) {
    final catalog = widget.role == FontRole.ui
        ? FontCatalog.uiOptions
        : FontCatalog.monoOptions;

    final entries = <(String, String)>[
      for (final entry in catalog)
        (entry.id, _labelForFontId(l10n, entry.id)),
    ];

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

    if (!entries.any((e) => e.$1 == widget.value)) {
      entries.insert(0, (widget.value, _labelForFontId(l10n, widget.value)));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsCompactDropdown<String>(
      value: widget.value,
      entries: _buildEntries(l10n),
      searchHintText: l10n.fontSearchHint,
      onChanged: (v) {
        if (v != null) _onSelect(v);
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
