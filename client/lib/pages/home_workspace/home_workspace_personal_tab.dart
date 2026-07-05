import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/extension_cubit.dart';
import '../../models/personal_profile.dart';
import '../team_config/team_config_extensions_section.dart';
import 'home_identity_config_section.dart';
import 'home_personal_agent_section.dart';
import 'home_personal_bundle_sections.dart';

/// Personal identity configuration tabs on the home workspace.
class HomePersonalTab extends StatelessWidget {
  const HomePersonalTab({
    required this.section,
    required this.personal,
    super.key,
  });

  final HomeIdentityConfigSection section;
  final PersonalProfile personal;

  @override
  Widget build(BuildContext context) {
    final profileId = personal.id;
    final body = switch (section) {
      HomeIdentityConfigSection.agent => HomePersonalAgentSection(
        profileId: profileId,
      ),
      HomeIdentityConfigSection.skills => HomePersonalSkillsSection(
        profileId: profileId,
      ),
      HomeIdentityConfigSection.plugins => HomePersonalPluginsSection(
        profileId: profileId,
      ),
      HomeIdentityConfigSection.mcp => HomePersonalMcpSection(
        profileId: profileId,
      ),
      HomeIdentityConfigSection.extensions => _HomePersonalExtensionsSection(
        profileId: profileId,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
      child: body,
    );
  }
}

class _HomePersonalExtensionsSection extends StatefulWidget {
  const _HomePersonalExtensionsSection({required this.profileId});

  final String profileId;

  @override
  State<_HomePersonalExtensionsSection> createState() =>
      _HomePersonalExtensionsSectionState();
}

class _HomePersonalExtensionsSectionState
    extends State<_HomePersonalExtensionsSection> {
  Map<String, bool> _overrides = const {};

  @override
  void initState() {
    super.initState();
    _loadOverrides();
  }

  @override
  void didUpdateWidget(covariant _HomePersonalExtensionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) _loadOverrides();
  }

  Future<void> _loadOverrides() async {
    final map = await context.read<ExtensionCubit>().teamOverrides(
      widget.profileId,
    );
    if (!mounted) return;
    setState(() => _overrides = map);
  }

  ExtensionOverrideChoice _choiceFor(String id) {
    if (!_overrides.containsKey(id)) {
      return ExtensionOverrideChoice.followGlobal;
    }
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
    await context.read<ExtensionCubit>().setTeamOverride(
      widget.profileId,
      id,
      value,
    );
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
