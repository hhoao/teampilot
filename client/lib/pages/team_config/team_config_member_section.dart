import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/team/launch_profile_selectors.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../models/team_member_prompt_presets.dart';
import '../../services/app/flashskyai_agent_catalog_service.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/cli/member_agent_preset_field.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../../widgets/team/team_lead_badge.dart';
import 'team_config_helpers.dart';
import 'team_config_member_dialogs.dart';
import 'team_config_persist_constants.dart';
import 'team_member_launch_config_section.dart';

class TeamMemberDetailSection extends StatelessWidget {
  const TeamMemberDetailSection({
    super.key,
    required this.teamId,
    required this.selectedMemberId,
  });

  final String teamId;
  final String? selectedMemberId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final memberId = selectedMemberId;
    final hasMember = memberId != null &&
        context.select<LaunchProfileCubit, bool>(
          (c) =>
              LaunchProfileSelectors.memberById(
                LaunchProfileSelectors.teamById(c.state, teamId),
                memberId,
              ) !=
              null,
        );
    if (!hasMember) {
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
        teamId: teamId,
        memberId: memberId,
      ),
    );
  }
}

class TeamMemberConfigForm extends StatefulWidget {
  const TeamMemberConfigForm({
    super.key,
    required this.teamId,
    required this.memberId,
  });

  final String teamId;
  final String memberId;

  @override
  State<TeamMemberConfigForm> createState() => TeamMemberConfigFormState();
}

class TeamMemberConfigFormState extends State<TeamMemberConfigForm> {
  late TextEditingController _nameCtl;
  late TextEditingController _agentCtl;
  late TextEditingController _argsCtl;
  late TextEditingController _promptCtl;
  late TextEditingController _playbookCtl;
  late FocusNode _nameFocus;
  late FocusNode _promptFocus;
  late FocusNode _playbookFocus;
  late FocusNode _argsFocus;
  late Debouncer _persistDebouncer;
  List<String> _userAgentIds = const [];

  LaunchProfileCubit get _cubit => context.read<LaunchProfileCubit>();

  TeamMemberConfig? get _member {
    final team = LaunchProfileSelectors.teamById(_cubit.state, widget.teamId);
    return LaunchProfileSelectors.memberById(team, widget.memberId);
  }

  TeamProfile? get _team =>
      LaunchProfileSelectors.teamById(_cubit.state, widget.teamId);

  @override
  void initState() {
    super.initState();
    _initControllersForMember(_member);
    _initFocusNodes();
    _initDebouncer();
    _loadUserAgents();
  }

  void _initControllersForMember(TeamMemberConfig? member) {
    _nameCtl = TextEditingController(text: member?.name ?? '');
    _agentCtl = TextEditingController(text: member?.agent ?? '');
    _argsCtl = TextEditingController(text: member?.extraArgs ?? '');
    _promptCtl = TextEditingController(text: member?.prompt ?? '');
    _playbookCtl = TextEditingController(text: member?.playbook ?? '');
  }

  void _initFocusNodes() {
    _nameFocus = FocusNode()..addListener(_onNameFocusChanged);
    _promptFocus = FocusNode()..addListener(_onPromptFocusChanged);
    _playbookFocus = FocusNode()..addListener(_onPlaybookFocusChanged);
    _argsFocus = FocusNode()..addListener(_onArgsFocusChanged);
  }

  void _initDebouncer() {
    _persistDebouncer = Debouncer(
      tag: 'team_member_config_${widget.teamId}_${widget.memberId}',
      duration: kTeamConfigTextPersistDebounce,
    );
  }

