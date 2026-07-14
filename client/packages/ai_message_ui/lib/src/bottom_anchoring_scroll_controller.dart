import 'package:flutter/widgets.dart';

/// [ScrollController] whose position stays pinned to [maxScrollExtent] until
/// [releaseBottomAnchor] — so the first paint is already at the bottom without
/// a visible top→bottom jump (and without [ListView.reverse]).
class BottomAnchoringScrollController extends ScrollController {
  BottomAnchoringScrollController({super.initialScrollOffset, super.keepScrollOffset});

  bool _anchorToBottom = true;

  bool get isAnchoringToBottom => _anchorToBottom;

  void releaseBottomAnchor() {
    if (!_anchorToBottom) return;
    _anchorToBottom = false;
  }

  /// Re-engage bottom pinning (e.g. history reload / became idle).
  void engageBottomAnchor() {
    _anchorToBottom = true;
    if (!hasClients) return;
    final position = this.position;
    final max = position.maxScrollExtent;
    if (max > 0 && (position.pixels - max).abs() > 1.0) {
      position.jumpTo(max);
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _BottomAnchoringScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      shouldAnchor: () => _anchorToBottom,
    );
  }
}

class _BottomAnchoringScrollPosition extends ScrollPositionWithSingleContext {
  _BottomAnchoringScrollPosition({
    required super.physics,
    required super.context,
    required bool Function() shouldAnchor,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
  }) : _shouldAnchor = shouldAnchor;

  final bool Function() _shouldAnchor;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final applied = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    if (!_shouldAnchor()) return applied;
    if (maxScrollExtent <= 0) return applied;
    if ((pixels - maxScrollExtent).abs() <= 1.0) return applied;
    // Correct before paint — no post-frame jump flash.
    correctPixels(maxScrollExtent);
    return true;
  }
}
