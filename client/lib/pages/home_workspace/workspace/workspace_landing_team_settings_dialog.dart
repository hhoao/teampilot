import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/app_provider_cubit.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_provider_config.dart';
import '../../../models/cli_preset.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/cli/preset_resolver.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/launch/member_placement_save.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/team_member_naming.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../../../widgets/deferred_mount_shell.dart';
import '../../../widgets/settings/settings_dialog_pane_host.dart';
import '../../../widgets/settings/workspace_hub_shell.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';
import '../../../widgets/team/team_lead_badge.dart';
import '../../team_config/team_config_helpers.dart';
import '../../team_config/team_default_preset_configure_dialog.dart';
import '../../team_config/team_member_launch_config_helpers.dart';
import '../../team_config/team_member_launch_config_section.dart';
import 'config/workspace_cli_config_helpers.dart';
import 'mixed_workspace_member_placement_panel.dart';

const double _kDialogWidth = 960;
const double _kDialogHeight = 720;
const double _kDialogInset = 24;

enum _LandingTeamSettingsSection { team, members, machines }

/// Launch-critical team settings from compose landing (left nav + right pane).
Future<bool?> showLandingTeamSettingsDialog(
  BuildContext context, {
  required Workspace workspace,
  required TeamProfile team,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _LandingTeamSettingsDialog(
      workspace: workspace,
      team: team,
    ),
  );
}

/// Whether the landing gear should show an attention dot.
///
/// Mixed workspaces need a first Machines confirmation; any topology with
/// remembered pins must keep the lead on a valid preferred host. Empty
/// local/remote targets do not alert (defaults materialize at session create).
bool landingTeamSettingsNeedsAttention({
  required Workspace workspace,
  required TeamProfile team,
}) {
  if (workspaceNeedsMixedPlacementInit(
    folders: workspace.folders,
    teamId: team.id,
    initializedByTeam: workspace.memberPlacementInitializedByTeam,
  )) {
    return true;
  }
  final targets = rememberedMemberTargets(
    workspace.memberTargetsByTeam,
    team.id,
  );
  if (targets.isEmpty &&
      workspaceTopologyOf(workspace.folders) != WorkspaceTopology.mixed) {
    return false;
  }
  return !leadPlacementValid(
    folders: workspace.folders,
    members: team.members.where((m) => m.isValid).toList(),
    targets: targets,
  );
}

class _LandingTeamSettingsDialog extends StatefulWidget {
  const _LandingTeamSettingsDialog({
    required this.workspace,
    required this.team,
  });

  final Workspace workspace;
  final TeamProfile team;

  @override
  State<_LandingTeamSettingsDialog> createState() =>
      _LandingTeamSettingsDialogState();
}

class _LandingTeamSettingsDialogState extends State<_LandingTeamSettingsDialog> {
  late final ValueNotifier<int> _selectedIndex;
  late TeamProfile _initialTeam;
  late TeamProfile _teamDraft;
  late MemberPlacementByTarget _placement;
  var _saving = false;
  var _cubitDirty = false;

  bool get _needsMixedInit => workspaceNeedsMixedPlacementInit(
    folders: widget.workspace.folders,
    teamId: widget.team.id,
    initializedByTeam: widget.workspace.memberPlacementInitializedByTeam,
  );

  List<_LandingTeamSettingsSection> get _sections => [
    _LandingTeamSettingsSection.team,
    _LandingTeamSettingsSection.members,
    _LandingTeamSettingsSection.machines,
  ];

  @override
  void initState() {
    super.initState();
    final cubit = context.read<LaunchProfileCubit>();
    _initialTeam = _teamFromCubit(cubit) ?? widget.team;
    _teamDraft = _initialTeam;
    _placement = _placementFromWorkspace(widget.workspace, _teamDraft);
    final initialIndex = _needsMixedInit
        ? _sections.indexOf(_LandingTeamSettingsSection.machines)
        : 0;
    _selectedIndex = ValueNotifier(initialIndex);
    unawaited(
      cubit.selectTeam(widget.team.id, silent: true, syncResources: false),
    );
  }

  @override
  void dispose() {
    _selectedIndex.dispose();
    super.dispose();
  }

