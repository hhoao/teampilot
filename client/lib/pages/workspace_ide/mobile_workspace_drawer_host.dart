import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/layout_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../pages/config/config_workspace.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/notification/notification_bell_button.dart';

/// Single left-side mobile workspace drawer overlay for narrow IDE layouts.
///
/// The shell owns the shared footer (manage + notifications + settings) and the
/// chat/tools mode switch; [chatBody] / [toolsBody] are supplied by the parent.
class MobileWorkspaceDrawerHost extends StatefulWidget {
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
  State<MobileWorkspaceDrawerHost> createState() =>
      _MobileWorkspaceDrawerHostState();
}

class _MobileWorkspaceDrawerHostState extends State<MobileWorkspaceDrawerHost>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 200);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.open ? 1 : 0,
    )..addStatusListener(_onAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant MobileWorkspaceDrawerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() {});
    }
  }

  bool get _panelMounted =>
      _controller.status != AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) {
    final panelMounted = _panelMounted;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (panelMounted)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                if (t <= 0) return const SizedBox.shrink();
                return GestureDetector(
                  key: AppKeys.mobileWorkspaceDrawerScrim,
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onDismiss,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45 * t),
                  ),
                );
              },
            ),
          ),
        if (panelMounted)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: widget.width,
            child: _DrawerPanel(
              controller: _controller,
              child: _DrawerShell(
                mode: widget.mode,
                chatBody: widget.chatBody,
                toolsBody: widget.toolsBody,
                onModeChanged: widget.onModeChanged,
                onOpenWorkspaceManagement: widget.onOpenWorkspaceManagement,
              ),
            ),
          ),
      ],
    );
  }
}

class _DrawerPanel extends StatelessWidget {
  const _DrawerPanel({
    required this.controller,
    required this.child,
  });

  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slide = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    return SlideTransition(
      position: slide,
      child: Material(
        color: cs.surface,
        elevation: 12,
        child: child,
      ),
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
                  size: context.tpIconSizes.md,
                  color: cs.onSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.label, style: styles.lg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
