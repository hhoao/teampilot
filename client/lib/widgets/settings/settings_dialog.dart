import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/app_dialog_theme.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/deferred_mount_shell.dart';
import 'settings_dialog_pane_host.dart';
import 'workspace_hub_shell.dart';

/// One section in the [showSettingsDialog] left nav.
///
/// Callers supply metadata plus a lazy [bodyBuilder] so panes are not built
/// until their tab is first selected.
class SettingsDialogEntry {
  const SettingsDialogEntry({
    required this.icon,
    required this.navLabel,
    required this.title,
    required this.subtitle,
    required this.bodyBuilder,
  });

  final IconData icon;
  final String navLabel;
  final String title;
  final String subtitle;
  final WidgetBuilder bodyBuilder;
}

const double _kSettingsDialogWidth = 1160;
const double _kSettingsDialogHeight = 960;
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
  late final ValueNotifier<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = ValueNotifier(0);
  }

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

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
    final cs = Theme.of(context).colorScheme;

    return AppDialog(
      maxWidth: dialogWidth,
      maxHeight: dialogHeight,
      contentPadding: EdgeInsets.zero,
      backgroundColor: cs.workspacePage,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Row(
          children: [
            _SettingsNav(
              title: widget.navTitle,
              entries: widget.entries,
              selectedListenable: _selected,
              onSelect: (index) => _selected.value = index,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: DeferredMountShell(
                  delayFrames: 1,
                  child: ListenableBuilder(
                    listenable: _selected,
                    builder: (context, _) {
                      final index = _selected.value;
                      final active = widget.entries[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SettingsHeader(
                            title: active.title,
                            subtitle: active.subtitle,
                            onClose: () => Navigator.of(context).pop(),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                16,
                                24,
                                24,
                              ),
                              child: RepaintBoundary(
                                child: SettingsDialogPaneHost(
                                  key: const ValueKey('settings-pane-host'),
                                  paneCount: widget.entries.length,
                                  selectedIndex: index,
                                  builder: (context, paneIndex) =>
                                      widget.entries[paneIndex].bodyBuilder(
                                        context,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
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
    required this.selectedListenable,
    required this.onSelect,
  });

  final String title;
  final List<SettingsDialogEntry> entries;
  final ValueListenable<int> selectedListenable;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    return RepaintBoundary(
      child: Container(
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
                child: ListenableBuilder(
                  listenable: selectedListenable,
                  builder: (context, _) {
                    final selectedIndex = selectedListenable.value;
                    return ListView(
                      children: [
                        for (final (index, entry) in entries.indexed)
                          WorkspaceHubNavItem(
                            title: entry.navLabel,
                            icon: entry.icon,
                            selected: index == selectedIndex,
                            onTap: () => onSelect(index),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
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
            icon: Icon(Icons.close, size: context.appIconSizes.md),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
