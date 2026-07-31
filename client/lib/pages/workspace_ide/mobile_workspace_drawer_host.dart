import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../pages/config/config_workspace.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/notification/notification_bell_button.dart';
import 'mobile_slide_panel_host.dart';

/// Single left-side mobile workspace drawer overlay for narrow IDE layouts.
///
/// The shell owns the shared footer (manage + notifications + settings) and the
/// chat/tools mode switch; [chatBody] / [toolsBody] are supplied by the parent.
class MobileWorkspaceDrawerHost extends StatelessWidget {
  const MobileWorkspaceDrawerHost({
    required this.child,
    required this.width,
    required this.open,
    required this.mode,
    required this.chatBody,
    required this.toolsBody,
    required this.onDismiss,
    required this.onModeChanged,
    required this.onOpenWorkspaceManagement,
    super.key,
  });

  /// Center workbench rendered full-bleed underneath the overlay.
  final Widget child;

  final double width;
  final bool open;
  final MobileDrawerMode mode;
  final Widget chatBody;
  final Widget toolsBody;
  final VoidCallback onDismiss;
  final ValueChanged<MobileDrawerMode> onModeChanged;
  final VoidCallback onOpenWorkspaceManagement;

  @override
  Widget build(BuildContext context) {
    return MobileSlidePanelHost(
      open: open,
      width: width,
      onDismiss: onDismiss,
      scrimKey: AppKeys.mobileWorkspaceDrawerScrim,
      panel: _DrawerShell(
        mode: mode,
        chatBody: chatBody,
        toolsBody: toolsBody,
        onModeChanged: onModeChanged,
        onOpenWorkspaceManagement: onOpenWorkspaceManagement,
      ),
      child: child,
    );
  }
}

class _DrawerShell extends StatelessWidget {
  const _DrawerShell({
    required this.mode,
    required this.chatBody,
    required this.toolsBody,
    required this.onModeChanged,
    required this.onOpenWorkspaceManagement,
  });

  final MobileDrawerMode mode;
  final Widget chatBody;
  final Widget toolsBody;
  final ValueChanged<MobileDrawerMode> onModeChanged;
  final VoidCallback onOpenWorkspaceManagement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SegmentedButton<MobileDrawerMode>(
            key: AppKeys.mobileWorkspaceDrawerModeSwitch,
            segments: [
              ButtonSegment(
                value: MobileDrawerMode.chat,
                label: Text(l10n.appRailChat),
              ),
              ButtonSegment(
                value: MobileDrawerMode.tools,
                label: Text(l10n.openRightTools),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) {
              final next = selection.firstOrNull;
              if (next == null || next == mode) return;
              onModeChanged(next);
            },
          ),
        ),
        Expanded(
          child: mode == MobileDrawerMode.chat ? chatBody : toolsBody,
        ),
        Divider(
          height: 1,
          color: cs.outlineVariant.withValues(alpha: 0.5),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: _ManageTile(
                  label: l10n.homeWorkspaceWorkspaceManagement,
                  onTap: onOpenWorkspaceManagement,
                ),
              ),
              const NotificationBellButton(),
              TpIconButton(
                key: AppKeys.sidebarSettingsButton,
                iconWidget: SvgPicture.asset(
                  'assets/icons/settings_gear.svg',
                  width: context.tpIconSizes.md,
                  height: context.tpIconSizes.md,
                  theme: SvgTheme(
                    currentColor: cs.onSurfaceVariant,
                  ),
                ),
                tooltip: l10n.settings,
                backgroundColor: Colors.transparent,
                onTap: () => showWorkspaceSettingsDialog(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManageTile extends StatefulWidget {
  const _ManageTile({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_ManageTile> createState() => _ManageTileState();
}

class _ManageTileState extends State<_ManageTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final background = _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    final labelStyle = styles.lg;
    final iconSize = context.tpIconSizeForText(
      labelStyle,
      textBaseAtScale1: AppTypographyScale.bodyLargeBase,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: AppKeys.homeWorkspaceWorkspaceManagementTile,
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.tune_outlined,
                  size: iconSize,
                  color: cs.onSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.label, style: labelStyle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
