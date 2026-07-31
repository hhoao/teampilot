import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/workspace/workspace_pane_policy.dart';
import 'settings_dialog_pane_host.dart';

typedef SettingsLabelBuilder = String Function(AppLocalizations l10n);

/// One section in the [showSettingsDialog] left nav.
///
/// Labels are builders so nav/header strings re-resolve when locale changes
/// while the dialog stays open. On wide viewports, [bodyBuilder] panes mount
/// lazily on first visit and stay alive via [SettingsDialogPaneHost]. On narrow
/// viewports each detail page builds its body when pushed.
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
    builder: (ctx) => _SettingsDialogHost(
      navTitle: navTitle,
      entries: entries,
      initialIndex: initialIndex,
      onClose: () => Navigator.of(ctx).pop(),
    ),
  );
}

/// Tracks nav selection and wraps wide bodies in [SettingsDialogPaneHost].
class _SettingsDialogHost extends StatefulWidget {
  const _SettingsDialogHost({
    required this.navTitle,
    required this.entries,
    required this.onClose,
    this.initialIndex = 0,
  });

  final SettingsLabelBuilder navTitle;
  final List<SettingsDialogEntry> entries;
  final VoidCallback onClose;
  final int initialIndex;

  @override
  State<_SettingsDialogHost> createState() => _SettingsDialogHostState();
}

class _SettingsDialogHostState extends State<_SettingsDialogHost> {
  late int _selectedIndex;
  final _wideBodyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, widget.entries.length - 1);
  }

  bool _isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >=
      WorkspacePanePolicy.narrowBreakpointWidth;

  Widget _wideBody(BuildContext context) {
    return TpDeferredMountShell(
      key: const ValueKey('settings-deferred-mount'),
      delayFrames: 1,
      child: RepaintBoundary(
        child: SettingsDialogPaneHost(
          key: _wideBodyKey,
          paneCount: widget.entries.length,
          selectedIndex: _selectedIndex,
          builder: (context, paneIndex) =>
              widget.entries[paneIndex].bodyBuilder(context),
        ),
      ),
    );
  }

  List<TpDialogNavEntry> _mapEntries() {
    return [
      for (final entry in widget.entries)
        TpDialogNavEntry(
          icon: entry.icon,
          navLabel: (c) => entry.navLabel(c.l10n),
          title: (c) => entry.title(c.l10n),
          subtitle: (c) => entry.subtitle(c.l10n),
          bodyBuilder: (context) {
            if (_isWide(context)) {
              return _wideBody(context);
            }
            return entry.bodyBuilder(context);
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return TpDialogNavShell(
      mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
      onClose: widget.onClose,
      navTitle: (c) => widget.navTitle(c.l10n),
      initialIndex: widget.initialIndex,
      onSelectedIndexChanged: (index) {
        setState(() => _selectedIndex = index);
      },
      entries: _mapEntries(),
    );
  }
}