  @override
  void didUpdateWidget(covariant TeamMemberConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.memberId != oldWidget.memberId) {
      _flushPersistForMember(oldWidget.memberId);
      _persistDebouncer.dispose();
      _initDebouncer();
      _syncControllersFromMember(_member);
      return;
    }
    final member = _member;
    if (member == null) return;
    _syncControllerIfIdle(_nameCtl, _nameFocus, member.name);
    _syncControllerIfIdle(_agentCtl, null, member.agent);
    _syncControllerIfIdle(_argsCtl, _argsFocus, member.extraArgs);
    _syncControllerIfIdle(_promptCtl, _promptFocus, member.prompt);
    _syncControllerIfIdle(_playbookCtl, _playbookFocus, member.playbook);
  }

  Future<void> _loadUserAgents() async {
    final ids = await FlashskyaiAgentCatalogService().listUserAgentIds();
    if (!mounted) return;
    setState(() => _userAgentIds = ids);
  }

  void _syncControllersFromMember(TeamMemberConfig? member) {
    if (member == null) return;
    _nameCtl.text = member.name;
    _agentCtl.text = member.agent;
    _argsCtl.text = member.extraArgs;
    _promptCtl.text = member.prompt;
    _playbookCtl.text = member.playbook;
  }

  void _syncControllerIfIdle(
    TextEditingController controller,
    FocusNode? focus,
    String value,
  ) {
    if (focus != null && focus.hasFocus) return;
    if (controller.text == value) return;
    controller.text = value;
  }

  @override
  void dispose() {
    _flushPersistForMember(widget.memberId);
    _persistDebouncer.dispose();
    _nameFocus.dispose();
    _promptFocus.dispose();
    _playbookFocus.dispose();
    _argsFocus.dispose();
    _nameCtl.dispose();
    _agentCtl.dispose();
    _argsCtl.dispose();
    _promptCtl.dispose();
    _playbookCtl.dispose();
    super.dispose();
  }

  TeamMemberConfig _memberFromControllers(TeamMemberConfig base) {
    return base.copyWith(
      name: _nameCtl.text,
      agent: _agentCtl.text,
      extraArgs: _argsCtl.text,
      prompt: _promptCtl.text,
      playbook: _playbookCtl.text,
    );
  }

  TeamMemberConfig? _memberSnapshot(String memberId) {
    final team = LaunchProfileSelectors.teamById(_cubit.state, widget.teamId);
    return LaunchProfileSelectors.memberById(team, memberId);
  }

  void _persistImmediate(TeamMemberConfig next) {
    _persistDebouncer.cancel();
    unawaited(_cubit.updateMember(next.id, next));
  }

  void _schedulePersist() {
    _persistDebouncer(() {
      if (!mounted) return;
      final member = _member;
      if (member == null) return;
      final next = _memberFromControllers(member);
      if (_membersEqualForPersist(member, next)) return;
      unawaited(_cubit.updateMember(member.id, next));
    });
  }

  void _flushPersistForMember(String memberId) {
    _persistDebouncer.cancel();
    if (!mounted) return;
    final member = _memberSnapshot(memberId);
    if (member == null) return;
    final next = _memberFromControllers(member);
    if (_membersEqualForPersist(member, next)) return;
    unawaited(_cubit.updateMember(memberId, next));
  }

  bool _membersEqualForPersist(TeamMemberConfig a, TeamMemberConfig b) {
    return a.name == b.name &&
        a.agent == b.agent &&
        a.extraArgs == b.extraArgs &&
        a.prompt == b.prompt &&
        a.playbook == b.playbook;
  }

  void _onNameFocusChanged() => _onFieldFocusChanged(_nameFocus);
  void _onPromptFocusChanged() => _onFieldFocusChanged(_promptFocus);
  void _onPlaybookFocusChanged() => _onFieldFocusChanged(_playbookFocus);
  void _onArgsFocusChanged() => _onFieldFocusChanged(_argsFocus);

  void _onFieldFocusChanged(FocusNode node) {
    if (!node.hasFocus) _flushPersistForMember(widget.memberId);
  }

  void _applyPromptPreset(String presetId) {
    final member = _member;
    if (member == null) return;
    final l10n = context.l10n;
    final prompt = teamMemberPromptPresetText(l10n, presetId);
    final playbook = teamMemberPlaybookPresetText(l10n, presetId);
    if (prompt.isEmpty && playbook.isEmpty) return;
    _promptCtl.text = prompt;
    _promptCtl.selection = TextSelection.collapsed(offset: prompt.length);
    _playbookCtl.text = playbook;
    _playbookCtl.selection = TextSelection.collapsed(offset: playbook.length);
    _persistImmediate(member.copyWith(prompt: prompt, playbook: playbook));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final teamShell = context.select<LaunchProfileCubit, TeamMemberFormShell?>(
      (c) => LaunchProfileSelectors.memberFormShell(
        LaunchProfileSelectors.teamById(c.state, widget.teamId),
      ),
    );
    final discrete = context.select<LaunchProfileCubit, MemberDiscreteFields?>(
      (c) => LaunchProfileSelectors.memberDiscreteFields(
        c.state,
        widget.teamId,
        widget.memberId,
      ),
    );
    final team = _team;
    final member = _member;
    if (team == null || teamShell == null || discrete == null || member == null) {
      return const SizedBox.shrink();
    }

    final showMemberAgentPreset = memberShowsAgentPresetUi(
      context,
      team: team,
      member: member,
    );
    final agentPresetCli = memberAgentPresetCli(
      team: team,
      member: member,
    );
    final memberAgentStyle = showMemberAgentPreset && agentPresetCli != null
        ? CliToolRegistryScope.of(context).memberAgentPresetStyle(
            agentPresetCli,
          )
        : null;

    final canDelete = teamShell.memberCount > 1 && !discrete.isTeamLead;
    final errorColor = Theme.of(context).colorScheme.error;

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsLabeledStackedRow(
            title: l10n.memberName,
            subtitle: l10n.memberNameSubtitle,
            titleTrailing: discrete.isTeamLead || canDelete
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (discrete.isTeamLead) const TeamLeadBadge(),
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
                            'team_delete_member_${member.id}',
                            () => confirmDeleteTeamMember(
                              context,
                              _cubit,
                              member,
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
              focusNode: _nameFocus,
              decoration: const InputDecoration(),
              onChanged: (_) => _schedulePersist(),
            ),
            showDividerBelow: true,
          ),
          MemberLaunchConfigRow(
            teamId: widget.teamId,
            memberId: widget.memberId,
            showDividerBelow: true,
          ),
          _MemberSkipPermissionsSwitch(
            teamId: widget.teamId,
            memberId: widget.memberId,
            onPersist: _persistImmediate,
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
                  focusNode: _promptFocus,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(),
                  onChanged: (_) => _schedulePersist(),
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
              focusNode: _playbookFocus,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(),
              onChanged: (_) => _schedulePersist(),
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
                    agent: member.agent,
                    userAgentIds: _userAgentIds,
                    customAgentController: _agentCtl,
                    fieldKeyPrefix: 'member-${widget.memberId}',
                    onAgentChanged: (value) {
                      _agentCtl.text = value;
                      _persistImmediate(member.copyWith(agent: value));
                    },
                  ),
                  showDividerBelow: true,
                ),
              if (!discrete.isTeamLead)
                _MemberReplicasRow(
                  teamId: widget.teamId,
                  memberId: widget.memberId,
                  onPersist: _persistImmediate,
                ),
              SettingsLabeledStackedRow(
                title: l10n.memberExtraArgs,
                subtitle: l10n.memberExtraArgsSubtitle,
                body: TextField(
                  controller: _argsCtl,
                  focusNode: _argsFocus,
                  decoration: const InputDecoration(),
                  onChanged: (_) => _schedulePersist(),
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

class _MemberSkipPermissionsSwitch extends StatelessWidget {
  const _MemberSkipPermissionsSwitch({
    required this.teamId,
    required this.memberId,
    required this.onPersist,
  });

  final String teamId;
  final String memberId;
  final void Function(TeamMemberConfig next) onPersist;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final skip = context.select<LaunchProfileCubit, bool?>(
      (c) => LaunchProfileSelectors.memberDiscreteFields(
        c.state,
        teamId,
        memberId,
      )?.dangerouslySkipPermissions,
    );
    if (skip == null) return const SizedBox.shrink();

    return SettingsLabeledRow(
      title: l10n.memberDangerouslySkipPermissions,
      subtitle: l10n.memberDangerouslySkipPermissionsHint,
      trailing: Switch(
        value: skip,
        onChanged: (v) {
          final member = LaunchProfileSelectors.memberById(
            LaunchProfileSelectors.teamById(
              context.read<LaunchProfileCubit>().state,
              teamId,
            ),
            memberId,
          );
          if (member == null) return;
          onPersist(member.copyWith(dangerouslySkipPermissions: v));
        },
      ),
      showDividerBelow: true,
    );
  }
}

class _MemberReplicasRow extends StatelessWidget {
  const _MemberReplicasRow({
    required this.teamId,
    required this.memberId,
    required this.onPersist,
  });

  final String teamId;
  final String memberId;
  final void Function(TeamMemberConfig next) onPersist;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final replicas = context.select<LaunchProfileCubit, int?>(
      (c) => LaunchProfileSelectors.memberDiscreteFields(
        c.state,
        teamId,
        memberId,
      )?.replicas,
    );
    if (replicas == null) return const SizedBox.shrink();

    return SettingsLabeledRow(
      title: l10n.memberReplicas,
      subtitle: l10n.memberReplicasSubtitle,
      trailing: _ReplicasStepper(
        value: replicas,
        onChanged: (v) {
          final member = LaunchProfileSelectors.memberById(
            LaunchProfileSelectors.teamById(
              context.read<LaunchProfileCubit>().state,
              teamId,
            ),
            memberId,
          );
          if (member == null) return;
          onPersist(member.copyWith(replicas: v));
        },
      ),
      showDividerBelow: true,
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
