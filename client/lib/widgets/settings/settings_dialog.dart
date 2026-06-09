import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_dialog_theme.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import 'workspace_hub_shell.dart';

/// One section in the [showSettingsDialog] left nav.
///
/// This shell is content-agnostic: callers in the `pages/` layer supply the
/// nav label and the pane [body], so the widget never depends on any route
/// page or cubit.
class SettingsDialogEntry {
  const SettingsDialogEntry({
    required this.icon,
    required this.navLabel,
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final IconData icon;
  final String navLabel;

  /// Header title and subtitle shown above [body] when this section is active.
  final String title;
  final String subtitle;

  /// The pane rendered in the dialog when this section is selected.
  final Widget body;
}

/// Opens a settings modal with a left nav column and a headed content pane.
///
/// [entries] must be non-empty; the first section is selected initially.
/// Fixed dialog size — roughly half the width and two-thirds the height of a
/// maximized window on a 1080p display. Clamped to the viewport on smaller
/// windows so the box never overflows.
const double _kSettingsDialogWidth = 1160;
const double _kSettingsDialogHeight = 960;

/// Total horizontal/vertical space reserved around the dialog (matches
/// [kAppDialogInsetPadding]).
const double _kSettingsDialogInset = kAppDialogInsetExtent;

Future<void> showSettingsDialog(
  BuildContext context, {
  required String navTitle,
  required List<SettingsDialogEntry> entries,
}) {
  assert(entries.isNotEmpty, 'showSettingsDialog needs at least one entry');
  return showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(navTitle: navTitle, entries: entries),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.navTitle, required this.entries});

  final String navTitle;
  final List<SettingsDialogEntry> entries;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogWidth = _kSettingsDialogWidth.clamp(
      0.0,
      media.size.width - _kSettingsDialogInset,
    );
    final dialogHeight = _kSettingsDialogHeight.clamp(
      0.0,
      media.size.height - _kSettingsDialogInset,
    );

    final active = widget.entries[_selected];

    return Dialog(
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Row(
          children: [
            _SettingsNav(
              title: widget.navTitle,
              entries: widget.entries,
              selectedIndex: _selected,
              onSelect: (index) => setState(() => _selected = index),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsHeader(
                      title: active.title,
                      subtitle: active.subtitle,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        child: active.body
                            .animate(key: ValueKey(_selected))
                            .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                            .slideX(
                              begin: 0.025,
                              end: 0,
                              duration: 220.ms,
                              curve: Curves.easeOutCubic,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsNav extends StatelessWidget {
  const _SettingsNav({
    required this.title,
    required this.entries,
    required this.selectedIndex,
    required this.onSelect,
  });

  final String title;
  final List<SettingsDialogEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: cs.workspaceSubtleSurface,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
              child: Text(
                title,
                style: styles.subtitle.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final (index, entry) in entries.indexed)
                    WorkspaceHubNavItem(
                      title: entry.navLabel,
                      icon: entry.icon,
                      selected: index == selectedIndex,
                      onTap: () => onSelect(index),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.subtitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: Icon(Icons.close, size: AppIconSizes.md),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
