import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'strings.dart';
import 'theme.dart';

/// Reveal policy for History action chrome (touch-friendly by default).
enum AiActionBarReveal {
  /// Dim until hover / pointer enter (desktop).
  hover,

  /// Always visible (History default — works on touch).
  always,
}

/// Action bar — assistant-ui ActionBar (Copy + Export Markdown).
class AiMessageActionBar extends StatefulWidget {
  const AiMessageActionBar({
    required this.message,
    this.reveal = AiActionBarReveal.always,
    this.forceVisible = false,
    super.key,
  });

  final AiMessage message;
  final AiActionBarReveal reveal;
  final bool forceVisible;

  @override
  State<AiMessageActionBar> createState() => _AiMessageActionBarState();
}

class _AiMessageActionBarState extends State<AiMessageActionBar> {
  bool _hovered = false;
  bool _copied = false;
  bool _exported = false;

  @override
  Widget build(BuildContext context) {
    final strings = AiMessageStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final color = aiTheme.resolveToolTrigger(scheme);
    final plain = plainTextForCopy(widget.message);
    final markdown = markdownForExport(widget.message);
    if (plain.isEmpty && markdown.isEmpty) return const SizedBox.shrink();

    final visible = widget.reveal == AiActionBarReveal.always ||
        widget.forceVisible ||
        _hovered ||
        _copied ||
        _exported;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0.35,
        duration: const Duration(milliseconds: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _copied ? strings.copied : strings.copy,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: color,
              onPressed: plain.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: plain));
                      if (!mounted) return;
                      setState(() => _copied = true);
                      await Future<void>.delayed(
                        const Duration(milliseconds: 1600),
                      );
                      if (!mounted) return;
                      setState(() => _copied = false);
                    },
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 16,
              ),
            ),
            IconButton(
              tooltip: _exported ? strings.copied : strings.exportMarkdown,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: color,
              onPressed: markdown.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: markdown));
                      if (!mounted) return;
                      setState(() => _exported = true);
                      await Future<void>.delayed(
                        const Duration(milliseconds: 1600),
                      );
                      if (!mounted) return;
                      setState(() => _exported = false);
                    },
              icon: Icon(
                _exported ? Icons.check_rounded : Icons.description_outlined,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
