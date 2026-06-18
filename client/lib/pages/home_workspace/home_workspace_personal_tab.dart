import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/identity_cubit.dart';
import '../../cubits/extension_cubit.dart';
import '../../models/personal_identity.dart';
import '../team_config/team_config_extensions_section.dart';
import 'home_workspace_global_section.dart';
import 'project/config/workspace_agent_section.dart';
import 'project/config/workspace_mcp_section.dart';
import 'project/config/workspace_plugins_section.dart';
import 'project/config/workspace_skills_section.dart';
import 'project/workspace_config_section.dart';

/// Embeds personal-identity config sections inside the workspace-home tab.
class HomePersonalTab extends StatelessWidget {
  const HomePersonalTab({
    required this.section,
    required this.personal,
    required this.cubit,
    this.onSelectGlobalView,
    super.key,
  });

  final WorkspaceConfigSection section;
  final PersonalIdentity personal;
  final IdentityCubit cubit;
  final ValueChanged<HomeGlobalView>? onSelectGlobalView;

  @override
  Widget build(BuildContext context) {
    final body = switch (section) {
      WorkspaceConfigSection.agent => WorkspaceAgentSection(
          workspaceId: '',
          identityId: personal.id,
        ),
      WorkspaceConfigSection.skills => WorkspaceSkillsSection(
          workspaceId: '',
          identityId: personal.id,
        ),
      WorkspaceConfigSection.plugins => WorkspacePluginsSection(
          workspaceId: '',
          identityId: personal.id,
        ),
      WorkspaceConfigSection.mcp => WorkspaceMcpSection(
          workspaceId: '',
          identityId: personal.id,
        ),
      WorkspaceConfigSection.extensions => _IdentityExtensionsSection(
          identityId: personal.id,
        ),
      _ => const SizedBox.shrink(),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: body,
    );
  }
}

class _IdentityExtensionsSection extends StatefulWidget {
  const _IdentityExtensionsSection({required this.identityId});

  final String identityId;

  @override
  State<_IdentityExtensionsSection> createState() =>
      _IdentityExtensionsSectionState();
}

class _IdentityExtensionsSectionState extends State<_IdentityExtensionsSection> {
  Map<String, bool> _overrides = const {};

  @override
  void initState() {
    super.initState();
    _loadOverrides();
  }

  @override
  void didUpdateWidget(covariant _IdentityExtensionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identityId != widget.identityId) _loadOverrides();
  }

  Future<void> _loadOverrides() async {
    final map = await context
        .read<ExtensionCubit>()
        .teamOverrides(widget.identityId);
    if (!mounted) return;
    setState(() => _overrides = map);
  }

  ExtensionOverrideChoice _choiceFor(String id) {
    if (!_overrides.containsKey(id)) return ExtensionOverrideChoice.followGlobal;
    return _overrides[id]!
        ? ExtensionOverrideChoice.forceOn
        : ExtensionOverrideChoice.forceOff;
  }

  bool _effective(ExtensionRow row) {
    final override = _overrides[row.id];
    return override ?? row.globalEnabled;
  }

  Future<void> _setChoice(String id, ExtensionOverrideChoice choice) async {
    final value = switch (choice) {
      ExtensionOverrideChoice.followGlobal => null,
      ExtensionOverrideChoice.forceOn => true,
      ExtensionOverrideChoice.forceOff => false,
    };
    await context
        .read<ExtensionCubit>()
        .setTeamOverride(widget.identityId, id, value);
    await _loadOverrides();
  }

  @override
  Widget build(BuildContext context) {
    final rows = context.watch<ExtensionCubit>().state.rows;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            TeamExtensionRow(
              row: row,
              choice: _choiceFor(row.id),
              effective: _effective(row),
              onChoice: (c) => _setChoice(row.id, c),
            ),
        ],
      ),
    );
  }
}
