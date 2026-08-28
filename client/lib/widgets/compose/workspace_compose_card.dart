import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/config_bundle.dart';
import '../../models/plugin.dart';
import '../../models/skill.dart';
import '../../pages/chat/session_launch_error_banner.dart';
import '../../pages/chat/session_launch_error_visibility.dart';
import '../../pages/chat/session_launch_failure_presenter.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing_palette.dart';
import '../../pages/home_workspace/workspace/workspace_chat_landing_voice_bar.dart';
import '../../services/workspace_dnd/workspace_drop_target.dart';
import '../../services/cli/registry/capabilities/native_command_capability.dart';
import '../../services/cli/registry/capabilities/skill_capability.dart';
import '../../services/compose/compose_at_file_refs.dart';
import '../../services/compose/compose_clip.dart';
import '../../utils/debounce/debounce.dart';
import 'compose_at_file_chip_row.dart';
import 'compose_chrome.dart';
import 'compose_file_drop_region.dart';
import 'compose_focus_shell.dart';
import 'compose_menu_chip.dart';
import 'compose_paste_clip_bar.dart';
import 'compose_paste_editor_dialog.dart';
import 'compose_permission_chip.dart';
import 'compose_trigger_field.dart';

/// Frames to wait before mounting the [ComposeTriggerField].
///
/// Keeps first-open LAYOUT off [RenderEditable] (test56 ~442 ms). Do not use
/// [TpDeferredMountShell.awaitIdle] here: a background agent PTY can keep the
/// scheduler non-idle after History/Terminal unmount, leaving the placeholder
/// forever (clicks cannot focus). Tests mount immediately via
/// [TpDeferredMountShell].
const kWorkspaceComposeFieldDelayFrames = 2;

