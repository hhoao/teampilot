import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/cli_presets_cubit.dart';
import '../../../cubits/launch_profile_cubit.dart';
import '../../../models/landing_launch_context.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_preset.dart';
import '../../../models/personal_profile.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../services/storage/launch_profile_provisioner.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../../theme/workspace_surface_layers.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/landing_draft_resolver.dart';
import '../../../services/keyboard/compose_keyboard_shortcut_handler.dart';
import '../../../widgets/menu/sidebar_action_menu.dart';

enum _LandingConversationMode { team, simple }

enum _LandingPermissionMode { defaultPermissions, fullAccess }

typedef LandingComposeSubmit =
    void Function(String message, LandingLaunchContext draft);

class WorkspaceChatLanding extends StatefulWidget {
  const WorkspaceChatLanding({
    required this.workspace,
    required this.onSubmit,
    this.isSubmitting = false,
    this.disabled = false,
    super.key,
  });

  final Workspace workspace;
  final LandingComposeSubmit onSubmit;
  final bool isSubmitting;
  final bool disabled;

  @override
  State<WorkspaceChatLanding> createState() => _WorkspaceChatLandingState();
}

class _WorkspaceChatLandingState extends State<WorkspaceChatLanding> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;

  var _conversationMode = _LandingConversationMode.simple;
  var _permissionMode = _LandingPermissionMode.defaultPermissions;
  String? _selectedPresetId;
  String? _selectedTeamId;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      onKeyEvent: ComposeKeyboardShortcutHandler.keyHandler(
        controller: _controller,
        onSubmit: _submit,
        canSubmit: () => _canSubmit,
      ),
    );
    unawaited(_loadDraft());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final draft = await resolveLandingDraft(
      workspaceId: widget.workspace.workspaceId,
      workspace: widget.workspace,
    );
    if (!mounted) return;
    setState(() => _applyDraft(draft));
  }

  void _applyDraft(LandingLaunchContext draft) {
    _conversationMode = draft.isPersonal
        ? _LandingConversationMode.simple
        : _LandingConversationMode.team;
    _selectedTeamId = draft.teamId;
    _selectedPresetId = draft.presetId;

    if ((_selectedTeamId == null || _selectedTeamId!.isEmpty) &&
        _conversationMode == _LandingConversationMode.team) {
      final teams = context.read<LaunchProfileCubit>().state.teams;
      if (teams.isNotEmpty) _selectedTeamId = teams.first.id;
    }

    final personalId = draft.personalProfileId.trim();
    if (personalId.isNotEmpty) {
      final opened = context.read<LaunchProfileCubit>().byId(personalId);
      if (opened is PersonalProfile) {
        _selectedPresetId ??= opened.activePresetId;
      }
    }
  }

  LandingLaunchContext _currentDraft() {
    final defaultProfile = widget.workspace.defaultProfileId.trim().isNotEmpty
        ? widget.workspace.defaultProfileId.trim()
        : LaunchProfileProvisioner.defaultPersonalId;
    return LandingLaunchContext(
      isPersonal: _conversationMode == _LandingConversationMode.simple,
      personalProfileId: defaultProfile,
      presetId: _selectedPresetId,
      teamId: _selectedTeamId,
    );
  }

  void _persistDraft() {
    unawaited(
      persistLandingDraft(widget.workspace.workspaceId, _currentDraft()),
    );
  }

  bool get _canSubmit =>
      !widget.disabled &&
      !widget.isSubmitting &&
      _controller.text.trim().isNotEmpty;

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.disabled || widget.isSubmitting) return;
    widget.onSubmit(text, _currentDraft());
  }

  void _setConversationMode(_LandingConversationMode mode) {
    if (_conversationMode == mode) return;
    setState(() => _conversationMode = mode);
    _persistDraft();
  }

  void _setPermissionMode(_LandingPermissionMode mode) {
    if (_permissionMode == mode) return;
    setState(() => _permissionMode = mode);
  }

  void _selectPreset(String presetId) {
    setState(() => _selectedPresetId = presetId);
    _persistDraft();
  }

  void _selectTeam(String teamId) {
    setState(() => _selectedTeamId = teamId);
    _persistDraft();
  }

  String _conversationModeLabel(AppLocalizations l10n) {
    return switch (_conversationMode) {
      _LandingConversationMode.team => l10n.workspaceChatLandingModeTeam,
      _LandingConversationMode.simple => l10n.workspaceChatLandingModeSimple,
    };
  }

  String _autoChipLabel(
    AppLocalizations l10n, {
    required List<CliPreset> presets,
    required List<TeamProfile> teams,
  }) {
    if (_conversationMode == _LandingConversationMode.simple) {
      final preset = presets
          .where((p) => p.id == _selectedPresetId)
          .firstOrNull;
      return preset?.name.trim().isNotEmpty == true
          ? preset!.name.trim()
          : l10n.workspaceChatLandingUsePreset;
    }

    final team = teams.where((t) => t.id == _selectedTeamId).firstOrNull;
    return team?.name.trim().isNotEmpty == true
        ? team!.name.trim()
        : l10n.selectTeam;
  }

  String _permissionChipLabel(AppLocalizations l10n) {
    return switch (_permissionMode) {
      _LandingPermissionMode.defaultPermissions =>
        l10n.workspaceChatLandingDefaultPermissions,
      _LandingPermissionMode.fullAccess =>
        l10n.workspaceChatLandingFullAccessPermissions,
    };
  }

  List<SidebarActionMenuSpec> _conversationModeSpecs(AppLocalizations l10n) {
    return [
      SidebarActionMenuSpec.item(
        value: _LandingConversationMode.team,
        icon: Icons.groups_outlined,
        label: l10n.workspaceChatLandingModeTeam,
        selected: _conversationMode == _LandingConversationMode.team,
      ),
      SidebarActionMenuSpec.item(
        value: _LandingConversationMode.simple,
        icon: Icons.chat_bubble_outline,
        label: l10n.workspaceChatLandingModeSimple,
        selected: _conversationMode == _LandingConversationMode.simple,
      ),
    ];
  }

  List<SidebarActionMenuSpec> _autoChipSpecs(
    AppLocalizations l10n, {
    required List<CliPreset> presets,
    required List<TeamProfile> teams,
  }) {
    if (_conversationMode == _LandingConversationMode.simple) {
      if (presets.isEmpty) {
        return [
          SidebarActionMenuSpec.item(
            value: null,
            icon: Icons.tune,
            label: l10n.workspaceCliPresetsEmptyHint,
            enabled: false,
          ),
        ];
      }
      return [
        for (final preset in presets)
          SidebarActionMenuSpec.item(
            value: preset.id,
            icon: Icons.tune,
            label: preset.name,
            selected: preset.id == _selectedPresetId,
          ),
      ];
    }

    if (teams.isEmpty) {
      return [
        SidebarActionMenuSpec.item(
          value: null,
          icon: Icons.groups_outlined,
          label: l10n.selectTeam,
          enabled: false,
        ),
      ];
    }
    return [
      for (final team in teams)
        SidebarActionMenuSpec.item(
          value: team.id,
          icon: Icons.groups_outlined,
          label: team.name,
          selected: team.id == _selectedTeamId,
        ),
    ];
  }

  List<SidebarActionMenuSpec> _permissionSpecs(AppLocalizations l10n) {
    return [
      SidebarActionMenuSpec.item(
        value: _LandingPermissionMode.defaultPermissions,
        icon: Icons.verified_outlined,
        label: l10n.workspaceChatLandingDefaultPermissions,
        selected: _permissionMode == _LandingPermissionMode.defaultPermissions,
      ),
      SidebarActionMenuSpec.item(
        value: _LandingPermissionMode.fullAccess,
        icon: Icons.lock_open_outlined,
        label: l10n.workspaceChatLandingFullAccessPermissions,
        selected: _permissionMode == _LandingPermissionMode.fullAccess,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.appSpacing;
    final presets = context.watch<CliPresetsCubit>().state.presets;
    final teams = context.watch<LaunchProfileCubit>().state.teams;
    final workspaceLabel = widget.workspace.display.trim().isNotEmpty
        ? widget.workspace.display.trim()
        : widget.workspace.firstFolderPath;

    return ColoredBox(
      color: cs.surface,
      child: SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xl,
              vertical: spacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ComposeCard(
                    controller: _controller,
                    focusNode: _focusNode,
                    hint: l10n.workspaceChatLandingInputHint,
                    isSubmitting: widget.isSubmitting,
                    canSubmit: _canSubmit,
                    onSubmit: _submit,
                    onChanged: (_) => setState(() {}),
                    conversationModeLabel: _conversationModeLabel(l10n),
                    autoChipLabel: _autoChipLabel(
                      l10n,
                      presets: presets,
                      teams: teams,
                    ),
                    permissionChipLabel: _permissionChipLabel(l10n),
                    conversationModeSpecs: _conversationModeSpecs(l10n),
                    autoChipSpecs: _autoChipSpecs(
                      l10n,
                      presets: presets,
                      teams: teams,
                    ),
                    permissionSpecs: _permissionSpecs(l10n),
                    onConversationModeSelected: (value) {
                      if (value is _LandingConversationMode) {
                        _setConversationMode(value);
                      }
                    },
                    onAutoChipSelected: (value) {
                      if (value is! String || value.isEmpty) return;
                      if (_conversationMode ==
                          _LandingConversationMode.simple) {
                        _selectPreset(value);
                      } else {
                        _selectTeam(value);
                      }
                    },
                    onPermissionSelected: (value) {
                      if (value is _LandingPermissionMode) {
                        _setPermissionMode(value);
                      }
                    },
                    skillsLabel: l10n.workspaceChatLandingSkills,
                    connectAppsLabel: l10n.workspaceChatLandingConnectApps,
                  ),
                  SizedBox(height: spacing.xl),
                  _WorkspaceSelectorBar(
                    label: workspaceLabel.isNotEmpty
                        ? workspaceLabel
                        : l10n.workspaceChatLandingSelectWorkspace,
                    hintWhenEmpty: l10n.workspaceChatLandingSelectWorkspace,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared surface, border, and foreground tokens for the landing compose UI.
@immutable
class _LandingPalette {
  _LandingPalette(ColorScheme cs)
    : elevated = cs.workspaceCard,
      chipFill = cs.workspaceInset,
      border = cs.outlineVariant.withValues(alpha: 0.7),
      muted = cs.workspaceMutedText,
      hint = cs.workspaceMutedText.withValues(alpha: 0.72),
      disabled = cs.workspaceMutedText.withValues(alpha: 0.38),
      sendIdle = cs.onSurfaceVariant.withValues(alpha: 0.18),
      sendActive = cs.onSurface,
      sendIcon = cs.surface;

  final Color elevated;
  final Color chipFill;
  final Color border;
  final Color muted;
  final Color hint;
  final Color disabled;
  final Color sendIdle;
  final Color sendActive;
  final Color sendIcon;
}

class _ComposeCard extends StatelessWidget {
  const _ComposeCard({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onSubmit,
    required this.onChanged,
    required this.conversationModeLabel,
    required this.autoChipLabel,
    required this.permissionChipLabel,
    required this.conversationModeSpecs,
    required this.autoChipSpecs,
    required this.permissionSpecs,
    required this.onConversationModeSelected,
    required this.onAutoChipSelected,
    required this.onPermissionSelected,
    required this.skillsLabel,
    required this.connectAppsLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final ValueChanged<String> onChanged;
  final String conversationModeLabel;
  final String autoChipLabel;
  final String permissionChipLabel;
  final List<SidebarActionMenuSpec> conversationModeSpecs;
  final List<SidebarActionMenuSpec> autoChipSpecs;
  final List<SidebarActionMenuSpec> permissionSpecs;
  final ValueChanged<Object?> onConversationModeSelected;
  final ValueChanged<Object?> onAutoChipSelected;
  final ValueChanged<Object?> onPermissionSelected;
  final String skillsLabel;
  final String connectAppsLabel;

  @override
  Widget build(BuildContext context) {
    final palette = _LandingPalette(Theme.of(context).colorScheme);
    final spacing = context.appSpacing;
    final styles = AppTextStyles.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: palette.elevated,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: palette.border),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg + spacing.xs,
              spacing.lg,
              spacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 3,
                  maxLines: 6,
                  enabled: !isSubmitting,
                  onChanged: onChanged,
                  style: styles.body.copyWith(
                    color: palette.muted,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: palette.elevated,
                    hintText: hint,
                    hintStyle: styles.body.copyWith(
                      color: palette.hint,
                      height: 1.5,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
                SizedBox(height: spacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _ToolbarMenuChip(
                              palette: palette,
                              icon: Icons.groups_outlined,
                              label: conversationModeLabel,
                              specs: conversationModeSpecs,
                              onSelected: onConversationModeSelected,
                            ),
                            SizedBox(width: spacing.sm),
                            _ToolbarMenuChip(
                              palette: palette,
                              icon: Icons.autorenew,
                              label: autoChipLabel,
                              specs: autoChipSpecs,
                              onSelected: onAutoChipSelected,
                            ),
                            SizedBox(width: spacing.sm),
                            _ToolbarChip(
                              palette: palette,
                              icon: Icons.auto_fix_high_outlined,
                              label: skillsLabel,
                            ),
                            SizedBox(width: spacing.sm),
                            _ToolbarChip(
                              palette: palette,
                              icon: Icons.link,
                              label: connectAppsLabel,
                            ),
                            SizedBox(width: spacing.sm),
                            _ToolbarMenuChip(
                              palette: palette,
                              icon: Icons.verified_outlined,
                              label: permissionChipLabel,
                              specs: permissionSpecs,
                              onSelected: onPermissionSelected,
                            ),
                            SizedBox(width: spacing.sm),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: spacing.sm),
                    _ComposeActionIcon(
                      palette: palette,
                      tooltip: 'Attach',
                      icon: Icons.add,
                      enabled: !isSubmitting,
                      onTap: () {},
                    ),
                    _ComposeActionIcon(
                      palette: palette,
                      tooltip: 'Enhance',
                      icon: Icons.auto_awesome_outlined,
                      enabled: !isSubmitting,
                      onTap: () {},
                    ),
                    _ComposeActionIcon(
                      palette: palette,
                      tooltip: 'Voice',
                      icon: Icons.mic_none_outlined,
                      enabled: !isSubmitting,
                      onTap: () {},
                    ),
                    SizedBox(width: spacing.xs),
                    _SendButton(
                      palette: palette,
                      canSubmit: canSubmit,
                      isSubmitting: isSubmitting,
                      onSubmit: onSubmit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: -20,
          right: 28,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.chipFill,
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(spacing.sm),
              child: Icon(
                Icons.smart_toy_rounded,
                color: palette.muted,
                size: context.appIconSizes.lg,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolbarMenuChip extends StatelessWidget {
  const _ToolbarMenuChip({
    required this.palette,
    required this.icon,
    required this.label,
    required this.specs,
    required this.onSelected,
  });

  final _LandingPalette palette;
  final IconData icon;
  final String label;
  final List<SidebarActionMenuSpec> specs;
  final ValueChanged<Object?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SidebarActionMenuIconAnchor(
      minWidth: 200,
      triggerBuilder: (context, controller) => _ToolbarChip(
        palette: palette,
        icon: icon,
        label: label,
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      buildMenuChildren: (context, controller) =>
          buildSidebarActionMenuChildren(
            context: context,
            specs: specs,
            menuController: controller,
            onSelect: onSelected,
          ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.palette,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final _LandingPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  static const double _minHeight = 36;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final icons = context.appIconSizes;
    final labelStyle = AppTextStyles.of(context).bodySmall.copyWith(
      color: palette.muted,
      fontWeight: FontWeight.w500,
    );

    return Material(
      color: palette.chipFill,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: icons.sm, color: palette.muted),
                SizedBox(width: spacing.xs),
                Text(label, style: labelStyle),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: icons.md,
                  color: palette.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposeActionIcon extends StatelessWidget {
  const _ComposeActionIcon({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final _LandingPalette palette;
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.appIconSizes;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _size,
            height: _size,
            child: Icon(
              icon,
              size: icons.md,
              color: enabled ? palette.muted : palette.disabled,
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.palette,
    required this.canSubmit,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final _LandingPalette palette;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.appIconSizes;
    final active = canSubmit && !isSubmitting;

    return Material(
      color: active ? palette.sendActive : palette.sendIdle,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active
            ? throttledOnPressed('workspace_chat_landing_send', onSubmit)
            : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: _size,
          height: _size,
          child: Center(
            child: isSubmitting
                ? SizedBox(
                    width: icons.sm,
                    height: icons.sm,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.sendIcon,
                    ),
                  )
                : Icon(
                    Icons.arrow_upward_rounded,
                    color: active ? palette.sendIcon : palette.disabled,
                    size: icons.md,
                  ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSelectorBar extends StatelessWidget {
  const _WorkspaceSelectorBar({
    required this.label,
    required this.hintWhenEmpty,
  });

  final String label;
  final String hintWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final palette = _LandingPalette(Theme.of(context).colorScheme);
    final spacing = context.appSpacing;
    final icons = context.appIconSizes;
    final styles = AppTextStyles.of(context);
    final display = label.trim().isEmpty ? hintWhenEmpty : label;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.lg,
        vertical: spacing.md,
      ),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_outlined, size: icons.sm, color: palette.muted),
          SizedBox(width: spacing.sm),
          Flexible(
            child: Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.body.copyWith(
                color: palette.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: icons.md, color: palette.muted),
        ],
      ),
    );
  }
}
