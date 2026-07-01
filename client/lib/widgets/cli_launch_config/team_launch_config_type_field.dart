import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../dropdown/app_dropdown_decoration.dart';
import '../dropdown/app_dropdown_field.dart';
import '../settings/workspace_settings_widgets.dart';
import 'cli_launch_config_dropdown.dart';
import 'team_launch_config_kind.dart';

/// Configuration type row for team default: preset / custom.
class TeamLaunchConfigTypeField extends StatelessWidget {
  const TeamLaunchConfigTypeField({
    required this.currentKind,
    required this.onChanged,
    this.decoration,
    this.showDividerBelow = false,
    super.key,
  });

  final TeamLaunchConfigKind currentKind;
  final ValueChanged<TeamLaunchConfigKind> onChanged;
  final AppDropdownDecoration? decoration;
  final bool showDividerBelow;

  static const _items = TeamLaunchConfigKind.values;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dropdownDeco =
        decoration ?? AppDropdownDecorations.themed(context);

    return SettingsLabeledRow(
      title: l10n.memberLaunchConfigTypeLabel,
      trailing: cliLaunchConfigDropdown(
        AppDropdownField<TeamLaunchConfigKind>(
          items: _items,
          initialItem: currentKind,
          hintText: l10n.memberLaunchConfigTypeLabel,
          decoration: dropdownDeco,
          itemLabel: (kind) => _kindLabel(l10n, kind),
          onChanged: (value) {
            if (value == null) return;
            onChanged(value);
          },
        ),
      ),
      showDividerBelow: showDividerBelow,
    );
  }

  static String _kindLabel(
    AppLocalizations l10n,
    TeamLaunchConfigKind kind,
  ) {
    return switch (kind) {
      TeamLaunchConfigKind.preset => l10n.memberLaunchConfigTypePreset,
      TeamLaunchConfigKind.custom => l10n.memberPresetCustom,
    };
  }
}