/// Unified compose card for both landing (unbound) and session-continue
/// (bound) chrome. See [ComposeChrome] for the toolbar sealed variants.
class WorkspaceComposeCard extends StatelessWidget {
  const WorkspaceComposeCard({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.canSubmit,
    required this.onSubmit,
    required this.onChanged,
    required this.chrome,
    required this.dropTarget,
    required this.attachTooltip,
    required this.voiceTooltip,
    required this.voiceCancelTooltip,
    required this.voiceStopTooltip,
    required this.isVoiceListening,
    required this.voiceElapsed,
    required this.voiceSoundLevel,
    required this.onAttach,
    required this.onVoice,
    required this.onVoiceCancel,
    required this.onVoiceStop,
    required this.workspaceRoot,
    required this.skills,
    required this.plugins,
    required this.slashBundle,
    this.skillSyntax,
    this.nativeCommands = const [],
    this.isSubmitting = false,
    this.onPasteImage,
    this.submitBlockedTooltip,
    this.deferFieldMount = false,
    this.onOpenAtFile,
    this.clip,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final ValueChanged<String> onChanged;
  final ComposeChrome chrome;
  final WorkspaceDropTarget dropTarget;
  final String attachTooltip;
  final String voiceTooltip;
  final String voiceCancelTooltip;
  final String voiceStopTooltip;
  final bool isVoiceListening;
  final Duration voiceElapsed;
  final double voiceSoundLevel;
  final VoidCallback onAttach;
  final VoidCallback onVoice;
  final VoidCallback onVoiceCancel;
  final VoidCallback onVoiceStop;
  final String workspaceRoot;
  final List<Skill> skills;
  final List<Plugin> plugins;
  final ConfigBundle slashBundle;
  final SkillCapability? skillSyntax;
  final List<NativeCommand> nativeCommands;
  final bool isSubmitting;
  final Future<bool> Function()? onPasteImage;
  final String? submitBlockedTooltip;
  final bool deferFieldMount;
  final ValueChanged<String>? onOpenAtFile;

  /// Optional paste-collapse buffer. When collapsed, a badge bar is rendered
  /// above the field; the at-file refs scan and the actions-row hasText account
  /// for the block. Parents pass launch-gate [canSubmit]; emptiness is local.
  final ComposeClip? clip;

  bool get _composeEnabled => switch (chrome) {
    BoundComposeChrome(:final composeEnabled) => composeEnabled,
    UnboundComposeChrome() => true,
  };

  bool get _floating => switch (chrome) {
    BoundComposeChrome(:final floating) => floating,
    UnboundComposeChrome() => false,
  };

  bool get _composeActionsEnabled => _composeEnabled && !isSubmitting;

  bool get _effectiveCanSubmit {
    if (!_composeEnabled || !canSubmit) return false;
    return controller.text.trim().isNotEmpty || (clip?.collapsed ?? false);
  }

  String get _sendThrottleKey => switch (chrome) {
    UnboundComposeChrome() => 'workspace_chat_landing_send',
    BoundComposeChrome() => 'session_review_compose_send',
  };

  @override
  Widget build(BuildContext context) {
    final palette = WorkspaceChatLandingPalette(Theme.of(context).colorScheme);
    final spacing = context.tpSpacing;
    final chrome = this.chrome;

    Widget field = ComposeTriggerField(
      controller: controller,
      focusNode: focusNode,
      hint: hint,
      enabled: _composeEnabled && !isSubmitting,
      onChanged: onChanged,
      onSubmit: onSubmit,
      canSubmit: () => _effectiveCanSubmit,
      workspaceRoot: workspaceRoot,
      skills: skills,
      plugins: plugins,
      slashBundle: slashBundle,
      skillSyntax: skillSyntax,
      nativeCommands: nativeCommands,
      mutedColor: palette.muted,
      hintColor: palette.hint,
      onPasteImage: onPasteImage,
      clip: clip,
    );

    if (deferFieldMount) {
      field = TpDeferredMountShell(
        delayFrames: kWorkspaceComposeFieldDelayFrames,
        placeholder: _ComposeFieldMountPlaceholder(
          hint: hint,
          hintColor: palette.hint,
          mutedColor: palette.muted,
        ),
        child: field,
      );
    }

    final shell = ComposeFocusShell(
      focusNode: focusNode,
      floating: _floating,
      color: palette.elevated,
      borderColor: palette.border,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          spacing.lg,
          chrome is UnboundComposeChrome ? spacing.lg + spacing.xs : spacing.lg,
          spacing.lg,
          spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (chrome is BoundComposeChrome)
              ..._launchErrorBanner(context, chrome, spacing),
            if (clip != null)
              ListenableBuilder(
                listenable: clip!,
                builder: (context, _) {
                  if (!clip!.collapsed) return const SizedBox.shrink();
                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.md),
                    child: ComposePasteClipBar(
                      clip: clip!,
                      onEdit: () =>
                          unawaited(showComposePasteEditor(context, clip!)),
                      onRemove: clip!.clear,
                    ),
                  );
                },
              ),
            ListenableBuilder(
              listenable: Listenable.merge([
                controller,
                if (clip != null) clip!,
              ]),
              builder: (context, _) {
                final refs = parseComposeAtFileRefs(
                  clip?.composeMessage(controller.text) ?? controller.text,
                  workspaceRoot: workspaceRoot,
                );
                if (refs.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(bottom: spacing.md),
                  child: ComposeAtFileChipRow(
                    refs: refs,
                    onOpen: onOpenAtFile ?? (_) {},
                  ),
                );
              },
            ),
            field,
            SizedBox(height: spacing.md),
            ListenableBuilder(
              listenable: Listenable.merge([
                controller,
                if (clip != null) clip!,
              ]),
              builder: (context, _) {
                final hasText =
                    controller.text.trim().isNotEmpty ||
                    (clip?.collapsed ?? false);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: isVoiceListening
                      ? _voiceRecordingActions(
                          context: context,
                          palette: palette,
                          spacing: spacing,
                          hasText: hasText,
                        )
                      : _idleActions(
                          context,
                          chrome: chrome,
                          palette: palette,
                          spacing: spacing,
                          hasText: hasText,
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );

    final content = chrome is UnboundComposeChrome
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              shell,
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
          )
        : shell;

    return ComposeFileDropRegion(target: dropTarget, child: content);
  }

  List<Widget> _launchErrorBanner(
    BuildContext context,
    BoundComposeChrome chrome,
    TpSpacing spacing,
  ) {
    final failure = presentSessionLaunchFailure(chrome.launchError);
    if (!shouldShowSessionLaunchErrorBanner(
          launchError: chrome.launchError,
          sessionConnectInProgress: chrome.sessionConnectInProgress,
        ) ||
        failure == null) {
      return const [];
    }

    return [
      SessionLaunchErrorBanner(
        view: failure,
        onRetry: chrome.onRetry,
        onRemapDeadTarget: chrome.onRemapDeadTarget,
        isRetrying: chrome.sessionConnectInProgress,
      ),
      SizedBox(height: spacing.md),
    ];
  }

  Widget? _trailingComposeAction({
    required BuildContext context,
    required WorkspaceChatLandingPalette palette,
    required bool hasText,
    bool hideVoiceWhenEmpty = false,
  }) {
    final chrome = this.chrome;
    if (chrome is BoundComposeChrome &&
        chrome.showStop &&
        chrome.onStop != null) {
      return _StopButton(
        palette: palette,
        tooltip: context.l10n.sessionHistoryComposeStop,
        onStop: chrome.onStop!,
      );
    }
    if (hasText) {
      return _SendButton(
        palette: palette,
        canSubmit: _effectiveCanSubmit,
        isSubmitting: isSubmitting,
        onSubmit: onSubmit,
        throttleKey: _sendThrottleKey,
        blockedTooltip: submitBlockedTooltip,
      );
    }
    if (hideVoiceWhenEmpty) return null;
    return _VoicePrimaryButton(
      palette: palette,
      tooltip: voiceTooltip,
      enabled: _composeActionsEnabled,
      onTap: onVoice,
    );
  }

  List<Widget> _unboundLeadingChips(
    UnboundComposeChrome chrome,
    WorkspaceChatLandingPalette palette,
    TpSpacing spacing,
  ) {
    return [
      ComposeMenuChip(
        palette: palette,
        icon: Icons.groups_outlined,
        label: chrome.conversationModeLabel,
        specs: chrome.conversationModeSpecs,
        onSelected: chrome.onConversationModeSelected,
      ),
      SizedBox(width: spacing.sm),
      ComposeMenuChip(
        palette: palette,
        icon: Icons.autorenew,
        leading: chrome.autoChipLeading,
        label: chrome.autoChipLabel,
        specs: chrome.autoChipSpecs,
        onSelected: chrome.onAutoChipSelected,
      ),
      if (chrome.onTeamSettings != null) ...[
        SizedBox(width: spacing.xs),
        _TeamSettingsButton(
          palette: palette,
          tooltip: chrome.teamSettingsTooltip ?? '',
          showAttention: chrome.showTeamSettingsAttention,
          enabled: _composeActionsEnabled,
          onTap: chrome.onTeamSettings!,
        ),
      ],
      if (chrome.expertChipLabel != null &&
          chrome.onExpertChipSelected != null) ...[
        SizedBox(width: spacing.sm),
        ComposeMenuChip(
          palette: palette,
          icon: Icons.psychology_outlined,
          label: chrome.expertChipLabel!,
          specs: chrome.expertChipSpecs,
          onSelected: chrome.onExpertChipSelected!,
        ),
      ],
      SizedBox(width: spacing.sm),
      ComposePermissionChip(
        palette: palette,
        launchSecurityPolicy: chrome.launchSecurityPolicy,
        defaultLabel: chrome.defaultPermissionsLabel,
        fullAccessLabel: chrome.fullAccessPermissionsLabel,
        askReadOnlyLabel: chrome.askReadOnlyPermissionsLabel,
        autoApproveWorkspaceWriteLabel:
            chrome.autoApproveWorkspaceWritePermissionsLabel,
        customLabel: chrome.customPermissionsLabel,
        onSelected: chrome.onPermissionSelected,
      ),
      SizedBox(width: spacing.sm),
    ];
  }

  List<Widget> _boundLeadingChips(
    BoundComposeChrome chrome,
    WorkspaceChatLandingPalette palette,
    TpSpacing spacing,
  ) {
    return [
      if (chrome.identityLabel != null) ...[
        _ContinueIdentityChip(
          palette: palette,
          icon: chrome.identityIcon ?? Icons.psychology_outlined,
          label: chrome.identityLabel!,
        ),
        SizedBox(width: spacing.sm),
      ],
      if (chrome.onModelCascadeSelected != null &&
          chrome.modelCascadeSpecs != null &&
          chrome.modelPresetLabel != null) ...[
        ComposeMenuChip(
          palette: palette,
          icon: Icons.terminal_outlined,
          leading: chrome.modelChipLeading,
          label: chrome.modelPresetLabel!,
          minWidth: 200,
          specs: chrome.modelCascadeSpecs!,
          onSelected: chrome.onModelCascadeSelected!,
        ),
        SizedBox(width: spacing.sm),
      ],
      if (chrome.onPermissionSelected != null &&
          chrome.defaultPermissionsLabel != null &&
          chrome.fullAccessPermissionsLabel != null) ...[
        ComposePermissionChip(
          palette: palette,
          launchSecurityPolicy: chrome.launchSecurityPolicy,
          defaultLabel: chrome.defaultPermissionsLabel!,
          fullAccessLabel: chrome.fullAccessPermissionsLabel!,
          askReadOnlyLabel: chrome.askReadOnlyPermissionsLabel,
          autoApproveWorkspaceWriteLabel:
              chrome.autoApproveWorkspaceWritePermissionsLabel,
          customLabel: chrome.customPermissionsLabel,
          onSelected: chrome.onPermissionSelected!,
        ),
        SizedBox(width: spacing.sm),
      ],
      if (chrome.onTeamSettings != null) ...[
        SizedBox(width: spacing.xs),
        _TeamSettingsButton(
          palette: palette,
          tooltip: chrome.teamSettingsTooltip ?? '',
          showAttention: chrome.showTeamSettingsAttention,
          enabled: _composeActionsEnabled,
          onTap: chrome.onTeamSettings!,
        ),
      ],
    ];
  }

  List<Widget> _idleActions(
    BuildContext context, {
    required ComposeChrome chrome,
    required WorkspaceChatLandingPalette palette,
    required TpSpacing spacing,
    required bool hasText,
  }) {
    final leading = switch (chrome) {
      UnboundComposeChrome c => _unboundLeadingChips(c, palette, spacing),
      BoundComposeChrome c when _hasBoundToolbar(c) => _boundLeadingChips(
        c,
        palette,
        spacing,
      ),
      BoundComposeChrome() => const <Widget>[],
    };
    final hasLeading = leading.isNotEmpty;

    return [
      if (hasLeading)
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: leading),
          ),
        )
      else
        const Spacer(),
      if (hasLeading) SizedBox(width: spacing.sm),
      _ComposeActionIcon(
        palette: palette,
        tooltip: attachTooltip,
        icon: Icons.add,
        enabled: _composeActionsEnabled,
        onTap: onAttach,
      ),
      SizedBox(width: spacing.xs),
      _trailingComposeAction(
        context: context,
        palette: palette,
        hasText: hasText,
      )!,
    ];
  }

  bool _hasBoundToolbar(BoundComposeChrome chrome) =>
      chrome.identityLabel != null ||
      chrome.onModelCascadeSelected != null ||
      chrome.onPermissionSelected != null ||
      chrome.onTeamSettings != null;

  List<Widget> _voiceRecordingActions({
    required BuildContext context,
    required WorkspaceChatLandingPalette palette,
    required TpSpacing spacing,
    required bool hasText,
  }) {
    return [
      _ComposeActionIcon(
        palette: palette,
        tooltip: attachTooltip,
        icon: Icons.add,
        enabled: _composeActionsEnabled,
        onTap: onAttach,
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
      if (_trailingComposeAction(
            context: context,
            palette: palette,
            hasText: hasText,
            hideVoiceWhenEmpty: true,
          )
          case final action?) ...[
        SizedBox(width: spacing.xs),
        action,
      ],
    ];
  }
}

