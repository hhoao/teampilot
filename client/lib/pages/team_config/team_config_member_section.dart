import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../models/team_member_prompt_presets.dart';
import '../../services/app/flashskyai_agent_catalog_service.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/storage/storage_resolver.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team_member_naming.dart';
import '../../widgets/cli/member_agent_preset_field.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../../widgets/team/team_lead_badge.dart';
import 'team_config_helpers.dart';
import 'team_config_member_dialogs.dart';
import 'team_member_launch_config_section.dart';

class TeamMemberDetailSection extends StatelessWidget {
  const TeamMemberDetailSection({
    super.key,
    required this.team,
    required this.cubit,
    required this.selectedMemberId,
  });

  final TeamProfile team;
  final LaunchProfileCubit cubit;
  final String? selectedMemberId;

  TeamMemberConfig? _memberOrNull() {
    final id = selectedMemberId;
    if (id == null || team.members.isEmpty) return null;
    for (final m in team.members) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final member = _memberOrNull();
    if (member == null) {
      return Center(
        child: Text(
          l10n.openMember,
          textAlign: TextAlign.center,
          style: AppTextStyles.of(
            context,
          ).body.copyWith(color: textBase.withValues(alpha: 0.55)),
        ),
      );
    }

    return SingleChildScrollView(
      child: TeamMemberConfigForm(
        key: ValueKey(member.id),
        team: team,
        member: member,
        cubit: cubit,
      ),
    );
  }
}

class TeamMemberConfigForm extends StatefulWidget {
  const TeamMemberConfigForm({
    super.key,
    required this.team,
    required this.member,
    required this.cubit,
  });

  final TeamProfile team;
  final TeamMemberConfig member;
  final LaunchProfileCubit cubit;

  @override
  State<TeamMemberConfigForm> createState() => TeamMemberConfigFormState();
}

