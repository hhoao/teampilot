import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/team_hub_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_team.dart';
import '../../services/team/team_clone_service.dart';
import '../../widgets/settings/workspace_section_host.dart';
import 'team_hub_detail_overlay.dart';
import 'team_hub_discovery_section.dart';
import 'team_hub_favorites_section.dart';
import 'team_hub_section.dart';

class TeamHubPage extends StatefulWidget {
  const TeamHubPage({
    super.key,
    required this.section,
    this.onSelectSection,
  });

  final TeamHubSection section;
  final void Function(TeamHubSection target)? onSelectSection;

  @override
  State<TeamHubPage> createState() => _TeamHubPageState();
}

class _TeamHubPageState extends State<TeamHubPage> {
  DiscoverableTeam? _detail;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<TeamHubCubit>();
    if (cubit.state.status == TeamHubLoadStatus.idle) {
      cubit.load();
    }
  }

  void _select(TeamHubSection target) {
    widget.onSelectSection?.call(target);
  }

  Future<void> _clone(TeamHubCubit cubit, DiscoverableTeam team) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await cubit.clone(team);
      if (!mounted) return;
      setState(() => _detail = null);
      final failed = result.failedDeps.length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? l10n.teamHubCloneSuccess(team.name)
                : l10n.teamHubClonePartial(team.name, failed),
          ),
        ),
      );
    } on CloneException {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.teamHubCloneFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TeamHubCubit, TeamHubState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.teamHubLoadError)),
        );
        context.read<TeamHubCubit>().clearError();
      },
      builder: (context, state) {
        final cubit = context.read<TeamHubCubit>();
        if (_detail != null) {
          return TeamHubDetailOverlay(
            team: _detail!,
            cloning: state.cloningKeys.contains(_detail!.key),
            installedDepIds: state.installedDepIds,
            onBack: () => setState(() => _detail = null),
            onClone: () => _clone(cubit, _detail!),
          );
        }
        final body = switch (widget.section) {
          TeamHubSection.discovery => TeamHubDiscoverySection(
              cubit: cubit,
              onOpen: (t) => setState(() => _detail = t),
            ),
          TeamHubSection.favorites => TeamHubFavoritesSection(
              cubit: cubit,
              onOpen: (t) => setState(() => _detail = t),
            ),
        };
        return WorkspaceAdaptiveSectionPage(
          pageKey: const ValueKey('team-hub-workspace'),
          title: context.l10n.teamHubTitle,
          subtitle: context.l10n.teamHubSubtitle,
          bodyAnimationKey: ValueKey('team-hub-body-${widget.section.name}'),
          nav: WorkspaceEnumNavPanel<TeamHubSection>(
            sections: TeamHubSection.values,
            current: widget.section,
            basePath: '/team-hub',
            descriptor: (s) => s,
            onSelect: _select,
          ),
          body: body,
        );
      },
    );
  }
}
