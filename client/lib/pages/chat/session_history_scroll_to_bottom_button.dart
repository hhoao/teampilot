import 'package:flutter/material.dart';

/// Finder key for the floating scroll-to-bottom button.
const Key kSessionHistoryScrollToBottomButtonKey = ValueKey(
  'session-history-scroll-to-bottom-button',
);

/// Finder key for the dot shown when content arrived below while the user was
/// reading older turns.
const Key kSessionHistoryNewMessagesDotKey = ValueKey(
  'session-history-new-messages-dot',
);

/// Floating circular jump-to-tip control shown above the composer while the
/// transcript is scrolled away from the bottom.
class SessionHistoryScrollToBottomButton extends StatelessWidget {
  const SessionHistoryScrollToBottomButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.rightInset,
    this.showNewMessagesDot = false,
  });

  final String tooltip;
  final VoidCallback onPressed;

  /// Distance from the transcript's right edge, matching the composer card's
  /// right edge so the button sits over the input box's top-right corner.
  final double rightInset;
  final bool showNewMessagesDot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      right: rightInset,
      // Footer sits below this Stack (Column sibling), not overlaid — this
      // clears the composer's top edge.
      bottom: 24,
      child: SelectionContainer.disabled(
        child: Stack(
          children: [
            Material(
              key: kSessionHistoryScrollToBottomButtonKey,
              color: scheme.surface,
              shape: CircleBorder(
                side: BorderSide(color: scheme.outlineVariant),
              ),
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.12),
              child: IconButton(
                tooltip: tooltip,
                onPressed: onPressed,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (showNewMessagesDot)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  key: kSessionHistoryNewMessagesDotKey,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