class TeamMemberConfigFormState extends State<TeamMemberConfigForm> {
  late TextEditingController _nameCtl;
  late TextEditingController _agentCtl;
  late TextEditingController _argsCtl;
  late TextEditingController _promptCtl;
  late TextEditingController _playbookCtl;
  List<String> _userAgentIds = const [];

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.member);
    _loadUserAgents();
  }

  Future<void> _loadUserAgents() async {
    final storageRoots = context.read<StorageRoots>();
    final ids = await FlashskyaiAgentCatalogService(
      storageRoots: storageRoots,
    ).listUserAgentIds();
    if (!mounted) return;
    setState(() => _userAgentIds = ids);
  }

  void _syncControllers(TeamMemberConfig m) {
    _nameCtl = TextEditingController(text: m.name);
    _agentCtl = TextEditingController(text: m.agent);
    _argsCtl = TextEditingController(text: m.extraArgs);
    _promptCtl = TextEditingController(text: m.prompt);
    _playbookCtl = TextEditingController(text: m.playbook);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _agentCtl.dispose();
    _argsCtl.dispose();
    _promptCtl.dispose();
    _playbookCtl.dispose();
    super.dispose();
  }

  void _update(TeamMemberConfig next) {
    widget.cubit.updateMember(widget.member.id, next);
  }

  /// A preset is a role bundle: it fills both layers at once — responsibilities
  /// ([prompt]) and the working method ([playbook]). team_lead has no playbook
  /// (its method is injected by the system addendum), so that layer is cleared.
  void _applyPromptPreset(String presetId) {
    final l10n = context.l10n;
    final prompt = teamMemberPromptPresetText(l10n, presetId);
    final playbook = teamMemberPlaybookPresetText(l10n, presetId);
    if (prompt.isEmpty && playbook.isEmpty) return;
    _promptCtl.text = prompt;
    _promptCtl.selection = TextSelection.collapsed(offset: prompt.length);
    _playbookCtl.text = playbook;
    _playbookCtl.selection = TextSelection.collapsed(offset: playbook.length);
    _update(widget.member.copyWith(prompt: prompt, playbook: playbook));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = widget.member;

    final showMemberAgentPreset = memberShowsAgentPresetUi(
      context,
      team: widget.team,
      member: m,
    );
    final agentPresetCli = memberAgentPresetCli(
      team: widget.team,
      member: m,
    );
    final memberAgentStyle = showMemberAgentPreset && agentPresetCli != null
        ? CliToolRegistryScope.of(context).memberAgentPresetStyle(
            agentPresetCli,
          )
        : null;

    final canDelete =
        widget.team.members.length > 1 && !TeamMemberNaming.isTeamLead(m);
    final errorColor = Theme.of(context).colorScheme.error;

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsLabeledStackedRow(
            title: l10n.memberName,
            subtitle: l10n.memberNameSubtitle,
            titleTrailing: TeamMemberNaming.isTeamLead(m) || canDelete
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (TeamMemberNaming.isTeamLead(m)) const TeamLeadBadge(),
                      if (canDelete)
                        IconButton(
                          tooltip: l10n.delete,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: throttledAsync(
                            'team_delete_member_${m.id}',
                            () => confirmDeleteTeamMember(
                              context,
                              widget.cubit,
                              m,
                              l10n,
                            ),
                          ),
                          icon: Icon(
                            Icons.delete_outline,
                            size: context.appIconSizes.md,
                            color: errorColor,
                          ),
                        ),
                    ],
                  )
                : null,
            body: TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(),
              onChanged: (v) => _update(m.copyWith(name: v)),
            ),
            showDividerBelow: true,
          ),
          MemberLaunchConfigRow(
            team: widget.team,
            member: m,
            cubit: widget.cubit,
            showDividerBelow: true,
          ),
          SettingsLabeledRow(
            title: l10n.memberDangerouslySkipPermissions,
            subtitle: l10n.memberDangerouslySkipPermissionsHint,
            trailing: Switch(
              value: m.dangerouslySkipPermissions,
              onChanged: (v) =>
                  _update(m.copyWith(dangerouslySkipPermissions: v)),
            ),
            showDividerBelow: true,
          ),
          SettingsLabeledStackedRow(
            title: l10n.prompt,
            subtitle: l10n.memberPromptSubtitle,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final preset in TeamMemberPromptPreset.all)
                      ActionChip(
                        label: Text(
                          teamMemberPromptPresetLabel(l10n, preset.id),
                          style: AppTextStyles.of(context).bodySmall,
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onPressed: () => _applyPromptPreset(preset.id),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _promptCtl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(),
                  onChanged: (v) => _update(m.copyWith(prompt: v)),
                ),
              ],
            ),
            showDividerBelow: true,
          ),
          SettingsLabeledStackedRow(
            title: l10n.memberPlaybook,
            subtitle: l10n.memberPlaybookSubtitle,
            body: TextField(
              controller: _playbookCtl,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(),
              onChanged: (v) => _update(m.copyWith(playbook: v)),
            ),
            showDividerBelow: true,
          ),
          SettingsAdvancedExpansion(
            title: l10n.workspaceAdvancedSettings,
            subtitle: l10n.workspaceAdvancedSettingsSubtitle,
            children: [
              if (showMemberAgentPreset &&
                  memberAgentStyle != null &&
                  agentPresetCli != null)
                SettingsLabeledStackedRow(
                  title: l10n.agent,
                  subtitle: memberAgentPresetSubtitle(l10n, memberAgentStyle),
                  body: MemberAgentPresetField(
                    cli: agentPresetCli,
                    agent: m.agent,
                    userAgentIds: _userAgentIds,
                    customAgentController: _agentCtl,
                    fieldKeyPrefix: 'member-${widget.member.id}',
                    onAgentChanged: (value) =>
                        _update(m.copyWith(agent: value)),
                  ),
                  showDividerBelow: true,
                ),
              if (!TeamMemberNaming.isTeamLead(m))
                SettingsLabeledRow(
                  title: l10n.memberReplicas,
                  subtitle: l10n.memberReplicasSubtitle,
                  trailing: _ReplicasStepper(
                    value: m.replicas,
                    onChanged: (v) => _update(m.copyWith(replicas: v)),
                  ),
                  showDividerBelow: true,
                ),
              SettingsLabeledStackedRow(
                title: l10n.memberExtraArgs,
                subtitle: l10n.memberExtraArgsSubtitle,
                body: TextField(
                  controller: _argsCtl,
                  decoration: const InputDecoration(),
                  onChanged: (v) => _update(m.copyWith(extraArgs: v)),
                ),
                showDividerBelow: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReplicasStepper extends StatelessWidget {
  const _ReplicasStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '-',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 28,
          child: Text('$value', textAlign: TextAlign.center),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: '+',
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
