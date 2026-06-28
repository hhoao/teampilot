import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/launch_profile_kind.dart';
import '../../models/personal_profile.dart';
import '../../utils/launch_profile_display_name.dart';
import '../../theme/workspace_surface_layers.dart';
import 'home_workspace_content_header.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_personal_tab.dart';
import 'workspace/workspace_config_section.dart';

/// Right-hand content pane for a selected [PersonalProfile] on the home
/// workspace (skills/plugins/MCP/agent — no roster).
class HomePersonalContent extends StatefulWidget {
  const HomePersonalContent({
    required this.personal,
    required this.cubit,
    this.onSelectGlobalView,
    super.key,
  });

  final PersonalProfile personal;
  final LaunchProfileCubit cubit;
  final ValueChanged<HomeGlobalView>? onSelectGlobalView;

  @override
  State<HomePersonalContent> createState() => _HomePersonalContentState();
}

class _HomePersonalContentState extends State<HomePersonalContent> {
  late int _tabIndex = 0;

  List<WorkspaceConfigSection> get _sections => WorkspaceConfigSection.forKind(
    LaunchProfileKind.personal,
  ).where((s) => s != WorkspaceConfigSection.settings).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final sections = _sections;
    if (sections.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final active = sections[_tabIndex.clamp(0, sections.length - 1)];
    final tabs = [for (final section in sections) section.title(l10n)];

    return ColoredBox(
      color: cs.workspaceCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomePersonalHeader(personal: widget.personal),
          const SizedBox(height: 14),
          HomeContentTabBar(
            tabs: tabs,
            selectedIndex: _tabIndex,
            onSelect: (i) => setState(() => _tabIndex = i),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Expanded(
            child:
                HomePersonalTab(
                      key: ValueKey('home-personal-tab-${active.name}'),
                      section: active,
                      personal: widget.personal,
                      cubit: widget.cubit,
                      onSelectGlobalView: widget.onSelectGlobalView,
                    )
                    .animate(key: ValueKey('home-personal-content-$_tabIndex'))
                    .fadeIn(duration: 180.ms, curve: Curves.easeOut)
                    .slideX(
                      begin: 0.025,
                      end: 0,
                      duration: 220.ms,
                      curve: Curves.easeOutCubic,
                    ),
          ),
        ],
      ),
    );
  }
}

class HomePersonalHeader extends StatelessWidget {
  const HomePersonalHeader({required this.personal, super.key});

  final PersonalProfile personal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.person_outline_rounded, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            launchProfileDisplayName(context.l10n, personal),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}
