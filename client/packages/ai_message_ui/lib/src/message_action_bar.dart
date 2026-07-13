import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'strings.dart';
import 'theme.dart';

/// Hover/always-visible copy bar — assistant-ui ActionBar (Copy only for History).
class AiMessageActionBar extends StatefulWidget {
  const AiMessageActionBar({
    required this.message,
    this.alwaysVisible = false,
    super.key,
  });

  final AiMessage message;
  final bool alwaysVisible;

  @override
  State<AiMessageActionBar> createState() => _AiMessageActionBarState();
}

class _AiMessageActionBarState extends State<AiMessageActionBar> {
  bool _hovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final strings = AiMessageStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final visible = widget.alwaysVisible || _hovered || _copied;
    final text = plainTextForCopy(widget.message);
    if (text.isEmpty) return const SizedBox.shrink();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: !visible,
          child: IconButton(
            tooltip: _copied ? strings.copied : strings.copy,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: aiTheme.resolveToolTrigger(scheme),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              setState(() => _copied = true);
              await Future<void>.delayed(const Duration(milliseconds: 1600));
              if (!mounted) return;
              setState(() => _copied = false);
            },
            icon: Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 16,
            ),
          ),
        ),
      ),
    );
  }
}