  TeamProfile? _teamFromCubit(LaunchProfileCubit cubit) {
    for (final team in cubit.state.teams) {
      if (team.id == widget.team.id) return team;
    }
    return null;
  }

  MemberPlacementByTarget _placementFromWorkspace(
    Workspace workspace,
    TeamProfile team,
  ) {
    final remembered = rememberedMemberTargets(
      workspace.memberTargetsByTeam,
      team.id,
    );
    final members = healMemberReplicasFromTargets(
      members: team.members,
      targets: remembered,
    );
    if (remembered.isEmpty) {
      // In-memory defaults only — persist on Save via prepareMemberPlacementSave.
      return defaultMemberPlacement(
        folders: workspace.folders,
        members: members,
      );
    }
    return memberPlacementFromMemberTargets(
      members: members,
      targets: remembered,
    );
  }

  PreparedMemberPlacementSave get _preparedSave => prepareMemberPlacementSave(
    team: _teamDraft,
    folders: widget.workspace.folders,
    placement: _placement,
  );

  bool get _canSave => !_saving && _preparedSave.leadValid;

  Future<void> _syncDraftToCubit() async {
    final cubit = context.read<LaunchProfileCubit>();
    await cubit.selectTeam(widget.team.id, silent: true, syncResources: false);
    await cubit.updateSelected(_teamDraft);
    _cubitDirty = true;
    _refreshDraftFromCubit(overlayDraftFields: true);
  }

  void _refreshDraftFromCubit({required bool overlayDraftFields}) {
    final cubit = context.read<LaunchProfileCubit>();
    final fromCubit = _teamFromCubit(cubit);
    if (fromCubit == null) return;
    if (!overlayDraftFields) {
      setState(() => _teamDraft = fromCubit);
      return;
    }
    setState(() {
      _teamDraft = fromCubit.copyWith(
        forceTeamLeadDelegateMode: _teamDraft.forceTeamLeadDelegateMode,
        updateForceTeamLeadDelegateMode: true,
        members: [
          for (final member in fromCubit.members)
            _overlayMemberDraftFields(member),
        ],
      );
    });
  }

  TeamMemberConfig _overlayMemberDraftFields(TeamMemberConfig cubitMember) {
    final draftMember = _teamDraft.members.cast<TeamMemberConfig?>().firstWhere(
      (m) => m!.id == cubitMember.id,
      orElse: () => null,
    );
    if (draftMember == null) return cubitMember;
    return cubitMember.copyWith(
      dangerouslySkipPermissions: draftMember.dangerouslySkipPermissions,
    );
  }

  Future<void> _openTeamPresetConfigure() async {
    await _syncDraftToCubit();
    if (!mounted) return;
    final cubit = context.read<LaunchProfileCubit>();
    final team = _teamFromCubit(cubit) ?? _teamDraft;
    await openTeamDefaultPresetConfigureDialog(
      context,
      team: team,
      cubit: cubit,
    );
    if (!mounted) return;
    _cubitDirty = true;
    _refreshDraftFromCubit(overlayDraftFields: true);
  }

  Future<void> _openMemberConfigure(TeamMemberConfig member) async {
    await _syncDraftToCubit();
    if (!mounted) return;
    final cubit = context.read<LaunchProfileCubit>();
    final team = _teamFromCubit(cubit) ?? _teamDraft;
    await showDialog<void>(
      context: context,
      builder: (ctx) => MemberLaunchConfigureDialog(
        team: team,
        member: member,
        cubit: cubit,
      ),
    );
    if (!mounted) return;
    _cubitDirty = true;
    _refreshDraftFromCubit(overlayDraftFields: true);
  }

  void _updateMember(TeamMemberConfig updated) {
    setState(() {
      _teamDraft = _teamDraft.copyWith(
        members: [
          for (final member in _teamDraft.members)
            if (member.id == updated.id) updated else member,
        ],
      );
    });
  }

  Future<void> _revertCubitIfNeeded() async {
    if (!_cubitDirty) return;
    final cubit = context.read<LaunchProfileCubit>();
    await cubit.selectTeam(widget.team.id, silent: true, syncResources: false);
    await cubit.updateSelected(_initialTeam);
  }

