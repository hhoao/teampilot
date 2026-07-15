import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../models/plugin.dart';
import '../../../models/skill.dart';
import '../../../models/config_bundle.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../services/workspace_dnd/workspace_drop_target.dart';
import '../../../widgets/compose/compose_focus_shell.dart';
import '../../../widgets/compose/compose_menu_chip.dart';
import '../../../widgets/compose/compose_permission_chip.dart';
import '../../../widgets/compose/compose_trigger_field.dart';
import '../../../widgets/deferred_mount_shell.dart';
import '../../../widgets/menu/sidebar_action_menu.dart';
import '../../../widgets/workspace_dnd/external_file_drop_region.dart';
import '../../../widgets/workspace_dnd/workspace_file_drop_region.dart';
import 'workspace_chat_landing_palette.dart';
import 'workspace_chat_landing_voice_bar.dart';

/// Compose input card for [WorkspaceChatLanding].
class WorkspaceChatLandingComposeCard extends StatelessWidget {
  const WorkspaceChatLandingComposeCard({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onSubmit,
    required this.onChanged,
    required this.conversationModeLabel,
    required this.autoChipLabel,
    required this.dangerouslySkipPermissions,
    required this.defaultPermissionsLabel,
    required this.fullAccessPermissionsLabel,
    required this.conversationModeSpecs,
    required this.autoChipSpecs,
    required this.onConversationModeSelected,
    required this.onAutoChipSelected,
    required this.onPermissionSelected,
    this.expertChipLabel,
    this.expertChipSpecs = const [],
    this.onExpertChipSelected,
    required this.attachTooltip,
    required this.enhanceTooltip,
    required this.voiceTooltip,
    required this.voiceCancelTooltip,
    required this.voiceStopTooltip,
    required this.isEnhancing,
    required this.isVoiceListening,
    required this.voiceElapsed,
    required this.voiceSoundLevel,
    required this.onAttach,
    required this.onEnhance,
    required this.onVoice,
    required this.onVoiceCancel,
    required this.onVoiceStop,
    required this.workspaceRoot,
    required this.skills,
    required this.plugins,
    required this.slashBundle,
    this.teamSettingsTooltip,
    this.onTeamSettings,
    this.showTeamSettingsAttention = false,
    this.submitBlockedTooltip,
    this.dropTarget,
    this.onPasteImage,
    super.key,
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
  final bool dangerouslySkipPermissions;
  final String defaultPermissionsLabel;
  final String fullAccessPermissionsLabel;
  final List<SidebarActionMenuSpec> conversationModeSpecs;
  final List<SidebarActionMenuSpec> autoChipSpecs;
  final ValueChanged<Object?> onConversationModeSelected;
  final ValueChanged<Object?> onAutoChipSelected;
  final ValueChanged<bool> onPermissionSelected;
  final String? expertChipLabel;
  final List<SidebarActionMenuSpec> expertChipSpecs;
  final ValueChanged<Object?>? onExpertChipSelected;
  final String attachTooltip;
  final String enhanceTooltip;
  final String voiceTooltip;
  final String voiceCancelTooltip;
  final String voiceStopTooltip;
  final bool isEnhancing;
  final bool isVoiceListening;
  final Duration voiceElapsed;
  final double voiceSoundLevel;
  final VoidCallback onAttach;
  final VoidCallback onEnhance;
  final VoidCallback onVoice;
  final VoidCallback onVoiceCancel;
  final VoidCallback onVoiceStop;
  final String workspaceRoot;
  final List<Skill> skills;
  final List<Plugin> plugins;
  final ConfigBundle slashBundle;
  final String? teamSettingsTooltip;
  final VoidCallback? onTeamSettings;
  final bool showTeamSettingsAttention;
  final String? submitBlockedTooltip;
  final WorkspaceDropTarget? dropTarget;
  final Future<bool> Function()? onPasteImage;

  bool get _composeActionsEnabled => !isSubmitting && !isEnhancing;

  List<Widget> _idleActions(
    BuildContext context, {
    required WorkspaceChatLandingPalette palette,
    required TpSpacing spacing,
  }) {
    return [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ComposeMenuChip(
                palette: palette,
                icon: Icons.groups_outlined,
                label: conversationModeLabel,
                specs: conversationModeSpecs,
                onSelected: onConversationModeSelected,
              ),
              SizedBox(width: spacing.sm),
              ComposeMenuChip(
                palette: palette,
                icon: Icons.autorenew,
                label: autoChipLabel,
                specs: autoChipSpecs,
                onSelected: onAutoChipSelected,
              ),
              if (onTeamSettings != null) ...[
                SizedBox(width: spacing.xs),
                _TeamSettingsButton(
                  palette: palette,
                  tooltip: teamSettingsTooltip ?? '',
                  showAttention: showTeamSettingsAttention,
                  enabled: _composeActionsEnabled,
                  onTap: onTeamSettings!,
                ),
              ],
              if (expertChipLabel != null &&
                  onExpertChipSelected != null) ...[
                SizedBox(width: spacing.sm),
                ComposeMenuChip(
                  palette: palette,
                  icon: Icons.psychology_outlined,
                  label: expertChipLabel!,
                  specs: expertChipSpecs,
                  onSelected: onExpertChipSelected!,
                ),
              ],
              SizedBox(width: spacing.sm),
              ComposePermissionChip(
                palette: palette,
                dangerouslySkipPermissions: dangerouslySkipPermissions,
                defaultLabel: defaultPermissionsLabel,
                fullAccessLabel: fullAccessPermissionsLabel,
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
        tooltip: attachTooltip,
        icon: Icons.add,
        enabled: _composeActionsEnabled,
        onTap: onAttach,
      ),
      _ComposeActionIcon(
        palette: palette,
        tooltip: enhanceTooltip,
        icon: Icons.auto_awesome_outlined,
        enabled:
            _composeActionsEnabled && controller.text.trim().isNotEmpty,
        isLoading: isEnhancing,
        onTap: onEnhance,
      ),
      _ComposeActionIcon(
        palette: palette,
        tooltip: voiceTooltip,
        icon: Icons.mic_none_outlined,
        enabled: _composeActionsEnabled,
        onTap: onVoice,
      ),
      SizedBox(width: spacing.xs),
      _SendButton(
        palette: palette,
        canSubmit: canSubmit,
        isSubmitting: isSubmitting,
        onSubmit: onSubmit,
        blockedTooltip: submitBlockedTooltip,
      ),
    ];
  }

  List<Widget> _voiceRecordingActions(
    BuildContext context, {
    required WorkspaceChatLandingPalette palette,
    required TpSpacing spacing,
  }) {
    return [
      _ComposeActionIcon(
        palette: palette,
        tooltip: attachTooltip,
        icon: Icons.add,
        enabled: _composeActionsEnabled,
        onTap: onAttach,
      ),
      _ComposeActionIcon(
        palette: palette,
        tooltip: enhanceTooltip,
        icon: Icons.auto_awesome_outlined,
        enabled:
            _composeActionsEnabled && controller.text.trim().isNotEmpty,
        isLoading: isEnhancing,
        onTap: onEnhance,
      ),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: ComposeVoiceRecordingStatus(
            palette: palette,
            elapsed: voiceElapsed,
            soundLevel: voiceSoundLevel,
            cancelTooltip: voiceCancelTooltip,
            stopTooltip: voiceStopTooltip,
            onCancel: onVoiceCancel,
            onStop: onVoiceStop,
          ),
        ),
      ),
      SizedBox(width: spacing.xs),
      _SendButton(
        palette: palette,
        canSubmit: canSubmit,
        isSubmitting: isSubmitting,
        onSubmit: onSubmit,
        blockedTooltip: submitBlockedTooltip,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.tpSpacing;

    return _wrapDropTarget(
      Stack(
        clipBehavior: Clip.none,
        children: [
          ComposeFocusShell(
            focusNode: focusNode,
            color: palette.elevated,
            borderColor: palette.border,
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
                  // Defer EditableText past the first workspace paint so
                  // Clipboard/LiveText/ProcessText probes are off the open path.
                  DeferredMountShell(
                    delayFrames: 2,
                    placeholder: _ComposeFieldPlaceholder(
                      hint: hint,
                      hintColor: palette.hint,
                    ),
                    child: ComposeTriggerField(
                      controller: controller,
                      focusNode: focusNode,
                      hint: hint,
                      enabled: !isSubmitting,
                      onChanged: onChanged,
                      onSubmit: onSubmit,
                      canSubmit: () => canSubmit,
                      workspaceRoot: workspaceRoot,
                      skills: skills,
                      plugins: plugins,
                      slashBundle: slashBundle,
                      mutedColor: palette.muted,
                      hintColor: palette.hint,
                      onPasteImage: onPasteImage,
                    ),
                  ),
                  SizedBox(height: spacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: isVoiceListening
                        ? _voiceRecordingActions(
                            context,
                            palette: palette,
                            spacing: spacing,
                          )
                        : _idleActions(
                            context,
                            palette: palette,
                            spacing: spacing,
                          ),
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
                  size: context.tpIconSizes.lg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapDropTarget(Widget child) {
    final target = dropTarget;
    if (target == null) return child;
    return ExternalFileDropRegion(
      target: target,
      child: WorkspaceFileDropRegion(
        target: target,
        child: child,
      ),
    );
  }
}

class _TeamSettingsButton extends StatelessWidget {
  const _TeamSettingsButton({
    required this.palette,
    required this.tooltip,
    required this.showAttention,
    required this.enabled,
    required this.onTap,
  });

  final WorkspaceChatLandingPalette palette;
  final String tooltip;
  final bool showAttention;
  final bool enabled;
  final VoidCallback onTap;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;
    final color = enabled ? palette.muted : palette.disabled;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: palette.chipFill,
        shape: CircleBorder(side: BorderSide(color: palette.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _size,
            height: _size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.settings_outlined, size: icons.md, color: color),
                if (showAttention)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.chipFill,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
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
    this.blockedTooltip,
  });

  final WorkspaceChatLandingPalette palette;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final String? blockedTooltip;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;
    final active = canSubmit && !isSubmitting;
    final tooltip = blockedTooltip?.trim();

    final button = Material(
      color: active ? palette.sendActive : palette.sendIdle,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active
            ? throttledOnPressed('workspace_chat_landing_send', onSubmit)
            : tooltip != null && tooltip.isNotEmpty
            ? () {}
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

    if (tooltip == null || tooltip.isEmpty || active) return button;

    return Tooltip(message: tooltip, child: button);
  }
}

class _ComposeActionIcon extends StatelessWidget {
  const _ComposeActionIcon({
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.isLoading = false,
  });

  final WorkspaceChatLandingPalette palette;
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool isLoading;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;
    final interactive = enabled && !isLoading;
    final color = !enabled ? palette.disabled : palette.muted;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: interactive ? onTap : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _size,
            height: _size,
            child: isLoading
                ? Center(
                    child: SizedBox(
                      width: icons.sm,
                      height: icons.sm,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.muted,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    size: icons.md,
                    color: color,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Non-interactive stand-in matching ~3-line compose field height.
class _ComposeFieldPlaceholder extends StatelessWidget {
  const _ComposeFieldPlaceholder({
    required this.hint,
    required this.hintColor,
  });

  final String hint;
  final Color hintColor;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final hintStyle = styles.mdColored(hintColor);
    final lineHeight =
        (hintStyle.fontSize ?? 14) * (hintStyle.height ?? 1.35);
    return SizedBox(
      width: double.infinity,
      // Matches ComposeTriggerField / TpTextareaShell min (~3 lines).
      height: lineHeight * 3,
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(hint, style: hintStyle),
      ),
    );
  }
}
