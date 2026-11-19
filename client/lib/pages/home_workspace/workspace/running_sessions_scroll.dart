import 'package:flutter/material.dart';

/// Scroll viewport for the open-sessions rows of the workspace sidebar.
///
/// Kept out of `workspace_sidebar.dart` (already oversized) and dependency
/// free so its hover behaviour can be tested on its own.
///
/// A bare [Scrollbar] only shows its thumb once the pointer is over the
/// painted strip (or the user already scrolled), so the list reads as static.
/// Here the thumb is revealed as soon as the pointer enters the rows area.
/// Touch platforms have no hover, so there it stays visible whenever the rows
/// overflow — otherwise nothing would ever hint that the strip scrolls.
class RunningSessionsScroll extends StatefulWidget {
  const RunningSessionsScroll({required this.child, super.key});

  final Widget child;

  @override
  State<RunningSessionsScroll> createState() => _RunningSessionsScrollState();
}

class _RunningSessionsScrollState extends State<RunningSessionsScroll> {
  final ScrollController _controller = ScrollController();
  bool _hovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final touchOnly = switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => false,
    };
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Scrollbar(
        controller: _controller,
        // No overflow means no paint at all: the painter skips a scrollable
        // that has nothing to scroll, so no full-height fake thumb appears.
        thumbVisibility: _hovered || touchOnly,
        thickness: 3,
        radius: const Radius.circular(1.5),
        child: ScrollConfiguration(
          // Desktop would otherwise wrap the scrollable in its own implicit
          // scrollbar, painting a second thumb next to this one.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            key: const ValueKey('workspace-running-sessions-scroll'),
            controller: _controller,
            primary: false,
            padding: EdgeInsets.zero,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
