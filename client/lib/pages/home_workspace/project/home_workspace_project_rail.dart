import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../widgets/team_pilot_brand_logo.dart';
import 'home_workspace_workspace_section.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../cubits/layout_cubit.dart';

/// Narrow vertical icon rail on the left of the workspace page (mirrors Apifox's
/// 接口管理 / 自动化测试 / … rail).
class WorkspaceRail extends StatelessWidget {
  const WorkspaceRail({
    required this.section,
    required this.isPersonalWorkspace,
    required this.onSectionChanged,
    required this.onLogoTap,
    super.key,
  });

  final WorkspaceSection section;
  final bool isPersonalWorkspace;
  final ValueChanged<WorkspaceSection> onSectionChanged;
  final VoidCallback onLogoTap;

  static const double width = 58;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = isPersonalWorkspace
        ? _personalItems(l10n)
        : _teamItems(l10n, context);

    return SizedBox(
      width: width,
      child: Column(
        children: [
          const SizedBox(height: 10),
          for (final item in items) item,
          const Spacer(),
          BlocBuilder<LayoutCubit, LayoutState>(
            buildWhen: (previous, next) =>
                previous.preferences.workspaceTerminalVisible !=
                next.preferences.workspaceTerminalVisible,
            builder: (context, state) {
              final visible = state.preferences.workspaceTerminalVisible;
              return _RailItem(
                icon: visible ? Icons.terminal : Icons.terminal_outlined,
                label: visible
                    ? l10n.workspaceTerminalHide
                    : l10n.workspaceTerminalShow,
                active: visible,
                onTap: () => context
                    .read<LayoutCubit>()
                    .setWorkspaceTerminalVisible(!visible),
              );
            },
          ),
          _RailItem(
            label: l10n.appTitle,
            active: false,
            onTap: onLogoTap,
            child: TeamPilotBrandLogo(),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  List<Widget> _personalItems(AppLocalizations l10n) {
    return [
      _sectionItem(
        icon: Icons.forum_outlined,
        label: l10n.homeWorkspaceConversations,
        value: WorkspaceSection.conversations,
      ),
      _sectionItem(
        icon: Icons.tune_outlined,
        label: l10n.homeWorkspaceWorkspaceManagement,
        value: WorkspaceSection.manage,
      ),
    ];
  }

  List<Widget> _teamItems(AppLocalizations l10n, BuildContext context) {
    return [
      _sectionItem(
        icon: Icons.forum_outlined,
        label: l10n.homeWorkspaceConversations,
        value: WorkspaceSection.conversations,
      ),
      _sectionItem(
        icon: Icons.tune_outlined,
        label: l10n.homeWorkspaceWorkspaceManagement,
        value: WorkspaceSection.manage,
      ),
    ];
  }

  Widget _sectionItem({
    required IconData icon,
    required String label,
    required WorkspaceSection value,
  }) {
    return _RailItem(
      icon: icon,
      label: label,
      active: section == value,
      onTap: () => onSectionChanged(value),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.child,
  }) : assert(icon != null || child != null);

  final IconData? icon;
  final Widget? child;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.active;
    final Color fg = active ? cs.primary : cs.onSurfaceVariant;

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                if (active)
                  Container(
                    width: 3,
                    height: 36,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                else
                  const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active || !_hovered
                          ? Colors.transparent
                          : cs.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child:
                        widget.child ??
                        Icon(widget.icon, size: context.appIconSizes.md, color: fg),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
