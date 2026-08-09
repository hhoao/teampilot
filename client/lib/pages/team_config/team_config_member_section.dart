import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../cubits/team/launch_profile_selectors.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/discoverable_member.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../services/cli/flashskyai/agent_catalog_service.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/expert_hub/expert_member_resolver.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/cli/member_agent_preset_field.dart';
import '../../widgets/team/team_lead_badge.dart';
import '../expert_hub/expert_landing_picker_sheet.dart';
import '../home_workspace/home_workspace_lazy_mount.dart';
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
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    final memberId = selectedMemberId;
    final hasMember =
        memberId != null &&
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
          style: TpTextStyles.of(
            context,
          ).mdColored(textBase.withValues(alpha: 0.55)),
        ),
      );
    }

    return HomeWorkspaceLazyMount(
      mountKey: '$teamId-$memberId',
      child: SingleChildScrollView(
        child: TeamMemberConfigForm(
          key: ValueKey('member-form-$memberId'),
          teamId: teamId,
          memberId: memberId,
        ),
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
  late TextEditingController _agentCtl;
  late TextEditingController _argsCtl;
  late FocusNode _argsFocus;
  late Debouncer _persistDebouncer;
  List<String> _userAgentIds = const [];
  LaunchProfileCubit? _profileCubit;
  bool _controllersSynced = false;

  LaunchProfileCubit get _cubit {
    final cached = _profileCubit;
    if (cached != null) return cached;
    return context.read<LaunchProfileCubit>();
  }

  TeamMemberConfig? _memberSnapshot(LaunchProfileCubit cubit, String memberId) {
    final team = LaunchProfileSelectors.teamById(cubit.state, widget.teamId);
    return LaunchProfileSelectors.memberById(team, memberId);
  }

  TeamRosterSlot? _slotSnapshot(LaunchProfileCubit cubit, String memberId) {
    final team = LaunchProfileSelectors.teamById(cubit.state, widget.teamId);
    if (team == null) return null;
    for (final slot in team.roster) {
      if (slot.id == memberId) return slot;
    }
    return null;
  }

  TeamMemberConfig? get _member => _memberSnapshot(_cubit, widget.memberId);

  TeamProfile? get _team =>
      LaunchProfileSelectors.teamById(_cubit.state, widget.teamId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _profileCubit = context.read<LaunchProfileCubit>();
    if (!_controllersSynced) {
      _controllersSynced = true;
      _syncControllersFromMember(
        _memberSnapshot(_profileCubit!, widget.memberId),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _initControllersForMember(null);
    _initFocusNodes();
    _initDebouncer();
    _loadUserAgents();
  }

  void _initControllersForMember(TeamMemberConfig? member) {
    _agentCtl = TextEditingController(text: member?.agent ?? '');
    _argsCtl = TextEditingController(text: member?.extraArgs ?? '');
  }

  void _initFocusNodes() {
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
    _syncControllerIfIdle(_agentCtl, null, member.agent);
    _syncControllerIfIdle(_argsCtl, _argsFocus, member.extraArgs);
  }

  Future<void> _loadUserAgents() async {
    final ids = await FlashskyaiAgentCatalogService().listUserAgentIds();
    if (!mounted) return;
    setState(() => _userAgentIds = ids);
  }

  void _syncControllersFromMember(TeamMemberConfig? member) {
    if (member == null) return;
    _agentCtl.text = member.agent;
    _argsCtl.text = member.extraArgs;
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
    _flushPersistOnDispose(widget.memberId);
    _persistDebouncer.dispose();
    _argsFocus.dispose();
    _agentCtl.dispose();
    _argsCtl.dispose();
    super.dispose();
  }

  TeamMemberConfig _memberFromControllers(TeamMemberConfig base) {
    return base.copyWith(agent: _agentCtl.text, extraArgs: _argsCtl.text);
  }

  void _flushPersistForMember(String memberId) {
    if (!mounted) return;
    _flushPersistWithCubit(_cubit, memberId);
  }

  void _flushPersistOnDispose(String memberId) {
    final cubit = _profileCubit;
    if (cubit == null) return;
    _flushPersistWithCubit(cubit, memberId);
  }

  void _flushPersistWithCubit(LaunchProfileCubit cubit, String memberId) {
    _persistDebouncer.cancel();
    final member = _memberSnapshot(cubit, memberId);
    if (member == null) return;
    final next = _memberFromControllers(member);
    if (_membersEqualForPersist(member, next)) return;
    unawaited(cubit.updateMember(memberId, next));
  }

  bool _membersEqualForPersist(TeamMemberConfig a, TeamMemberConfig b) {
    return a.agent == b.agent && a.extraArgs == b.extraArgs;
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

  void _onArgsFocusChanged() => _onFieldFocusChanged(_argsFocus);

  void _onFieldFocusChanged(FocusNode node) {
    if (!node.hasFocus) _flushPersistForMember(widget.memberId);
  }

  Future<void> _applyExpert(DiscoverableMember expert) async {
    await _cubit.setMemberExpert(widget.memberId, expert.key);
  }

  Future<void> _openExpertHubPicker() async {
    await showExpertApplyPickerSheet(
      context,
      onApply: (expert) => unawaited(_applyExpert(expert)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
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
    // Keep Provider lookups outside select callbacks (nested read/watch is forbidden).
    final expertKey = context.select<LaunchProfileCubit, String?>((c) {
      return _slotSnapshot(c, widget.memberId)?.expertKey;
    });
    final hubState = context.watch<ExpertHubCubit>().state;
    final resolvedExpert = ExpertMemberResolver.resolve(
      key: expertKey,
      hubState: hubState,
    );
    final expertLabel = ExpertMemberResolver.labelForKey(
      key: expertKey,
      fallbackLabel: l10n.expertHubNoneSelected,
      hubState: hubState,
    );
    final team = _team;
    final member = _member;
    if (team == null ||
        teamShell == null ||
        discrete == null ||
        member == null) {
      return const SizedBox.shrink();
    }
    // Persona prose lives on the catalog expert; prefer live resolve so a
    // stale/empty materialized member cache cannot blank the read-only fields.
    final hasExpert = (expertKey?.trim().isNotEmpty ?? false);
    final responsibilities =
        resolvedExpert?.member.responsibilities.trim().isNotEmpty == true
        ? resolvedExpert!.member.responsibilities
        : member.responsibilities;
    final playbook = resolvedExpert?.member.playbook.trim().isNotEmpty == true
        ? resolvedExpert!.member.playbook
        : member.playbook;
    final emptyPersonaHint = hasExpert ? null : l10n.memberPersonaEmptyNoExpert;

    final showMemberAgentPreset = memberShowsAgentPresetUi(
      context,
      team: team,
      member: member,
    );
    final agentPresetCli = memberAgentPresetCli(team: team, member: member);
    final memberAgentStyle = showMemberAgentPreset && agentPresetCli != null
        ? CliToolRegistryScope.of(
            context,
          ).memberAgentPresetStyle(agentPresetCli)
        : null;

    final canDelete = teamShell.memberCount > 1 && !discrete.isTeamLead;
    final errorColor = Theme.of(context).colorScheme.error;

    return TpCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpPreferenceStack(
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
                            size: context.tpIconSizes.md,
                            color: errorColor,
                          ),
                        ),
                    ],
                  )
                : null,
            body: Text(
              member.name.trim().isEmpty ? l10n.memberName : member.name,
              style: styles.md,
            ),
            showDividerBelow: true,
          ),
          TpPreferenceStack(
            title: l10n.expertHubNav,
            subtitle: l10n.expertHubSubtitle,
            body: Row(
              children: [
                Expanded(child: Text(expertLabel, style: styles.md)),
                OutlinedButton(
                  onPressed: _openExpertHubPicker,
                  child: Text(l10n.expertHubBrowseAll),
                ),
              ],
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
          TpPreferenceStack(
            title: l10n.memberResponsibilities,
            subtitle: l10n.memberPromptSubtitle,
            body: _ReadOnlyMultilineText(
              text: responsibilities,
              emptyHint: emptyPersonaHint ?? l10n.memberResponsibilitiesEmpty,
              style: styles.md,
              mutedStyle: styles.mdColored(muted),
            ),
            showDividerBelow: true,
          ),
          TpPreferenceStack(
            title: l10n.memberPlaybook,
            subtitle: l10n.memberPlaybookSubtitle,
            body: _ReadOnlyMultilineText(
              text: playbook,
              emptyHint: emptyPersonaHint ?? l10n.memberPlaybookEmpty,
              style: styles.md,
              mutedStyle: styles.mdColored(muted),
            ),
            showDividerBelow: true,
          ),
          TpDisclosure(
            title: l10n.workspaceAdvancedSettings,
            subtitle: l10n.workspaceAdvancedSettingsSubtitle,
            children: [
              if (showMemberAgentPreset &&
                  memberAgentStyle != null &&
                  agentPresetCli != null)
                TpPreferenceStack(
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
              TpPreferenceStack(
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

class _ReadOnlyMultilineText extends StatelessWidget {
  const _ReadOnlyMultilineText({
    required this.text,
    required this.emptyHint,
    required this.style,
    required this.mutedStyle,
  });

  final String text;
  final String emptyHint;
  final TextStyle style;
  final TextStyle mutedStyle;

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return Text(emptyHint, style: mutedStyle);
    }
    return SelectableText(trimmed, style: style);
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

    return TpPreferenceRow(
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
