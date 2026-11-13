import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_message_interaction_scope.dart';
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
    this.timestampText,
    this.onRetryDelivery,
    this.onEdit,
    this.editLabel = 'Edit message',
    this.editing = false,
    this.editInitialText,
    this.onSubmitEdit,
    this.onCancelEdit,
    this.onPickEditAttachments,
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
    this.leadingAction,
    super.key,
  });

  final AiMessage message;

  /// Pre-formatted timestamp for the action bar; null hides the label.
  final String? timestampText;

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

  /// Text the editor starts with. Defaults to the message's plain text; set
  /// this to keep a failed edit's draft when the editor reopens.
  final String? editInitialText;

  /// Returns whether the edit was accepted. A false result keeps the editor
  /// open (and re-enables submit) so the user can retry.
  final Future<bool> Function(String text)? onSubmitEdit;
  final VoidCallback? onCancelEdit;

  /// Opens the host's file picker and returns `@` references to insert into
  /// the edit draft. Null hides the editor's attach action.
  final Future<List<String>> Function()? onPickEditAttachments;

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

  /// Rendered immediately left of a user bubble, vertically centered on the
  /// bubble itself (not on the bubble + action bar). Used for retry actions.
  final Widget? leadingAction;

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
    final rewindForkEnabled =
        AiMessageInteractionScope.maybeRewindEnabled(context) ??
        widget.rewindForkEnabled;
    final isUser = widget.message.role == AiRole.user;
    // The user action bar lives under the bubble and reserves its own row, so
    // drop the outer message gap while it is shown (the bar/editor supplies the
    // spacing below the message).
    final actionsUnderBubble = isUser && widget.showActionBar;

    final body = Padding(
      padding: EdgeInsets.only(
        top: isUser ? aiTheme.userMessageTopInset : 0,
        bottom: actionsUnderBubble ? 0 : aiTheme.messageSpacing,
      ),
      child: RepaintBoundary(
        child: switch (widget.message.role) {
          AiRole.user => _UserBubble(
            timestampText: widget.timestampText,
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
            editInitialText: widget.editInitialText,
            onSubmitEdit: widget.onSubmitEdit,
            onCancelEdit: widget.onCancelEdit,
            onPickEditAttachments: widget.onPickEditAttachments,
            editSendLabel: widget.editSendLabel,
            editCancelLabel: widget.editCancelLabel,
            onFork: widget.onFork,
            forkLabel: widget.forkLabel,
            rewindForkEnabled: rewindForkEnabled,
            versionIndex: widget.versionIndex,
            versionCount: widget.versionCount,
            onPreviousVersion: widget.onPreviousVersion,
            onNextVersion: widget.onNextVersion,
            previousVersionLabel: widget.previousVersionLabel,
            nextVersionLabel: widget.nextVersionLabel,
            leadingAction: widget.leadingAction,
          ),
          AiRole.assistant => _AssistantBlock(
            timestampText: widget.timestampText,
            scheme: scheme,
            aiTheme: aiTheme,
            parts: parts,
            message: widget.message,
            showActionBar: widget.showActionBar,
            actionBarReveal: widget.actionBarReveal,
            hoverListenable: trackHover ? _hovered : null,
            onFork: widget.onFork,
            forkLabel: widget.forkLabel,
            rewindForkEnabled: rewindForkEnabled,
            versionIndex: widget.versionIndex,
            versionCount: widget.versionCount,
            onPreviousVersion: widget.onPreviousVersion,
            onNextVersion: widget.onNextVersion,
            previousVersionLabel: widget.previousVersionLabel,
            nextVersionLabel: widget.nextVersionLabel,
          ),
          AiRole.system => Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: aiTheme.threadMaxWidth,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: aiTheme.resolveMutedSurface(scheme),
                    borderRadius: BorderRadius.circular(
                      aiTheme.userBubbleRadius,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
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
    this.editInitialText,
    this.onSubmitEdit,
    this.onCancelEdit,
    this.onPickEditAttachments,
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
    this.timestampText,
    this.leadingAction,
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
  final String? editInitialText;
  final Future<bool> Function(String text)? onSubmitEdit;
  final VoidCallback? onCancelEdit;
  final Future<List<String>> Function()? onPickEditAttachments;
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

  final String? timestampText;

  /// Rendered immediately left of the bubble, vertically centered on it.
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    final collapsed = _buildCollapsed(context);
    if (!editing) return collapsed;
    final editor = _UserMessageEditor(
      scheme: scheme,
      theme: aiTheme,
      initialText: editInitialText ?? plainTextForCopy(message),
      originalText: plainTextForCopy(message),
      sendLabel: editSendLabel,
      cancelLabel: editCancelLabel,
      onSubmit: onSubmitEdit ?? (_) async => true,
      onCancel: onCancelEdit,
      onPickAttachments: onPickEditAttachments,
    );
    // Keep the collapsed bubble + action row in the tree as an invisible
    // sizer and let the editor fill that exact slot. Opening the editor then
    // never changes the message height; a long draft scrolls inside the box
    // instead of pushing the transcript down.
    return Stack(
      children: [
        Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: collapsed,
        ),
        Positioned.fill(child: editor),
      ],
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final threadMax = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 480.0;
          final bubbleMax = aiTheme.userBubbleMaxWidth.clamp(0.0, threadMax);
          final bubble = ConstrainedBox(
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
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (leadingAction == null)
                bubble
              else
                // The action centres on the bubble itself, not on the bubble
                // plus the action bar underneath it.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    leadingAction!,
                    const SizedBox(width: 6),
                    Flexible(child: bubble),
                  ],
                ),
              if (showActionBar)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 18),
                  child: _HoverScopedActionBar(
                    message: message,
                    timestampText: timestampText,
                    reveal: actionBarReveal,
                    hoverListenable: hoverListenable,
                    dense: true,
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
    this.timestampText,
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

  final String? timestampText;

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
                  timestampText: timestampText,
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
    this.dense = false,
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
    this.timestampText,
  });

  final AiMessage message;
  final AiActionBarReveal reveal;
  final ValueListenable<bool>? hoverListenable;
  final bool dense;
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

  final String? timestampText;

  @override
  Widget build(BuildContext context) {
    return AiMessageActionBar(
      message: message,
      timestampText: timestampText,
      reveal: reveal,
      forceVisibleListenable: hoverListenable,
      dense: dense,
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

/// Editor box radius (the bubble radius is too tight for a bordered field).
const double _kUserEditRadius = 16;

/// Space the editor leaves below its border box, before the next message.
const double _kUserEditBottomInset = 12;

class _SendEditIntent extends Intent {
  const _SendEditIntent();
}

class _CancelEditIntent extends Intent {
  const _CancelEditIntent();
}

/// In-place editor for a user message. Enter sends, Shift+Enter is a newline.
///
/// The box replaces the bubble and its action row with roughly the same
/// footprint, so opening the editor does not jump the transcript height.
class _UserMessageEditor extends StatefulWidget {
  const _UserMessageEditor({
    required this.scheme,
    required this.theme,
    required this.initialText,
    required this.originalText,
    required this.sendLabel,
    required this.cancelLabel,
    required this.onSubmit,
    required this.onCancel,
    this.onPickAttachments,
  });

  final ColorScheme scheme;
  final AiMessageTheme theme;

  /// Text the field starts with (a draft when reopening a failed edit).
  final String initialText;

  /// Text of the message being edited, used to detect a no-op submit.
  final String originalText;
  final String sendLabel;
  final String cancelLabel;
  final Future<bool> Function(String text) onSubmit;
  final VoidCallback? onCancel;

  /// Opens the host picker; returned `@` references are inserted at the cursor.
  final Future<List<String>> Function()? onPickAttachments;

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

  Future<void> _submit() async {
    if (_submitted) return;
    final text = _controller.text.trim();
    if (text.isEmpty || text == widget.originalText.trim()) {
      widget.onCancel?.call();
      return;
    }
    _submitted = true;
    final accepted = await widget.onSubmit(text);
    if (!accepted && mounted) {
      // Keep the editor open so a retry can send the same draft again.
      _submitted = false;
    }
  }

  Future<void> _attach() async {
    final pick = widget.onPickAttachments;
    if (pick == null || _submitted) return;
    final refs = await pick();
    if (!mounted || refs.isEmpty) return;
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final leading = start > 0 && text[start - 1].trim().isNotEmpty ? ' ' : '';
    final trailing = end < text.length && text[end].trim().isNotEmpty
        ? ' '
        : '';
    final insertion = '$leading${refs.join(' ')}$trailing';
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AiMessageStrings.of(context);
    final textStyle = widget.theme.markdown.userBubble(widget.scheme.onSurface);
    return Padding(
      // Breathing room between the box and whatever follows the message.
      padding: const EdgeInsets.only(bottom: _kUserEditBottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
        decoration: BoxDecoration(
          color: widget.scheme.surface,
          borderRadius: BorderRadius.circular(_kUserEditRadius),
          border: Border.all(color: widget.scheme.primary),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  // Fill the box so a click anywhere in the text area focuses
                  // the field; longer drafts scroll inside the fixed slot.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Shortcuts(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.enter):
                            _SendEditIntent(),
                        SingleActivator(LogicalKeyboardKey.escape):
                            _CancelEditIntent(),
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
                          readOnly: _submitted,
                          maxLines: null,
                          minLines: 1,
                          style: textStyle,
                          cursorColor: widget.scheme.primary,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            // The app theme pins text fields to a control
                            // height; the editor text sits directly in the
                            // bordered box.
                            constraints: BoxConstraints(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onPickAttachments != null) ...[
                  IconButton(
                    tooltip: strings.attachFile,
                    onPressed: _submitted ? null : _attach,
                    icon: const Icon(Icons.attach_file_rounded),
                    iconSize: 20,
                    color: widget.scheme.onSurfaceVariant,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(28, 28),
                      maximumSize: const Size(28, 28),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                _editPill(
                  label: widget.cancelLabel,
                  onPressed: _submitted ? null : widget.onCancel,
                ),
                const SizedBox(width: 8),
                _editPill(
                  label: widget.sendLabel,
                  onPressed: _submitted ? null : _submit,
                  primary: true,
                  child: _submitted
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.scheme.onPrimary,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Compact pill action matching the composer's cancel/send pair.
  Widget _editPill({
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
    Widget? child,
  }) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelLarge),
    );
    final content = child ?? Text(label);
    if (primary) {
      return FilledButton(style: style, onPressed: onPressed, child: content);
    }
    return OutlinedButton(
      style: style.copyWith(
        foregroundColor: WidgetStatePropertyAll(widget.scheme.onSurfaceVariant),
        side: WidgetStatePropertyAll(
          BorderSide(color: widget.scheme.outlineVariant),
        ),
      ),
      onPressed: onPressed,
      child: content,
    );
  }
}
