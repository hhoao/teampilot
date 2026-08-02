import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import 'strings.dart';
import 'theme.dart';

/// Reveal policy for History action chrome.
enum AiActionBarReveal {
  /// Hidden until hover / pointer enter (non-last messages).
  hover,

  /// Always visible (last message — assistant-ui `autohide="not-last"`).
  always,
}

/// Action bar — assistant-ui ActionBar (Copy + Export Markdown).
///
/// History fling architecture:
/// - Lite icons (no Material [IconButton] / [Tooltip] overlay)
/// - Hover-reveal: empty [SizedBox] until first show, then sticky mount +
///   [Opacity] via [forceVisibleListenable]; after hide, delayed unmount so
///   fling-mounted bars do not linger in the cache window
class AiMessageActionBar extends StatefulWidget {
  const AiMessageActionBar({
    required this.message,
    this.reveal = AiActionBarReveal.always,
    this.forceVisible = false,
    this.forceVisibleListenable,
    super.key,
  });

  final AiMessage message;
  final AiActionBarReveal reveal;
  final bool forceVisible;

  /// When set (history hover path), visibility toggles via Opacity without
  /// rebuilding the button row after first mount.
  final ValueListenable<bool>? forceVisibleListenable;

  @override
  State<AiMessageActionBar> createState() => _AiMessageActionBarState();
}

class _AiMessageActionBarState extends State<AiMessageActionBar> {
  static const _unmountDelay = Duration(milliseconds: 180);

  bool _hovered = false;
  bool _copied = false;
  bool _exported = false;
  bool _actionsMounted = false;
  String _plain = '';
  String _markdown = '';
  Timer? _unmountTimer;

  @override
  void initState() {
    super.initState();
    widget.forceVisibleListenable?.addListener(_onForceVisibleChanged);
    if (_shouldShowNow) {
      _mountActions();
    }
  }

  @override
  void dispose() {
    _unmountTimer?.cancel();
    widget.forceVisibleListenable?.removeListener(_onForceVisibleChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AiMessageActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.forceVisibleListenable != widget.forceVisibleListenable) {
      oldWidget.forceVisibleListenable?.removeListener(_onForceVisibleChanged);
      widget.forceVisibleListenable?.addListener(_onForceVisibleChanged);
    }
    if (oldWidget.message.id != widget.message.id) {
      _unmountTimer?.cancel();
      _actionsMounted = false;
      _plain = '';
      _markdown = '';
      if (_shouldShowNow) {
        _mountActions();
      }
      return;
    }
    if (_actionsMounted && !identical(oldWidget.message, widget.message)) {
      _plain = plainTextForCopy(widget.message);
      _markdown = markdownForExport(widget.message);
    }
    if (!_actionsMounted && _shouldShowNow) {
      _mountActions();
    } else if (_actionsMounted &&
        widget.reveal == AiActionBarReveal.hover &&
        !_shouldShowNow) {
      _scheduleUnmount();
    }
  }

  void _onForceVisibleChanged() {
    if (!mounted) return;
    if (_shouldShowNow && !_actionsMounted) {
      _unmountTimer?.cancel();
      setState(_mountActions);
    } else if (_actionsMounted &&
        widget.reveal == AiActionBarReveal.hover &&
        !_shouldShowNow) {
      _scheduleUnmount();
    }
  }

  bool get _forcedVisible {
    final listenable = widget.forceVisibleListenable;
    if (listenable != null) return listenable.value;
    return widget.forceVisible;
  }

  bool get _shouldShowNow =>
      widget.reveal == AiActionBarReveal.always ||
      _forcedVisible ||
      _hovered ||
      _copied ||
      _exported;

  void _mountActions() {
    _unmountTimer?.cancel();
    _plain = plainTextForCopy(widget.message);
    _markdown = markdownForExport(widget.message);
    if (_plain.isNotEmpty || _markdown.isNotEmpty) {
      _actionsMounted = true;
    }
  }

  void _scheduleUnmount() {
    if (widget.reveal != AiActionBarReveal.hover) return;
    _unmountTimer?.cancel();
    _unmountTimer = Timer(_unmountDelay, () {
      if (!mounted || _shouldShowNow) return;
      setState(() {
        _actionsMounted = false;
        _plain = '';
        _markdown = '';
      });
    });
  }

  Future<void> _copyPlain() async {
    await Clipboard.setData(ClipboardData(text: _plain));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  Future<void> _copyMarkdown() async {
    await Clipboard.setData(ClipboardData(text: _markdown));
    if (!mounted) return;
    setState(() => _exported = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _exported = false);
  }

  @override
  Widget build(BuildContext context) {
    // Fixed height so hover reveal never shifts messages below.
    const barHeight = 40.0;

    if (!_actionsMounted) {
      const placeholder = SizedBox(height: barHeight);
      if (widget.forceVisibleListenable != null) {
        return const SelectionContainer.disabled(child: placeholder);
      }
      return SelectionContainer.disabled(
        child: MouseRegion(
          onEnter: (_) => setState(() {
            _hovered = true;
            _mountActions();
          }),
          onExit: (_) {
            setState(() => _hovered = false);
            _scheduleUnmount();
          },
          child: placeholder,
        ),
      );
    }

    final strings = AiMessageStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final color = aiTheme.resolveToolTrigger(scheme);

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LiteIconAction(
          label: _copied ? strings.copied : strings.copy,
          icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
          color: color,
          onPressed: _plain.isEmpty ? null : _copyPlain,
        ),
        _LiteIconAction(
          label: _exported ? strings.copied : strings.exportMarkdown,
          icon:
              _exported ? Icons.check_rounded : Icons.description_outlined,
          color: color,
          onPressed: _markdown.isEmpty ? null : _copyMarkdown,
        ),
      ],
    );

    final listenable = widget.forceVisibleListenable;
    final Widget barBody;
    if (listenable != null) {
      barBody = ListenableBuilder(
        listenable: listenable,
        builder: (context, child) {
          final show = _shouldShowNow;
          return SizedBox(
            height: barHeight,
            child: Opacity(
              opacity: show ? 1 : 0,
              child: IgnorePointer(ignoring: !show, child: child),
            ),
          );
        },
        child: actions,
      );
    } else {
      final show = _shouldShowNow;
      barBody = SizedBox(
        height: barHeight,
        child: Opacity(
          opacity: show ? 1 : 0,
          child: IgnorePointer(ignoring: !show, child: actions),
        ),
      );
    }

    final trackLocalHover = listenable == null;

    return SelectionContainer.disabled(
      child: trackLocalHover
          ? MouseRegion(
              onEnter: (_) {
                _unmountTimer?.cancel();
                setState(() => _hovered = true);
              },
              onExit: (_) {
                setState(() => _hovered = false);
                _scheduleUnmount();
              },
              child: barBody,
            )
          : barBody,
    );
  }
}

/// Compact icon affordance without Material [IconButton] / [Tooltip].
class _LiteIconAction extends StatelessWidget {
  const _LiteIconAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final iconColor = enabled ? color : color.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      label: label,
      enabled: enabled,
      child: TpHover(
        enabled: enabled,
        onTap: onPressed,
        width: 36,
        height: 36,
        borderRadius: BorderRadius.circular(8),
        hoverColor: color.withValues(alpha: 0.08),
        child: Icon(icon, size: 16, color: iconColor),
      ),
    );
  }
}
