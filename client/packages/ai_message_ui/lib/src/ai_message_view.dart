import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_message_parts.dart';
import 'history_render_scope.dart';
import 'markdown/compiled_markdown_chrome.dart';
import 'message_action_bar.dart';
import 'message_role_scope.dart';
import 'message_streaming_scope.dart';
import 'part_registry.dart';
import 'parts/fade_expand_body.dart';
import 'strings.dart';
import 'theme.dart';

/// Role layout aligned with assistant-ui UserMessage / AssistantMessage.
class AiMessageView extends StatefulWidget {
  const AiMessageView({
    required this.message,
    this.registry = AiPartRegistry.defaults,
    this.showActionBar = true,
    this.actionBarReveal = AiActionBarReveal.always,
    this.actionBarHoverEnabled,
    this.chainOfThoughtAutoExpand = false,
    this.onRetryDelivery,
    this.onEdit,
    this.editLabel = 'Edit message',
    this.editing = false,
    this.onSubmitEdit,
    this.onCancelEdit,
    this.editSendLabel = 'Send',
    this.editCancelLabel = 'Cancel',
    this.onFork,
    this.forkLabel = 'Fork from here',
    this.rewindForkEnabled = true,
    this.versionIndex,
    this.versionCount,
    this.onPreviousVersion,
    this.onNextVersion,
    this.previousVersionLabel = 'Previous version',
    this.nextVersionLabel = 'Next version',
    super.key,
  });

  final AiMessage message;
  final AiPartRegistry registry;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;

  /// When set, shows a refresh icon on the action bar (failed delivery retry).
  final VoidCallback? onRetryDelivery;

  /// When set, shows an edit action on the action bar. Only user messages
  /// render the inline editor.
  final VoidCallback? onEdit;
  final String editLabel;

  /// When true, a user message renders [_UserMessageEditor] instead of the
  /// bubble.
  final bool editing;
  final ValueChanged<String>? onSubmitEdit;
  final VoidCallback? onCancelEdit;
  final String editSendLabel;
  final String editCancelLabel;

  final VoidCallback? onFork;
  final String forkLabel;
  final bool rewindForkEnabled;
  final int? versionIndex;
  final int? versionCount;
  final VoidCallback? onPreviousVersion;
  final VoidCallback? onNextVersion;
  final String previousVersionLabel;
  final String nextVersionLabel;

  /// When `false`, ignore pointer-enter for hover ActionBars (history fling).
  /// Defaults to always enabled when null.
  final ValueListenable<bool>? actionBarHoverEnabled;

  /// Auto-expand this message's last chain-of-thought while it is the live
  /// thinking tail (see [AiMessageParts.chainOfThoughtAutoExpand]).
  final bool chainOfThoughtAutoExpand;

  @override
  State<AiMessageView> createState() => _AiMessageViewState();
}

