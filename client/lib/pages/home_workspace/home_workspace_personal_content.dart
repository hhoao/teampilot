import 'package:flutter/material.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/personal_profile.dart';
import '../../utils/launch_profile_display_name.dart';
import 'home_identity_config_section.dart';
import 'home_workspace_global_section.dart';
import 'home_workspace_identity_content_shell.dart';
import 'home_workspace_personal_tab.dart';

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

  static const _sections = HomeIdentityConfigSection.values;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = _sections[_tabIndex.clamp(0, _sections.length - 1)];
    final tabs = [for (final section in _sections) section.title(l10n)];
    final personalId = widget.personal.id;

    return HomeIdentityContentShell(
      header: HomePersonalHeader(personal: widget.personal),
      tabs: tabs,
      selectedTabIndex: _tabIndex,
      onTabSelected: (i) => setState(() => _tabIndex = i),
      bodyAnimationKey: ValueKey(
        'home-personal-content-$personalId-$_tabIndex',
      ),
      tabBody: HomePersonalTab(
        key: ValueKey('home-personal-tab-${active.name}'),
        section: active,
        personal: widget.personal,
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
