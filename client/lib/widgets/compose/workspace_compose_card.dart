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
import '../../services/compose/compose_at_file_refs.dart';
import '../../utils/debounce/debounce.dart';
import 'compose_at_file_chip_row.dart';
import 'compose_chrome.dart';
import 'compose_file_drop_region.dart';
import 'compose_focus_shell.dart';
import 'compose_menu_chip.dart';
import 'compose_model_preset_chip.dart';
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
    this.onPasteImage,
    this.submitBlockedTooltip,
    this.deferFieldMount = false,
    this.onOpenAtFile,
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
  final Future<bool> Function()? onPasteImage;
  final String? submitBlockedTooltip;
  final bool deferFieldMount;
  final ValueChanged<String>? onOpenAtFile;

  bool get _composeEnabled => switch (chrome) {
    BoundComposeChrome(:final composeEnabled) => composeEnabled,
    UnboundComposeChrome() => true,
  };

  bool get _floating => switch (chrome) {
    BoundComposeChrome(:final floating) => floating,
    UnboundComposeChrome() => false,
  };

  bool get _composeActionsEnabled =>
      _composeEnabled && !isSubmitting && !isEnhancing;

  bool get _effectiveCanSubmit => _composeEnabled && canSubmit;

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
      mutedColor: palette.muted,
      hintColor: palette.hint,
      onPasteImage: onPasteImage,
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
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final refs = parseComposeAtFileRefs(
                  controller.text,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: isVoiceListening
                  ? _voiceRecordingActions(
                      context: context,
                      palette: palette,
                      spacing: spacing,
                    )
                  : _idleActions(
                      context,
                      chrome: chrome,
                      palette: palette,
                      spacing: spacing,
                    ),
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

  Widget _composePrimaryAction({
    required BuildContext context,
    required WorkspaceChatLandingPalette palette,
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
    return _SendButton(
      palette: palette,
      canSubmit: _effectiveCanSubmit,
      isSubmitting: isSubmitting,
      onSubmit: onSubmit,
      throttleKey: _sendThrottleKey,
      blockedTooltip: submitBlockedTooltip,
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
        dangerouslySkipPermissions: chrome.dangerouslySkipPermissions,
        defaultLabel: chrome.defaultPermissionsLabel,
        fullAccessLabel: chrome.fullAccessPermissionsLabel,
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
      if (chrome.onPresetSelected != null &&
          chrome.modelPresetLabel != null &&
          chrome.emptyPresetHintLabel != null) ...[
        ComposeModelPresetChip(
          palette: palette,
          sameCliPresets: chrome.sameCliPresets,
          selectedPresetId: chrome.selectedPresetId,
          label: chrome.modelPresetLabel!,
          emptyHintLabel: chrome.emptyPresetHintLabel!,
          onPresetSelected: chrome.onPresetSelected!,
          customLabel: chrome.customLabel,
          customSelected: chrome.customSelected,
          onCustom: chrome.onCustom,
        ),
        SizedBox(width: spacing.sm),
      ],
      if (chrome.onPermissionSelected != null &&
          chrome.defaultPermissionsLabel != null &&
          chrome.fullAccessPermissionsLabel != null) ...[
        ComposePermissionChip(
          palette: palette,
          dangerouslySkipPermissions: chrome.dangerouslySkipPermissions,
          defaultLabel: chrome.defaultPermissionsLabel!,
          fullAccessLabel: chrome.fullAccessPermissionsLabel!,
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

  bool _hasBoundToolbar(BoundComposeChrome chrome) =>
      chrome.identityLabel != null ||
      chrome.onPresetSelected != null ||
      chrome.onPermissionSelected != null ||
      chrome.onTeamSettings != null;

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

    final button = Material(
      color: active ? palette.sendActive : palette.sendIdle,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active
            ? throttledOnPressed(throttleKey, onSubmit)
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
                : Icon(icon, size: icons.md, color: color),
          ),
        ),
      ),
    );
  }
}
