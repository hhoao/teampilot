import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/cli_preset.dart';
import '../../models/config_bundle.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../utils/debounce/debounce.dart';
import '../../widgets/compose/compose_focus_shell.dart';
import '../../widgets/compose/compose_model_preset_chip.dart';
import '../../widgets/compose/compose_permission_chip.dart';
import '../../widgets/compose/compose_trigger_field.dart';
import '../home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../home_workspace/workspace/workspace_chat_landing_voice_bar.dart';
import 'session_launch_error_banner.dart';
import 'session_launch_error_visibility.dart';
import 'session_launch_failure_presenter.dart';

/// Slim continue-compose for session history review (no landing chrome).
class SessionReviewComposeCard extends StatelessWidget {
  const SessionReviewComposeCard({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.canSubmit,
    required this.onSubmit,
    required this.onChanged,
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
    this.isSubmitting = false,
    this.composeEnabled = true,
    this.launchError,
    this.onRemapDeadTarget,
    this.onRetry,
    this.sessionConnectInProgress = false,
    this.onPasteImage,
    this.floating = false,
    this.identityLabel,
    this.identityIcon,
    this.sameCliPresets = const [],
    this.selectedPresetId,
    this.modelPresetLabel,
    this.emptyPresetHintLabel,
    this.onPresetSelected,
    this.dangerouslySkipPermissions = false,
    this.defaultPermissionsLabel,
    this.fullAccessPermissionsLabel,
    this.onPermissionSelected,
    this.teamSettingsTooltip,
    this.onTeamSettings,
    this.showTeamSettingsAttention = false,
    this.showStop = false,
    this.onStop,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final ValueChanged<String> onChanged;
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
  final bool isSubmitting;

  /// When false, field and toolbar actions are locked (e.g. permission wait).
  final bool composeEnabled;
  final String? launchError;
  final VoidCallback? onRemapDeadTarget;
  final VoidCallback? onRetry;
  final bool sessionConnectInProgress;
  final Future<bool> Function()? onPasteImage;
  final bool floating;

  /// Read-only expert / team identity (no menu).
  final String? identityLabel;
  final IconData? identityIcon;

  final List<CliPreset> sameCliPresets;
  final String? selectedPresetId;
  final String? modelPresetLabel;
  final String? emptyPresetHintLabel;
  final ValueChanged<String>? onPresetSelected;

  final bool dangerouslySkipPermissions;
  final String? defaultPermissionsLabel;
  final String? fullAccessPermissionsLabel;
  final ValueChanged<bool>? onPermissionSelected;

  final String? teamSettingsTooltip;
  final VoidCallback? onTeamSettings;
  final bool showTeamSettingsAttention;

  /// When true, the send button is replaced with a stop-generating control.
  final bool showStop;
  final VoidCallback? onStop;

  bool get _composeActionsEnabled =>
      composeEnabled && !isSubmitting && !isEnhancing;

  bool get _showContinueToolbar =>
      identityLabel != null ||
      onPresetSelected != null ||
      onPermissionSelected != null ||
      onTeamSettings != null;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.tpSpacing;
    final failure = presentSessionLaunchFailure(launchError);

    return ComposeFocusShell(
      focusNode: focusNode,
      floating: floating,
      color: palette.elevated,
      borderColor: palette.border,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.lg,
          spacing.lg,
          spacing.lg,
          spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (shouldShowSessionLaunchErrorBanner(
                  launchError: launchError,
                  sessionConnectInProgress: sessionConnectInProgress,
                ) &&
                failure != null) ...[
              SessionLaunchErrorBanner(
                view: failure,
                onRetry: onRetry,
                onRemapDeadTarget: onRemapDeadTarget,
                isRetrying: sessionConnectInProgress,
              ),
              SizedBox(height: spacing.md),
            ],
            ComposeTriggerField(
              controller: controller,
              focusNode: focusNode,
              hint: hint,
              enabled: composeEnabled && !isSubmitting,
              onChanged: onChanged,
              onSubmit: onSubmit,
              canSubmit: () => composeEnabled && canSubmit,
              workspaceRoot: workspaceRoot,
              skills: skills,
              plugins: plugins,
              slashBundle: slashBundle,
              mutedColor: palette.muted,
              hintColor: palette.hint,
              onPasteImage: onPasteImage,
            ),
            SizedBox(height: spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: isVoiceListening
                  ? _voiceRecordingActions(
                      context: context,
                      palette: palette,
                      spacing: spacing,
                    )
                  : _idleActions(
                      context: context,
                      palette: palette,
                      spacing: spacing,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _idleActions({
    required BuildContext context,
    required WorkspaceChatLandingPalette palette,
    required TpSpacing spacing,
  }) {
    return [
      if (_showContinueToolbar)
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (identityLabel != null) ...[
                  _ContinueIdentityChip(
                    palette: palette,
                    icon: identityIcon ?? Icons.psychology_outlined,
                    label: identityLabel!,
                  ),
                  SizedBox(width: spacing.sm),
                ],
                if (onPresetSelected != null &&
                    modelPresetLabel != null &&
                    emptyPresetHintLabel != null) ...[
                  ComposeModelPresetChip(
                    palette: palette,
                    sameCliPresets: sameCliPresets,
                    selectedPresetId: selectedPresetId,
                    label: modelPresetLabel!,
                    emptyHintLabel: emptyPresetHintLabel!,
                    onPresetSelected: onPresetSelected!,
                  ),
                  SizedBox(width: spacing.sm),
                ],
                if (onPermissionSelected != null &&
                    defaultPermissionsLabel != null &&
                    fullAccessPermissionsLabel != null) ...[
                  ComposePermissionChip(
                    palette: palette,
                    dangerouslySkipPermissions: dangerouslySkipPermissions,
                    defaultLabel: defaultPermissionsLabel!,
                    fullAccessLabel: fullAccessPermissionsLabel!,
                    onSelected: onPermissionSelected!,
                  ),
                  SizedBox(width: spacing.sm),
                ],
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
              ],
            ),
          ),
        )
      else
        const Spacer(),
      if (_showContinueToolbar) SizedBox(width: spacing.sm),
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
        enabled: _composeActionsEnabled && controller.text.trim().isNotEmpty,
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
      _composePrimaryAction(context: context, palette: palette),
    ];
  }

  List<Widget> _voiceRecordingActions({
    required BuildContext context,
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
        enabled: _composeActionsEnabled && controller.text.trim().isNotEmpty,
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
      _composePrimaryAction(context: context, palette: palette),
    ];
  }

  Widget _composePrimaryAction({
    required BuildContext context,
    required WorkspaceChatLandingPalette palette,
  }) {
    if (showStop && onStop != null) {
      return _StopButton(
        palette: palette,
        tooltip: context.l10n.sessionHistoryComposeStop,
        onStop: onStop!,
      );
    }
    return _SendButton(
      palette: palette,
      canSubmit: composeEnabled && canSubmit,
      isSubmitting: isSubmitting,
      onSubmit: onSubmit,
    );
  }
}

/// Read-only stadium chip (no chevron / menu).
class _ContinueIdentityChip extends StatelessWidget {
  const _ContinueIdentityChip({
    required this.palette,
    required this.icon,
    required this.label,
  });