  Future<void> _cancel() async {
    await _revertCubitIfNeeded();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final cubit = context.read<LaunchProfileCubit>();
      final sessions = context.read<SessionRepository>();
      final prepared = prepareMemberPlacementSave(
        team: _teamDraft,
        folders: widget.workspace.folders,
        placement: _placement,
      );
      if (!prepared.leadValid) return;
      await cubit.selectTeam(widget.team.id, silent: true, syncResources: false);
      // Persist placement totals on roster.overrides.replicas (members alone
      // are runtime-only and would be dropped on the next materialize).
      _teamDraft = prepared.team;
      await cubit.updateSelected(_teamDraft);
      await sessions.updateWorkspaceMemberPlacement(
        widget.workspace.workspaceId,
        widget.team.id,
        targets: prepared.targets,
      );
      if (mounted) {
        await context.read<ChatCubit>().loadWorkspaceData(sessions);
      }
      _cubitDirty = false;
      _initialTeam = _teamDraft;
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogWidth = _kDialogWidth.clamp(
      0.0,
      media.size.width - _kDialogInset,
    );
    final dialogHeight = _kDialogHeight.clamp(
      0.0,
      media.size.height - _kDialogInset,
    );
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(_kDialogInset / 2),
      backgroundColor: cs.workspacePage,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Row(
          children: [
            _Nav(
              title: context.l10n.teamSettings,
              sections: _sections,
              selectedListenable: _selectedIndex,
              onSelect: (index) => _selectedIndex.value = index,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: DeferredMountShell(
                  delayFrames: 1,
                  child: ListenableBuilder(
                    listenable: _selectedIndex,
                    builder: (context, _) {
                      final section = _sections[_selectedIndex.value];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PaneHeader(
                            section: section,
                            team: _teamDraft,
                            machinesHint: !_preparedSave.leadValid
                                ? context
                                      .l10n
                                      .mixedWorkspaceLeadPlacementInvalid
                                : _needsMixedInit
                                ? context
                                      .l10n
                                      .mixedWorkspaceMemberAssignmentIncomplete
                                : null,
                            placement: _placement,
                            onClose: _cancel,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                16,
                                24,
                                0,
                              ),
                              child: RepaintBoundary(
                                child: SettingsDialogPaneHost(
                                  key: const ValueKey(
                                    'landing-team-settings-pane-host',
                                  ),
                                  paneCount: _sections.length,
                                  selectedIndex: _selectedIndex.value,
                                  builder: (context, paneIndex) {
                                    final active = _sections[paneIndex];
                                    return _PaneBody(
                                      section: active,
                                      teamDraft: _teamDraft,
                                      workspace: widget.workspace,
                                      placement: _placement,
                                      onPlacementChanged: (next) =>
                                          setState(() => _placement = next),
                                      onDelegateChanged: (value) => setState(
                                        () => _teamDraft = _teamDraft.copyWith(
                                          forceTeamLeadDelegateMode: value,
                                          updateForceTeamLeadDelegateMode: true,
                                        ),
                                      ),
                                      onMemberUpdated: _updateMember,
                                      onOpenTeamPresetConfigure:
                                          _openTeamPresetConfigure,
                                      onOpenMemberConfigure:
                                          _openMemberConfigure,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          _Footer(
                            canSave: _canSave,
                            saving: _saving,
                            placementHint: !_preparedSave.leadValid
                                ? context
                                      .l10n
                                      .mixedWorkspaceLeadPlacementInvalid
                                : _needsMixedInit
                                ? context
                                      .l10n
                                      .mixedWorkspaceMemberAssignmentIncomplete
                                : null,
                            onCancel: _cancel,
                            onSave: _save,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({
    required this.title,
    required this.sections,
    required this.selectedListenable,
    required this.onSelect,
  });

  final String title;
  final List<_LandingTeamSettingsSection> sections;
  final ValueListenable<int> selectedListenable;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;

    String label(_LandingTeamSettingsSection section) => switch (section) {
      _LandingTeamSettingsSection.team => l10n.landingTeamSettingsNavTeam,
      _LandingTeamSettingsSection.members => l10n.members,
      _LandingTeamSettingsSection.machines =>
        l10n.landingTeamSettingsNavMachines,
    };

    IconData icon(_LandingTeamSettingsSection section) => switch (section) {
      _LandingTeamSettingsSection.team => Icons.tune_outlined,
      _LandingTeamSettingsSection.members => Icons.groups_outlined,
      _LandingTeamSettingsSection.machines => Icons.hub_outlined,
    };

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: cs.workspaceSubtleSurface,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
              child: Text(
                title,
                style: styles.subtitle.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: selectedListenable,
                builder: (context, _) {
                  final selected = selectedListenable.value;
                  return ListView(
                    children: [
                      for (final (index, section) in sections.indexed)
                        WorkspaceHubNavItem(
                          title: label(section),
                          icon: icon(section),
                          selected: index == selected,
                          onTap: () => onSelect(index),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.section,
    required this.team,
    required this.machinesHint,
    required this.placement,
    required this.onClose,
  });

  final _LandingTeamSettingsSection section;
  final TeamProfile team;
  final String? machinesHint;
  final MemberPlacementByTarget placement;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    final (title, subtitle) = switch (section) {
      _LandingTeamSettingsSection.team => (
        l10n.landingTeamSettingsNavTeam,
        l10n.landingTeamSettingsGlobalHint,
      ),
      _LandingTeamSettingsSection.members => (
        l10n.members,
        '${team.members.where((m) => m.isValid).length}',
      ),
      _LandingTeamSettingsSection.machines => (
        l10n.landingTeamSettingsNavMachines,
        _machinesSubtitle(l10n, team, placement),
      ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.subtitle.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (machinesHint != null &&
                    section == _LandingTeamSettingsSection.machines) ...[
                  const SizedBox(height: 6),
                  Text(
                    machinesHint!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: Icon(Icons.close, size: context.appIconSizes.md),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  static String _machinesSubtitle(
    AppLocalizations l10n,
    TeamProfile team,
    MemberPlacementByTarget placement,
  ) {
    var placed = 0;
    for (final member in team.members) {
      if (!member.isValid) continue;
      placed += memberPlacementCountForType(placement, member.id);
    }
    // Placement is source of truth: total == placed (may be 0 for non-leads).
    return l10n.mixedWorkspaceMemberPlacementProgress(placed, placed);
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody({
    required this.section,
    required this.teamDraft,
    required this.workspace,
    required this.placement,
    required this.onPlacementChanged,
    required this.onDelegateChanged,
    required this.onMemberUpdated,
    required this.onOpenTeamPresetConfigure,
    required this.onOpenMemberConfigure,
  });

  final _LandingTeamSettingsSection section;
  final TeamProfile teamDraft;
  final Workspace workspace;
  final MemberPlacementByTarget placement;
  final ValueChanged<MemberPlacementByTarget> onPlacementChanged;
  final ValueChanged<bool> onDelegateChanged;
  final ValueChanged<TeamMemberConfig> onMemberUpdated;
  final Future<void> Function() onOpenTeamPresetConfigure;
  final Future<void> Function(TeamMemberConfig member) onOpenMemberConfigure;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      _LandingTeamSettingsSection.team => _TeamPane(
        team: teamDraft,
        onDelegateChanged: onDelegateChanged,
        onOpenTeamPresetConfigure: onOpenTeamPresetConfigure,
      ),
      _LandingTeamSettingsSection.members => _MembersPane(
        team: teamDraft,
        onMemberUpdated: onMemberUpdated,
        onOpenMemberConfigure: onOpenMemberConfigure,
      ),
      _LandingTeamSettingsSection.machines => _MachinesPane(
        workspace: workspace,
        team: teamDraft,
        placement: placement,
        onPlacementChanged: onPlacementChanged,
      ),
    };
  }
}

class _TeamPane extends StatelessWidget {
  const _TeamPane({
    required this.team,
    required this.onDelegateChanged,
    required this.onOpenTeamPresetConfigure,
  });

  final TeamProfile team;
  final ValueChanged<bool> onDelegateChanged;
  final Future<void> Function() onOpenTeamPresetConfigure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final catalogCli = catalogCliForTeam(context, team.cli);
    final showDelegateRow =
        catalogCli == CliTool.claude || catalogCli == CliTool.flashskyai;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.landingTeamSettingsGlobalHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SettingsSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TeamDefaultPresetSummary(
                  team: team,
                  onConfigure: onOpenTeamPresetConfigure,
                  showDividerBelow: showDelegateRow,
                ),
                if (showDelegateRow)
                  SettingsLabeledRow(
                    title: l10n.teamLeadDelegateOnlyTitle,
                    subtitle: l10n.teamLeadDelegateOnlySubtitle,
                    trailing: Switch(
                      value: team.forceTeamLeadDelegateMode,
                      onChanged: onDelegateChanged,
                    ),
                    showDividerBelow: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamDefaultPresetSummary extends StatelessWidget {
  const _TeamDefaultPresetSummary({
    required this.team,
    required this.onConfigure,
    required this.showDividerBelow,
  });

  final TeamProfile team;
  final Future<void> Function() onConfigure;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final registry = CliToolRegistryScope.of(context);
    final presets = context.watch<CliPresetsCubit>().state.presets;
    final catalogCli = team.cli;
    final activePreset = team.activePresetId != null
        ? presets.cast<CliPreset?>().firstWhere(
            (p) => p?.id == team.activePresetId,
            orElse: () => null,
          )
        : null;
    final configured = teamLaunchDefaultsConfigured(
      team: team,
      presets: presets,
      catalogCli: catalogCli,
    );

    AppProviderConfig? selectedProvider;
    var hidesModelPicker = false;
    String configLine;
    CliTool displayCli = catalogCli;
    if (activePreset != null) {
      displayCli = activePreset.cli;
      final providers = context
          .watch<AppProviderCubit>()
          .state
          .providersFor(activePreset.cli)
          .toList(growable: false);
      final prov = activePreset.provider.trim();
      if (prov.isNotEmpty) {
        for (final p in providers) {
          if (p.id == prov) {
            selectedProvider = p;
            break;
          }
        }
      }
      hidesModelPicker = workspaceCliHidesModelPicker(
        registry,
        activePreset.cli,
        selectedProvider,
      );
      configLine = teamLaunchSummaryLine(
        l10n: l10n,
        team: team,
        body: teamPresetConfigLine(
          l10n: l10n,
          registry: registry,
          preset: activePreset,
          provider: selectedProvider,
          hidesModelPicker: hidesModelPicker,
        ),
      );
    } else {
      final providers = context
          .watch<AppProviderCubit>()
          .state
          .providersFor(catalogCli)
          .toList(growable: false);
      final prov = team.providerForCli(catalogCli);
      if (prov.isNotEmpty) {
        for (final p in providers) {
          if (p.id == prov) {
            selectedProvider = p;
            break;
          }
        }
      }
      hidesModelPicker = workspaceCliHidesModelPicker(
        registry,
        catalogCli,
        selectedProvider,
      );
      configLine = teamLaunchSummaryLine(
        l10n: l10n,
        team: team,
        body: teamCustomLaunchConfigLine(
          l10n: l10n,
          registry: registry,
          team: team,
          catalogCli: catalogCli,
          provider: selectedProvider,
          hidesModelPicker: hidesModelPicker,
        ),
      );
    }

    final catalogDef = registry.tryGet(displayCli);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              catalogDef != null
                  ? CliBrandIcon(
                      cli: displayCli,
                      definition: catalogDef,
                      label: cliDisplayName(catalogDef, l10n),
                      size: 40,
                      borderRadius: 10,
                    )
                  : Icon(Icons.tune_outlined, size: 40, color: cs.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.teamDefaultPresetLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: styles.prominent.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SettingsConfiguredBadge(configured: configured),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      configured
                          ? configLine
                          : l10n.teamDefaultPresetSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight:
                            configured ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onConfigure,
                icon: Icon(Icons.tune, size: context.appIconSizes.sm),
                label: Text(l10n.workspaceCliConfigure),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDividerBelow)
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

class _MembersPane extends StatelessWidget {
  const _MembersPane({
    required this.team,
    required this.onMemberUpdated,
    required this.onOpenMemberConfigure,
  });

  final TeamProfile team;
  final ValueChanged<TeamMemberConfig> onMemberUpdated;
  final Future<void> Function(TeamMemberConfig member) onOpenMemberConfigure;

  @override
  Widget build(BuildContext context) {
    final members = [
      for (final member in team.members)
        if (member.isValid) member,
    ];
    return SingleChildScrollView(
      child: SettingsSurfaceCard(
        child: Column(
          children: [
            for (final (index, member) in members.indexed)
              _MemberRow(
                team: team,
                member: member,
                showDividerBelow: index < members.length - 1,
                onMemberUpdated: onMemberUpdated,
                onOpenMemberConfigure: onOpenMemberConfigure,
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.team,
    required this.member,
    required this.showDividerBelow,
    required this.onMemberUpdated,
    required this.onOpenMemberConfigure,
  });

  final TeamProfile team;
  final TeamMemberConfig member;
  final bool showDividerBelow;
  final ValueChanged<TeamMemberConfig> onMemberUpdated;
  final Future<void> Function(TeamMemberConfig member) onOpenMemberConfigure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final registry = CliToolRegistryScope.of(context);
    final presets = context.watch<CliPresetsCubit>().state.presets;
    final providers = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(memberCustomCatalogCli(team, member))
        .toList(growable: false);
    AppProviderConfig? selectedProvider;
    final resolved = resolveMemberLaunch(
      team: team,
      member: member,
      globalPresets: presets,
    );
    final prov = resolved.provider.trim();
    if (prov.isNotEmpty) {
      for (final p in providers) {
        if (p.id == prov) {
          selectedProvider = p;
          break;
        }
      }
    }
    final configured = memberLaunchIsConfigured(
      team: team,
      member: member,
      registry: registry,
      presets: presets,
      provider: selectedProvider,
    );
    final hidesModelPicker = workspaceCliHidesModelPicker(
      registry,
      resolved.cli,
      selectedProvider,
    );
    final configLine = memberLaunchConfigLine(
      l10n: l10n,
      registry: registry,
      team: team,
      member: member,
      configured: configured,
      provider: selectedProvider,
      hidesModelPicker: hidesModelPicker,
      presets: presets,
    );
    final displayName = member.name.trim().isNotEmpty
        ? member.name.trim()
        : member.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: styles.prominent.copyWith(
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            if (TeamMemberNaming.isTeamLead(member)) ...[
                              const SizedBox(width: 8),
                              const TeamLeadBadge(compact: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          configured
                              ? configLine
                              : l10n.memberLaunchConfigSubtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: styles.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight:
                                configured ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => onOpenMemberConfigure(member),
                    icon: Icon(Icons.tune, size: context.appIconSizes.sm),
                    label: Text(l10n.workspaceCliConfigure),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SettingsLabeledRow(
                title: l10n.memberDangerouslySkipPermissions,
                subtitle: l10n.memberDangerouslySkipPermissionsHint,
                trailing: Switch(
                  value: member.dangerouslySkipPermissions,
                  onChanged: (value) => onMemberUpdated(
                    member.copyWith(dangerouslySkipPermissions: value),
                  ),
                ),
                showDividerBelow: false,
              ),
            ],
          ),
        ),
        if (showDividerBelow)
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}

class _MachinesPane extends StatelessWidget {
  const _MachinesPane({
    required this.workspace,
    required this.team,
    required this.placement,
    required this.onPlacementChanged,
  });

  final Workspace workspace;
  final TeamProfile team;
  final MemberPlacementByTarget placement;
  final ValueChanged<MemberPlacementByTarget> onPlacementChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.mixedWorkspaceMemberAssignmentSubtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: MixedWorkspaceMemberPlacementPanel(
            workspace: workspace,
            members: team.members,
            placement: placement,
            onPlacementChanged: onPlacementChanged,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.canSave,
    required this.saving,
    required this.placementHint,
    required this.onCancel,
    required this.onSave,
  });

  final bool canSave;
  final bool saving;
  final String? placementHint;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          if (placementHint != null)
            Expanded(
              child: Text(
                placementHint!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.error,
                ),
              ),
            )
          else
            const Spacer(),
          TextButton(onPressed: saving ? null : onCancel, child: Text(l10n.cancel)),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: canSave ? onSave : null,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
