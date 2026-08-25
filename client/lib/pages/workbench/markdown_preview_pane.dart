import 'dart:async';

import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../theme/app_markdown_style_sheet.dart' show buildAppMarkdownTokens;
import '../../widgets/scroll_cursor_lock.dart';

/// Read-only markdown preview rendered by the workbench file editor.
///
/// Environment-dependent dependencies (link/image resolvers, code-block display
/// mode, scaled padding, shell fill) are injected by the caller, so the pane
/// itself only owns document data tracking, selection-only notify filtering,
/// hover-suppression during scroll, and the scroll/cursor-lock wrapper.
class MarkdownPreviewPane extends StatefulWidget {
  const MarkdownPreviewPane({
    required this.controller,
    required this.resolvers,
    required this.codeBlockMode,
    required this.markdownPadding,
    required this.shellColor,
    super.key,
  });

  final CodeLineEditingController controller;

  /// Link/image handlers (caller-built).
  final MarkdownResolvers resolvers;
  final ContentDisplayMode codeBlockMode;
  final EdgeInsetsGeometry markdownPadding;
  final Color shellColor;

  @override
  State<MarkdownPreviewPane> createState() => _MarkdownPreviewPaneState();
}

class _MarkdownPreviewPaneState extends State<MarkdownPreviewPane> {
  static const _hoverResumeIdle = Duration(milliseconds: 160);

  late String _data = widget.controller.text;

  /// While false, force [SystemMouseCursors.basic] so text/link cursors do not
  /// flicker as markdown scrolls under a stationary pointer.
  final ValueNotifier<bool> _hoverEffectsEnabled = ValueNotifier(true);
  Timer? _hoverResumeTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(MarkdownPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _data = widget.controller.text;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _hoverResumeTimer?.cancel();
    _hoverEffectsEnabled.dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final next = widget.controller.text;
    // Ignore selection-only controller notifies — rebuilding MarkdownView /
    // SelectionArea mid-drag jumps the scroll back toward the document head.
    if (next == _data) return;
    setState(() => _data = next);
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
    // SelectionArea must sit *inside* the scroll content. As an ancestor it
    // enables edge auto-scroll while selecting, which yanks long previews to
    // the top (flutter/flutter#110917).
    return ColoredBox(
      color: widget.shellColor,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ValueListenableBuilder<bool>(
          valueListenable: _hoverEffectsEnabled,
          builder: (context, hoverEnabled, child) =>
              ScrollCursorLock(active: !hoverEnabled, child: child!),
          child: SingleChildScrollView(
            padding: widget.markdownPadding,
            child: AiLineSpacedSelectionStyle(
              child: SelectionArea(
                child: MarkdownDisplayModeScope(
                  codeBlockMode: widget.codeBlockMode,
                  child: VirtualMarkdownView(
                    document: compileMarkdown(_data),
                    tokens: buildAppMarkdownTokens(
                      Theme.of(context),
                      MarkdownProfile.document,
                      // v1: window width, not preview pane width.
                      width: MediaQuery.sizeOf(context).width,
                    ),
                    resolvers: widget.resolvers,
                    // Natural-height block virtualization: a large .md file
                    // previews without freezing (only visible blocks laid out).
                    flatten: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
