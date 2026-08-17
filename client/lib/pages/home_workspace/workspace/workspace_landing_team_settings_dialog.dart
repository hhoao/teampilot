import 'dart:async';
import '../../../widgets/settings/configured_status_badge.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/app_provider_cubit.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_provider_config.dart';
import '../../../models/cli_preset.dart';
import '../../../models/team_config.dart';
import '../../../models/launch_security_policy.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/cli/preset_resolver.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/capabilities/provider_capability.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/launch/member_placement_save.dart';
import '../../../services/launch/team_settings_commit_service.dart';
import '../../../services/workspace/workspace_pane_policy.dart';
import '../../../utils/team/team_member_naming.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../../../widgets/settings/settings_dialog_pane_host.dart';
import '../../../widgets/team/team_lead_badge.dart';
import '../../team_config/team_config_helpers.dart';
import '../../team_config/team_default_preset_configure_dialog.dart';
import '../../team_config/team_member_launch_config_helpers.dart';
import '../../team_config/team_member_launch_config_section.dart';
import 'config/workspace_cli_config_helpers.dart';
import 'mixed_workspace_member_placement_panel.dart';

const double _kDialogWidth = 960;
const double _kDialogHeight = 720;

enum _LandingTeamSettingsSection { team, members, machines }

/// Launch-critical team settings from compose landing (left nav + right pane).
///
/// Edits a local draft and only persists on Save (single commit via
/// [TeamSettingsCommitService]); nested configure dialogs return their updated
/// team. Escape / barrier tap safely discard the draft.
Future<bool?> showLandingTeamSettingsDialog(
  BuildContext context, {
  required Workspace workspace,
  required TeamProfile team,
}) {
  return showTpDialog<bool?>(
    context: context,
    presentation: TpDialogPresentation.page,
    mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
    maxWidth: _kDialogWidth,
    maxHeight: _kDialogHeight,
    builder: (_) =>
        _LandingTeamSettingsDialog(workspace: workspace, team: team),
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

class _LandingTeamSettingsDialogState
    extends State<_LandingTeamSettingsDialog> {
  late int _selectedIndex;
  late final int _initialIndex;
  late TeamProfile _teamDraft;
  late Workspace _workspace;
  late MemberPlacementByTarget _placement;
  var _saving = false;
  final _wideBodyKey = GlobalKey();

  bool get _needsMixedInit => workspaceNeedsMixedPlacementInit(
    folders: _workspace.folders,
    teamId: widget.team.id,
    initializedByTeam: _workspace.memberPlacementInitializedByTeam,
  );

  List<_LandingTeamSettingsSection> get _sections => [
    _LandingTeamSettingsSection.team,
    _LandingTeamSettingsSection.members,
    _LandingTeamSettingsSection.machines,
  ];

  @override
  void initState() {
    super.initState();
    _workspace = widget.workspace;
    final cubit = context.read<LaunchProfileCubit>();
    _teamDraft = _teamFromCubit(cubit) ?? widget.team;
    _placement = _placementFromWorkspace(_workspace, _teamDraft);
    _initialIndex = _needsMixedInit
        ? _sections.indexOf(_LandingTeamSettingsSection.machines)
        : 0;
    _selectedIndex = _initialIndex;
    unawaited(
      cubit.selectTeam(widget.team.id, silent: true, syncResources: false),
    );
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
    folders: _workspace.folders,
    placement: _placement,
  );

  void _onWorkspaceRemapped(Workspace updated) {
    setState(() {
      _workspace = updated;
      _placement = _placementFromWorkspace(_workspace, _teamDraft);
    });
  }

  bool get _canSave => !_saving && _preparedSave.leadValid;

  /// Adopts a nested-configure result as the new draft. Nested dialogs persist
  /// via [LaunchProfileCubit] immediately, so their result becomes the new
  /// baseline; draft-only fields (switches) are re-overlaid on top.
  void _adoptUpdatedTeam(TeamProfile updated) {
    setState(() {
      _teamDraft = updated.copyWith(
        forceTeamLeadDelegateMode: _teamDraft.forceTeamLeadDelegateMode,
        updateForceTeamLeadDelegateMode: true,
        members: [
          for (final member in updated.members)
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
      launchSecurityPolicy: draftMember.launchSecurityPolicy,
    );
  }

  Future<void> _openTeamPresetConfigure() async {
    final cubit = context.read<LaunchProfileCubit>();
    final updated = await openTeamDefaultPresetConfigureDialog(
      context,
      team: _teamDraft,
      cubit: cubit,
    );
    if (!mounted || updated == null) return;
    _adoptUpdatedTeam(updated);
  }

  Future<void> _openMemberConfigure(TeamMemberConfig member) async {
    final cubit = context.read<LaunchProfileCubit>();
    final updated = await showMemberLaunchConfigureDialog(
      context,
      team: _teamDraft,
      member: member,
      cubit: cubit,
    );
    if (!mounted || updated == null) return;
    _adoptUpdatedTeam(updated);
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

  /// Draft-only dismiss: nothing was persisted by this dialog, so Cancel just
  /// pops (nested configure dialogs already committed their own edits).
  void _cancel() {
    Navigator.of(context).pop(false);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final ok =
          await TeamSettingsCommitService(
            launchProfileCubit: context.read<LaunchProfileCubit>(),
            sessionRepository: context.read<SessionRepository>(),
            chatCubit: context.read<ChatCubit>(),
          ).commit(
            workspaceId: _workspace.workspaceId,
            teamId: widget.team.id,
            prepared: _preparedSave,
          );
      if (ok && mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TpDialogNavShell(
            mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
            onClose: _cancel,
            navTitle: (c) => c.l10n.teamSettings,
            initialIndex: _initialIndex,
            onSelectedIndexChanged: (index) {
              setState(() => _selectedIndex = index);
            },
            entries: _mapEntries(),
          ),
        ),
        SafeArea(
          top: false,
          child: _Footer(
            canSave: _canSave,
            saving: _saving,
            placementHint: !_preparedSave.leadValid
                ? context.l10n.mixedWorkspaceLeadPlacementInvalid
                : _needsMixedInit
                ? context.l10n.mixedWorkspaceMemberAssignmentIncomplete
                : null,
            onCancel: _cancel,
            onSave: () => unawaited(_save()),
          ),
        ),
      ],
    );
  }

  bool _isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >=
      WorkspacePanePolicy.narrowBreakpointWidth;

  Widget _wideBody(BuildContext context) {
    return TpDeferredMountShell(
      key: const ValueKey('landing-team-settings-deferred-mount'),
      delayFrames: 1,
      child: RepaintBoundary(
        child: SettingsDialogPaneHost(
          key: _wideBodyKey,
          paneCount: _sections.length,
          selectedIndex: _selectedIndex,
          builder: (context, paneIndex) =>
              _paneBodyForSection(context, _sections[paneIndex]),
        ),
      ),
    );
  }

  Widget _paneBodyForSection(
    BuildContext context,
    _LandingTeamSettingsSection section,
  ) {
    return _PaneBody(
      section: section,
      teamDraft: _teamDraft,
      workspace: _workspace,
      placement: _placement,
      onPlacementChanged: (next) => setState(() => _placement = next),
      onWorkspaceRemapped: _onWorkspaceRemapped,
      onDelegateChanged: (value) => setState(
        () => _teamDraft = _teamDraft.copyWith(
          forceTeamLeadDelegateMode: value,
          updateForceTeamLeadDelegateMode: true,
        ),
      ),
      onMemberUpdated: _updateMember,
      onOpenTeamPresetConfigure: _openTeamPresetConfigure,
      onOpenMemberConfigure: _openMemberConfigure,
    );
  }

  List<TpDialogNavEntry> _mapEntries() {
    return [
      for (final section in _sections)
        TpDialogNavEntry(
          icon: switch (section) {
            _LandingTeamSettingsSection.team => Icons.tune_outlined,
            _LandingTeamSettingsSection.members => Icons.groups_outlined,
            _LandingTeamSettingsSection.machines => Icons.hub_outlined,
          },
          navLabel: (c) => switch (section) {
            _LandingTeamSettingsSection.team =>
              c.l10n.landingTeamSettingsNavTeam,
            _LandingTeamSettingsSection.members => c.l10n.members,
            _LandingTeamSettingsSection.machines =>
              c.l10n.landingTeamSettingsNavMachines,
          },
          title: (c) => switch (section) {
            _LandingTeamSettingsSection.team =>
              c.l10n.landingTeamSettingsNavTeam,
            _LandingTeamSettingsSection.members => c.l10n.members,
            _LandingTeamSettingsSection.machines =>
              c.l10n.landingTeamSettingsNavMachines,
          },
          subtitle: (c) => switch (section) {
            _LandingTeamSettingsSection.team =>
              c.l10n.landingTeamSettingsGlobalHint,
            _LandingTeamSettingsSection.members =>
              '${_teamDraft.members.where((m) => m.isValid).length}',
            _LandingTeamSettingsSection.machines => _machinesSubtitle(
              c.l10n,
              _teamDraft,
              _placement,
            ),
          },
          bodyBuilder: (context) {
            if (_isWide(context)) {
              return _wideBody(context);
            }
            return _paneBodyForSection(context, section);
          },
        ),
    ];
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
    required this.onWorkspaceRemapped,
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
  final ValueChanged<Workspace> onWorkspaceRemapped;
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
        onWorkspaceRemapped: onWorkspaceRemapped,
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
        catalogCli != null &&
        (CliToolRegistryScope.of(
              context,
            ).capability<ProviderCapability>(catalogCli)?.supportsDelegate ??
            false);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.landingTeamSettingsGlobalHint,
            style: TpTextStyles.of(context).mutedSm,
          ),
          const SizedBox(height: 16),
          TpCard.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TeamDefaultPresetSummary(
                  team: team,
                  onConfigure: onOpenTeamPresetConfigure,
                  showDividerBelow: showDelegateRow,
                ),
                if (showDelegateRow)
                  TpPreferenceRow(
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
    final styles = TpTextStyles.of(context);
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final icon = catalogDef != null
                  ? CliBrandIcon(
                      cli: displayCli,
                      definition: catalogDef,
                      label: cliDisplayName(catalogDef, l10n),
                      size: 40,
                      borderRadius: 10,
                    )
                  : Icon(Icons.tune_outlined, size: 40, color: cs.primary);
              final summary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          l10n.teamDefaultPresetLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles.lgColored(cs.onSurface),
                        ),
                      ),
                      const SizedBox(width: 8),
                      configuredStatusBadge(context, configured: configured),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    configured ? configLine : l10n.teamDefaultPresetSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: configured
                        ? styles.smMediumColored(cs.onSurfaceVariant)
                        : styles.smColored(cs.onSurfaceVariant),
                  ),
                ],
              );
              final configure = OutlinedButton.icon(
                onPressed: onConfigure,
                icon: Icon(Icons.tune, size: context.tpIconSizes.sm),
                label: Text(l10n.workspaceCliConfigure),
              );
              if (constraints.maxWidth < 420) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: 14),
                        Expanded(child: summary),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: configure),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(child: summary),
                  const SizedBox(width: 12),
                  configure,
                ],
              );
            },
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
      child: TpCard.outlined(
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
    final styles = TpTextStyles.of(context);
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
                                style: styles.lgColored(cs.onSurface),
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
                          style: configured
                              ? styles.smMediumColored(cs.onSurfaceVariant)
                              : styles.smColored(cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => onOpenMemberConfigure(member),
                    icon: Icon(Icons.tune, size: context.tpIconSizes.sm),
                    label: Text(l10n.workspaceCliConfigure),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TpPreferenceRow(
                title: l10n.memberDangerouslySkipPermissions,
                subtitle: l10n.memberDangerouslySkipPermissionsHint,
                trailing: Switch(
                  value: member.launchSecurityPolicy.requiresDangerousExecution,
                  onChanged: (value) => onMemberUpdated(
                    member.copyWith(
                      launchSecurityPolicy: value
                          ? LaunchSecurityPolicy.fullAccess
                          : const LaunchSecurityPolicy(),
                    ),
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
    required this.onWorkspaceRemapped,
  });

  final Workspace workspace;
  final TeamProfile team;
  final MemberPlacementByTarget placement;
  final ValueChanged<MemberPlacementByTarget> onPlacementChanged;
  final ValueChanged<Workspace> onWorkspaceRemapped;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.mixedWorkspaceMemberAssignmentSubtitle,
          style: TpTextStyles.of(context).mutedSm,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: MixedWorkspaceMemberPlacementPanel(
            workspace: workspace,
            members: team.members,
            placement: placement,
            onPlacementChanged: onPlacementChanged,
            onWorkspaceRemapped: onWorkspaceRemapped,
            team: team,
            globalPresets: context.watch<CliPresetsCubit>().state.presets,
            remoteCliReadiness: context.read<ChatCubit>().remoteCliReadiness,
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
                style: TpTextStyles.of(context).smColored(cs.error),
              ),
            )
          else
            const Spacer(),
          TextButton(
            onPressed: saving ? null : onCancel,
            child: Text(l10n.cancel),
          ),
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
