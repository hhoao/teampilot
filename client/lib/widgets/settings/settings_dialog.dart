import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/workspace/workspace_pane_policy.dart';

typedef SettingsLabelBuilder = String Function(AppLocalizations l10n);

/// One section in the [showSettingsDialog] left nav.
///
/// Labels are builders so nav/header strings re-resolve when locale changes
/// while the dialog stays open. Callers supply a lazy [bodyBuilder] so panes
/// are not built until their tab is first selected.
class SettingsDialogEntry {
  const SettingsDialogEntry({
    required this.icon,
    required this.navLabel,
    required this.title,
    required this.subtitle,
    required this.bodyBuilder,
  });

  final IconData icon;
  final SettingsLabelBuilder navLabel;
  final SettingsLabelBuilder title;
  final SettingsLabelBuilder subtitle;
  final WidgetBuilder bodyBuilder;
}

Future<void> showSettingsDialog(
  BuildContext context, {
  required SettingsLabelBuilder navTitle,
  required List<SettingsDialogEntry> entries,
  int initialIndex = 0,
}) {
  assert(entries.isNotEmpty, 'showSettingsDialog needs at least one entry');
  return showTpDialog<void>(
    context: context,
    presentation: TpDialogPresentation.page,
    mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
    barrierDismissible: false,
    builder: (ctx) => TpDialogNavShell(
      mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
      onClose: () => Navigator.of(ctx).pop(),
      navTitle: (c) => navTitle(c.l10n),
      initialIndex: initialIndex,
      entries: entries
          .map(
            (e) => TpDialogNavEntry(
              icon: e.icon,
              navLabel: (c) => e.navLabel(c.l10n),
              title: (c) => e.title(c.l10n),
              subtitle: (c) => e.subtitle(c.l10n),
              bodyBuilder: e.bodyBuilder,
            ),
          )
          .toList(),
    ),
  );
}