class _AiMessageViewState extends State<AiMessageView> {
  /// Hover is isolated from message body rebuilds (markdown / tools).
  final ValueNotifier<bool> _hovered = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    widget.actionBarHoverEnabled?.addListener(_onHoverEnabledChanged);
  }

  @override
  void didUpdateWidget(covariant AiMessageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionBarHoverEnabled != widget.actionBarHoverEnabled) {
      oldWidget.actionBarHoverEnabled?.removeListener(_onHoverEnabledChanged);
      widget.actionBarHoverEnabled?.addListener(_onHoverEnabledChanged);
    }
  }

  @override
  void dispose() {
    widget.actionBarHoverEnabled?.removeListener(_onHoverEnabledChanged);
    _hovered.dispose();
    super.dispose();
  }

  bool get _hoverAllowed => widget.actionBarHoverEnabled?.value ?? true;

  void _onHoverEnabledChanged() {
    if (!_hoverAllowed && _hovered.value) {
      _hovered.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiTheme = AiMessageTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final parts = AiMessageRoleScope(
      role: widget.message.role,
      child: AiMessageStreamingScope(
        streaming: widget.message.status == AiMessageStatus.incomplete,
        child: AiMessageParts(
          parts: widget.message.parts,
          registry: widget.registry,
          chainOfThoughtAutoExpand: widget.chainOfThoughtAutoExpand,
        ),
      ),
    );
    final trackHover =
        widget.showActionBar &&
        widget.actionBarReveal == AiActionBarReveal.hover;

    final body = Padding(
      padding: EdgeInsets.only(
        top: widget.message.role == AiRole.user
            ? aiTheme.userMessageTopInset
            : 0,
        bottom: aiTheme.messageSpacing,
      ),
      child: RepaintBoundary(
        child: switch (widget.message.role) {
          AiRole.user => _UserBubble(
            scheme: scheme,
            aiTheme: aiTheme,
            parts: parts,
            message: widget.message,
            showActionBar: widget.showActionBar,
            actionBarReveal: widget.actionBarReveal,
            hoverListenable: trackHover ? _hovered : null,
            onRetryDelivery: widget.onRetryDelivery,
            onEdit: widget.onEdit,
            editLabel: widget.editLabel,
            editing: widget.editing,
            onSubmitEdit: widget.onSubmitEdit,
            onCancelEdit: widget.onCancelEdit,
            editSendLabel: widget.editSendLabel,
            editCancelLabel: widget.editCancelLabel,
            onFork: widget.onFork,
            forkLabel: widget.forkLabel,
            rewindForkEnabled: widget.rewindForkEnabled,
            versionIndex: widget.versionIndex,
            versionCount: widget.versionCount,
            onPreviousVersion: widget.onPreviousVersion,
            onNextVersion: widget.onNextVersion,
            previousVersionLabel: widget.previousVersionLabel,
            nextVersionLabel: widget.nextVersionLabel,
          ),
          AiRole.assistant => _AssistantBlock(
            scheme: scheme,
            aiTheme: aiTheme,
            parts: parts,
            message: widget.message,
            showActionBar: widget.showActionBar,
            actionBarReveal: widget.actionBarReveal,
            hoverListenable: trackHover ? _hovered : null,
            onFork: widget.onFork,
            forkLabel: widget.forkLabel,
            rewindForkEnabled: widget.rewindForkEnabled,
            versionIndex: widget.versionIndex,
            versionCount: widget.versionCount,
            onPreviousVersion: widget.onPreviousVersion,
            onNextVersion: widget.onNextVersion,
            previousVersionLabel: widget.previousVersionLabel,
            nextVersionLabel: widget.nextVersionLabel,
          ),
          AiRole.system => Align(
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: aiTheme.resolveMutedSurface(scheme),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: DefaultTextStyle.merge(
                  style: aiTheme.markdown.systemMessage(
                    scheme.onSurfaceVariant,
                  ),
                  child: parts,
                ),
              ),
            ),
          ),
        },
      ),
    );

    if (!trackHover) return body;

    // Keep MouseRegion mounted always — swapping it via ListenableBuilder when
    // the scroll gate flips remounts hit-targets under the cursor and jitters
    // scroll metrics. Gate only ignores enter; exit/clear still via listener.
    return MouseRegion(
      onEnter: (_) {
        if (!_hoverAllowed) return;
        _hovered.value = true;
      },
      onExit: (_) => _hovered.value = false,
      child: body,
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.status == AiMessageStatus.complete) {
      return const SizedBox.shrink();
    }
    final strings = AiMessageStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final markdown = AiMessageTheme.of(context).markdown;
    final label = message.status == AiMessageStatus.cancelled
        ? strings.messageCancelled
        : strings.messageIncomplete;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: markdown.statusBanner(scheme.onErrorContainer),
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.scheme,
    required this.aiTheme,
    required this.parts,
    required this.message,
    required this.showActionBar,
    required this.actionBarReveal,
    this.hoverListenable,
    this.onRetryDelivery,
    this.onEdit,
    this.editLabel = 'Edit message',
    this.editing = false,
    this.onSubmitEdit,
    this.onCancelEdit,
    this.editSendLabel = 'Send',
    this.editCancelLabel = 'Cancel',
    this.onFork,
    this.forkLabel = 'Fork from here',
    this.rewindForkEnabled = true,
    this.versionIndex,
    this.versionCount,
    this.onPreviousVersion,
    this.onNextVersion,
    this.previousVersionLabel = 'Previous version',
    this.nextVersionLabel = 'Next version',
  });

  final ColorScheme scheme;
  final AiMessageTheme aiTheme;
  final Widget parts;
  final AiMessage message;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;
  final ValueListenable<bool>? hoverListenable;
  final VoidCallback? onRetryDelivery;
  final VoidCallback? onEdit;
  final String editLabel;
  final bool editing;
  final ValueChanged<String>? onSubmitEdit;
  final VoidCallback? onCancelEdit;
  final String editSendLabel;
  final String editCancelLabel;
  final VoidCallback? onFork;
  final String forkLabel;
  final bool rewindForkEnabled;
  final int? versionIndex;
  final int? versionCount;
  final VoidCallback? onPreviousVersion;
  final VoidCallback? onNextVersion;
  final String previousVersionLabel;
  final String nextVersionLabel;

  @override
  Widget build(BuildContext context) {
    if (editing) {
      return _UserMessageEditor(
        scheme: scheme,
        theme: aiTheme,
        initialText: plainTextForCopy(message),
        sendLabel: editSendLabel,
        cancelLabel: editCancelLabel,
        onSubmit: (text) => onSubmitEdit?.call(text),
        onCancel: onCancelEdit,
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve action-bar chrome so Row never overflows the thread width.
          final actionBarReserve =
              80.0 +
              (onRetryDelivery != null ? 36.0 : 0.0) +
              (onEdit != null ? 36.0 : 0.0) +
              (onFork != null ? 36.0 : 0.0) +
              (versionCount != null && versionCount! > 1 ? 108.0 : 0.0);
          final threadMax = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 480.0;
          final canFitActionBar =
              showActionBar && threadMax >= actionBarReserve;
          final bubbleCap = canFitActionBar
              ? (threadMax - actionBarReserve).clamp(0.0, threadMax)
              : threadMax;
          final bubbleMax = aiTheme.userBubbleMaxWidth.clamp(0.0, bubbleCap);
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (canFitActionBar)
                _HoverScopedActionBar(
                  message: message,
                  reveal: actionBarReveal,
                  hoverListenable: hoverListenable,
                  onRetryDelivery: onRetryDelivery,
                  onEdit: onEdit,
                  editLabel: editLabel,
                  onFork: onFork,
                  forkLabel: forkLabel,
                  rewindForkEnabled: rewindForkEnabled,
                  versionIndex: versionIndex,
                  versionCount: versionCount,
                  onPreviousVersion: onPreviousVersion,
                  onNextVersion: onNextVersion,
                  previousVersionLabel: previousVersionLabel,
                  nextVersionLabel: nextVersionLabel,
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: bubbleMax),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(aiTheme.userBubbleRadius),
                  child: ColoredBox(
                    color: aiTheme.resolveUserBubble(scheme),
                    child: _UserBubbleFadeHost(
                      messageId: message.id,
                      textSignature: message.parts
                          .whereType<AiTextPart>()
                          .map((p) => p.text)
                          .join('\u0000'),
                      fadeColor: aiTheme.resolveUserBubble(scheme),
                      contentPadding: kUserBubbleContentPadding,
                      child: DefaultTextStyle.merge(
                        style: aiTheme.markdown.userBubble(
                          aiTheme.resolveUserForeground(scheme),
                        ),
                        textHeightBehavior: kUserBubbleTextHeightBehavior,
                        child: parts,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UserBubbleFadeHost extends StatefulWidget {
  const _UserBubbleFadeHost({
    required this.messageId,
    required this.textSignature,
    required this.fadeColor,
    required this.contentPadding,
    required this.child,
  });

  final String messageId;
  final String textSignature;
  final Color fadeColor;
  final EdgeInsetsGeometry contentPadding;
  final Widget child;

  @override
  State<_UserBubbleFadeHost> createState() => _UserBubbleFadeHostState();
}

class _UserBubbleFadeHostState extends State<_UserBubbleFadeHost> {
  bool _open = false;

  @override
  void didUpdateWidget(covariant _UserBubbleFadeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId ||
        oldWidget.textSignature != widget.textSignature) {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // History review already budgets long markdown with its own mask
    // (_ExpandableHistoryMarkdown), which applies [kUserBubbleContentPadding]
    // internally and keeps its fade/chevron edge-to-edge. Do not add an outer
    // padding here or the mask would be inset from the bubble edges.
    if (AiHistoryRenderScope.maybeOf(context) != null) {
      return widget.child;
    }
    return AiFadeExpandBody(
      open: _open,
      onToggle: () => setState(() => _open = !_open),
      fadeColor: widget.fadeColor,
      contentPadding: widget.contentPadding,
      child: widget.child,
    );
  }
}

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({
    required this.scheme,
    required this.aiTheme,
    required this.parts,
    required this.message,
    required this.showActionBar,
    required this.actionBarReveal,
    this.hoverListenable,
    this.onFork,
    this.forkLabel = 'Fork from here',
    this.rewindForkEnabled = true,
    this.versionIndex,
    this.versionCount,
    this.onPreviousVersion,
    this.onNextVersion,
    this.previousVersionLabel = 'Previous version',
    this.nextVersionLabel = 'Next version',
  });

  final ColorScheme scheme;
  final AiMessageTheme aiTheme;
  final Widget parts;
  final AiMessage message;
  final bool showActionBar;
  final AiActionBarReveal actionBarReveal;
  final ValueListenable<bool>? hoverListenable;
  final VoidCallback? onFork;
  final String forkLabel;
  final bool rewindForkEnabled;
  final int? versionIndex;
  final int? versionCount;
  final VoidCallback? onPreviousVersion;
  final VoidCallback? onNextVersion;
  final String previousVersionLabel;
  final String nextVersionLabel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusBanner(message: message),
            DefaultTextStyle.merge(
              style: aiTheme.markdown.assistantBody(scheme.onSurface),
              child: parts,
            ),
            if (showActionBar)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _HoverScopedActionBar(
                  message: message,
                  reveal: actionBarReveal,
                  hoverListenable: hoverListenable,
                  onFork: onFork,
                  forkLabel: forkLabel,
                  rewindForkEnabled: rewindForkEnabled,
                  versionIndex: versionIndex,
                  versionCount: versionCount,
                  onPreviousVersion: onPreviousVersion,
                  onNextVersion: onNextVersion,
                  previousVersionLabel: previousVersionLabel,
                  nextVersionLabel: nextVersionLabel,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Passes hover visibility into the action bar without rebuilding message body.
class _HoverScopedActionBar extends StatelessWidget {
  const _HoverScopedActionBar({
    required this.message,
    required this.reveal,
    this.hoverListenable,
    this.onRetryDelivery,
    this.onEdit,
    this.editLabel = 'Edit message',
    this.onFork,
    this.forkLabel = 'Fork from here',
    this.rewindForkEnabled = true,
    this.versionIndex,
    this.versionCount,
    this.onPreviousVersion,
    this.onNextVersion,
    this.previousVersionLabel = 'Previous version',
    this.nextVersionLabel = 'Next version',
  });

  final AiMessage message;
  final AiActionBarReveal reveal;
  final ValueListenable<bool>? hoverListenable;
  final VoidCallback? onRetryDelivery;
  final VoidCallback? onEdit;
  final String editLabel;
  final VoidCallback? onFork;
  final String forkLabel;
  final bool rewindForkEnabled;
  final int? versionIndex;
  final int? versionCount;
  final VoidCallback? onPreviousVersion;
  final VoidCallback? onNextVersion;
  final String previousVersionLabel;
  final String nextVersionLabel;

  @override
  Widget build(BuildContext context) {
    return AiMessageActionBar(
      message: message,
      reveal: reveal,
      forceVisibleListenable: hoverListenable,
      onRetryDelivery: onRetryDelivery,
      onEdit: onEdit,
      editLabel: editLabel,
      onFork: onFork,
      forkLabel: forkLabel,
      rewindForkEnabled: rewindForkEnabled,
      versionIndex: versionIndex,
      versionCount: versionCount,
      onPreviousVersion: onPreviousVersion,
      onNextVersion: onNextVersion,
      previousVersionLabel: previousVersionLabel,
      nextVersionLabel: nextVersionLabel,
    );
  }
}

class _SendEditIntent extends Intent {
  const _SendEditIntent();
}

class _CancelEditIntent extends Intent {
  const _CancelEditIntent();
}

/// In-place editor for a user message. Enter sends, Shift+Enter is a newline.
class _UserMessageEditor extends StatefulWidget {
  const _UserMessageEditor({
    required this.scheme,
    required this.theme,
    required this.initialText,
    required this.sendLabel,
    required this.cancelLabel,
    required this.onSubmit,
    required this.onCancel,
  });

  final ColorScheme scheme;
  final AiMessageTheme theme;
  final String initialText;
  final String sendLabel;
  final String cancelLabel;
  final ValueChanged<String> onSubmit;
  final VoidCallback? onCancel;

  @override
  State<_UserMessageEditor> createState() => _UserMessageEditorState();
}

class _UserMessageEditorState extends State<_UserMessageEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  var _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focus = FocusNode()..requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    final text = _controller.text.trim();
    if (text.isEmpty || text == widget.initialText.trim()) {
      widget.onCancel?.call();
      return;
    }
    _submitted = true;
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.theme.userBubbleMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.enter): _SendEditIntent(),
                SingleActivator(LogicalKeyboardKey.escape): _CancelEditIntent(),
              },
              child: Actions(
                actions: {
                  _SendEditIntent: CallbackAction<_SendEditIntent>(
                    onInvoke: (_) {
                      _submit();
                      return null;
                    },
                  ),
                  _CancelEditIntent: CallbackAction<_CancelEditIntent>(
                    onInvoke: (_) {
                      widget.onCancel?.call();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: widget.theme.resolveUserBubble(widget.scheme),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        widget.theme.userBubbleRadius,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: Text(widget.cancelLabel),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _submit,
                  child: Text(widget.sendLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