/// Reserves the same min height as [ComposeTriggerField]'s textarea shell.
class _ComposeFieldMountPlaceholder extends StatelessWidget {
  const _ComposeFieldMountPlaceholder({
    required this.hint,
    required this.hintColor,
    required this.mutedColor,
  });

  final String hint;
  final Color hintColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final textStyle = styles.mdColored(mutedColor);
    final lineHeight = (textStyle.fontSize ?? 14) * (textStyle.height ?? 1.35);
    final minH = lineHeight * 3;

    return SizedBox(
      height: minH,
      width: double.infinity,
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: styles.mdColored(hintColor),
        ),
      ),
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
      child: TpHover(
        shape: TpPressableShape.circle,
        width: _size,
        height: _size,
        backgroundColor: palette.chipFill,
        border: Border.all(color: palette.border),
        enabled: enabled,
        onTap: enabled ? onTap : null,
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
    );
  }
}

class _StopButton extends StatefulWidget {
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
  State<_StopButton> createState() => _StopButtonState();
}

class _StopButtonState extends State<_StopButton> {
  var _stopping = false;

  void _handleStop() {
    if (_stopping) return;
    _stopping = true;
    widget.onStop();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: TpHover(
          shape: TpPressableShape.circle,
          width: _StopButton._size,
          height: _StopButton._size,
          backgroundColor: widget.palette.sendActive,
          enabled: !_stopping,
          onTap: _stopping
              ? null
              : throttledOnPressed('session_review_compose_stop', _handleStop),
          child: Center(
            child: Icon(
              Icons.stop_rounded,
              color: widget.palette.sendIcon,
              size: icons.md,
            ),
          ),
        ),
      ),
    );
  }
}