  final WorkspaceChatLandingPalette palette;
  final IconData icon;
  final String label;

  static const double minHeight = 36;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    final icons = context.tpIconSizes;
    final labelStyle = TpTextStyles.of(context).smColored(palette.muted);

    return Material(
      color: palette.chipFill,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
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
            ],
          ),
        ),
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
                        border: Border.all(color: palette.chipFill, width: 1.5),
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

class _StopButton extends StatelessWidget {
  const _StopButton({
    required this.palette,
    required this.tooltip,
    required this.onStop,
  });

  final WorkspaceChatLandingPalette palette;
  final String tooltip;
  final VoidCallback onStop;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: palette.sendActive,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: throttledOnPressed('session_review_compose_stop', onStop),
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: _size,
              height: _size,
              child: Center(
                child: Icon(
                  Icons.stop_rounded,
                  color: palette.sendIcon,
                  size: icons.md,
                ),
              ),
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

  final WorkspaceChatLandingPalette palette;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;
    final active = canSubmit && !isSubmitting;

    return Material(
      color: active ? palette.sendActive : palette.sendIdle,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active
            ? throttledOnPressed('session_review_compose_send', onSubmit)
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
                : Icon(icon, size: icons.md, color: color),
          ),
        ),
      ),
    );
  }
}
