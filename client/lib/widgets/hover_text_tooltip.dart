import 'dart:async';

import 'package:flutter/material.dart';

/// A lightweight hover tooltip that shows [message] in an overlay bubble.
///
/// Unlike Material's [Tooltip], it uses neither a global pointer route nor a
/// ticker, so it is safe inside a [ReorderableListView]: when the list reparents
/// a row via its internal `GlobalKey`, there is no `RawTooltip` lifecycle to
/// trip the "SingleTickerProviderStateMixin … multiple tickers" assertion.
class HoverTextTooltip extends StatefulWidget {
  const HoverTextTooltip({
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 500),
    this.maxWidth = 320,
    super.key,
  });

  final String message;
  final Widget child;
  final Duration waitDuration;
  final double maxWidth;

  @override
  State<HoverTextTooltip> createState() => _HoverTextTooltipState();
}

class _HoverTextTooltipState extends State<HoverTextTooltip> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _controller = OverlayPortalController();
  Timer? _showTimer;

  void _scheduleShow() {
    if (widget.message.isEmpty) return;
    _showTimer?.cancel();
    _showTimer = Timer(widget.waitDuration, () {
      if (mounted && !_controller.isShowing) _controller.show();
    });
  }

  void _hide() {
    _showTimer?.cancel();
    _showTimer = null;
    if (_controller.isShowing) _controller.hide();
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) return widget.child;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: _buildOverlay,
        child: MouseRegion(
          onEnter: (_) => _scheduleShow(),
          onExit: (_) => _hide(),
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final tooltipTheme = Theme.of(context).tooltipTheme;
    return IgnorePointer(
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 6),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: tooltipTheme.padding,
                decoration: tooltipTheme.decoration,
                child: Text(
                  widget.message,
                  style: tooltipTheme.textStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