class _VoicePrimaryButton extends StatelessWidget {
  const _VoicePrimaryButton({
    required this.palette,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final WorkspaceChatLandingPalette palette;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;
    final color = enabled ? palette.muted : palette.disabled;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: TpHover(
          shape: TpPressableShape.circle,
          width: _size,
          height: _size,
          backgroundColor: palette.sendIdle,
          enabled: enabled,
          onTap: enabled ? onTap : null,
          child: Center(
            child: Icon(Icons.mic_none_outlined, color: color, size: icons.md),
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
    required this.throttleKey,
    this.blockedTooltip,
  });

  final WorkspaceChatLandingPalette palette;
  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final String throttleKey;
  final String? blockedTooltip;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;
    final active = canSubmit && !isSubmitting;
    final tooltip = blockedTooltip?.trim();

    final button = TpHover(
      shape: TpPressableShape.circle,
      width: _size,
      height: _size,
      backgroundColor: active ? palette.sendActive : palette.sendIdle,
      enabled: active,
      onTap: active ? throttledOnPressed(throttleKey, onSubmit) : null,
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
  });

  final WorkspaceChatLandingPalette palette;
  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final icons = context.tpIconSizes;
    final color = !enabled ? palette.disabled : palette.muted;

    return Tooltip(
      message: tooltip,
      child: TpHover(
        shape: TpPressableShape.circle,
        width: _size,
        height: _size,
        backgroundColor: Colors.transparent,
        enabled: enabled,
        onTap: enabled ? onTap : null,
        child: Center(
          child: Icon(icon, size: icons.md, color: color),
        ),
      ),
    );
  }
}
