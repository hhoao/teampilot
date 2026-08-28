import 'dart:async';

import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../services/commands/key_chord.dart';
import '../../services/commands/shortcut_focus.dart';
import '../../services/editor/markdown_preview_find_controller.dart';
import '../../theme/app_markdown_style_sheet.dart' show buildAppMarkdownTokens;
import '../../widgets/scroll_cursor_lock.dart';
import '../../widgets/workbench/markdown_preview_find_bar.dart';

/// Mod+F intent for the markdown preview find bar (pane-private; the pane
/// claims the chord so global bindings stay suppressed while it has focus).
class _OpenFindIntent extends Intent {
  const _OpenFindIntent();
}

/// Read-only markdown preview rendered by the workbench file editor.
///
/// Environment-dependent dependencies (link/image resolvers, code-block display
/// mode, scaled padding, shell fill) are injected by the caller, so the pane
/// itself only owns document data tracking, selection-only notify filtering,
/// hover-suppression during scroll, and the scroll/cursor-lock wrapper.
///
/// When [findController] is supplied the pane also hosts preview find: Mod+F
/// opens the bar, hits paint as match washes, and the active hit reveals its
/// block. Null disables the feature (find bar hidden, chord unhandled).
class MarkdownPreviewPane extends StatefulWidget {
  const MarkdownPreviewPane({
    required this.controller,
    required this.resolvers,
    required this.codeBlockMode,
    required this.markdownPadding,
    required this.shellColor,
    this.findController,
    super.key,
  });

  final CodeLineEditingController controller;

  /// Link/image handlers (caller-built).
  final MarkdownResolvers resolvers;
  final ContentDisplayMode codeBlockMode;
  final EdgeInsetsGeometry markdownPadding;
  final Color shellColor;

  /// Surface-owned find state; null turns preview find off.
  final MarkdownPreviewFindController? findController;

  @override
  State<MarkdownPreviewPane> createState() => _MarkdownPreviewPaneState();
}

class _MarkdownPreviewPaneState extends State<MarkdownPreviewPane> {
  static const _hoverResumeIdle = Duration(milliseconds: 160);

  late String _data = widget.controller.text;

  /// Compiled document hoisted out of build: find indexing and highlight
  /// threading key on document identity, so recompiling per frame would thrash.
  late MarkdownDocument _document = compileMarkdown(_data);

  /// Reveal target for find navigation (bound to [VirtualMarkdownView]).
  MarkdownViewController? _viewController;

  /// While false, force [SystemMouseCursors.basic] so text/link cursors do not
  /// flicker as markdown scrolls under a stationary pointer.
  final ValueNotifier<bool> _hoverEffectsEnabled = ValueNotifier(true);
  Timer? _hoverResumeTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _viewController = MarkdownViewController();
    widget.findController?.addListener(_onFindChanged);
    _syncFindDocument();
  }

  @override
  void didUpdateWidget(MarkdownPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _data = widget.controller.text;
      _document = compileMarkdown(_data);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.findController != widget.findController) {
      oldWidget.findController?.removeListener(_onFindChanged);
      widget.findController?.addListener(_onFindChanged);
    }
    _syncFindDocument();
  }

  @override
  void dispose() {
    _hoverResumeTimer?.cancel();
    _hoverEffectsEnabled.dispose();
    _viewController?.dispose();
    widget.controller.removeListener(_onControllerChanged);
    widget.findController?.removeListener(_onFindChanged);
    super.dispose();
  }

  void _syncFindDocument() {
    widget.findController?.setDocument(_document);
  }

  void _onFindChanged() {
    final find = widget.findController;
    if (find == null || !mounted) return;
    setState(() {}); // repaint match highlights
    final index = find.activeIndex;
    if (index < 0 || index >= find.hits.length) return;
    final container = find.containerOf(find.hits[index]);
    if (container != null) {
      unawaited(_viewController?.revealBlock(container.blockIndex));
    }
  }

  void _onControllerChanged() {
    final next = widget.controller.text;
    // Ignore selection-only controller notifies — rebuilding MarkdownView /
    // SelectionArea mid-drag jumps the scroll back toward the document head.
    if (next == _data) return;
    setState(() {
      _data = next;
      _document = compileMarkdown(next);
    });
    _syncFindDocument();
  }

  void _setHoverEnabled(bool enabled) {
    if (_hoverEffectsEnabled.value == enabled) return;
    _hoverEffectsEnabled.value = enabled;
  }

  void _suppressHoverForScroll() {
    _hoverResumeTimer?.cancel();
    _setHoverEnabled(false);
  }

  void _scheduleHoverResume() {
    _hoverResumeTimer?.cancel();
    _hoverResumeTimer = Timer(_hoverResumeIdle, () {
      if (!mounted) return;
      _setHoverEnabled(true);
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      _scheduleHoverResume();
      return false;
    }
    if (notification is ScrollStartNotification) {
      _suppressHoverForScroll();
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta != null && delta != 0) {
        _suppressHoverForScroll();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final find = widget.findController;
    final highlights = find?.highlights;
    // SelectionArea must sit *inside* the scroll content. As an ancestor it
    // enables edge auto-scroll while selecting, which yanks long previews to
    // the top (flutter/flutter#110917).
    return ShortcutFocus(
      // The preview owns Mod+F (preview find bar). Claimed so any future
      // global command binding Mod+F is suppressed here.
      claims: {
        KeyChord(key: 'f', mods: [KeyChordMod.mod]),
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _OpenFindIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _OpenFindIntent(),
        },
        child: Actions(
          actions: {
            _OpenFindIntent: CallbackAction<_OpenFindIntent>(
              onInvoke: (_) {
                find?.openFind();
                return null;
              },
            ),
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: widget.shellColor,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _hoverEffectsEnabled,
                      builder: (context, hoverEnabled, child) =>
                          ScrollCursorLock(
                            active: !hoverEnabled,
                            child: child!,
                          ),
                      child: SingleChildScrollView(
                        padding: widget.markdownPadding,
                        child: AiLineSpacedSelectionStyle(
                          child: SelectionArea(
                            contextMenuBuilder: buildTpSelectionAreaContextMenu,
                            child: MarkdownDisplayModeScope(
                              codeBlockMode: widget.codeBlockMode,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return VirtualMarkdownView(
                                    document: _document,
                                    tokens: buildAppMarkdownTokens(
                                      Theme.of(context),
                                      MarkdownProfile.document,
                                      width: constraints.maxWidth,
                                    ),
                                    resolvers: widget.resolvers,
                                    // Natural-height block virtualization: a large .md file
                                    // previews without freezing (only visible blocks laid out).
                                    flatten: true,
                                    highlights: highlights,
                                    controller: _viewController,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (find?.open ?? false)
                Positioned(
                  top: 8,
                  right: 16,
                  child: MarkdownPreviewFindBar(controller: find!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
