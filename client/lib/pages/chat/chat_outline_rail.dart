import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import 'chat_outline.dart';

/// Matches `docs/mocks/zcode-chat.html` `.msg-menu` / `.msg-line`,
/// with slightly longer/thicker bars and a gap from the pane edge.
const double kChatOutlineRailLeftInset = 10;
const double kChatOutlineRailWidth = 44;
const double kChatOutlineMinTickGap = 16;
const double kChatOutlineTickSlop = 16;
const double kChatOutlineBarIdle = 18;
const double kChatOutlineBarPeak = 36;
const double kChatOutlineBarStep = 6;
const double kChatOutlineBarMin = 8;
const double kChatOutlineBarThickness = 3.5;
const double kChatOutlinePeekGap = 12;
const Duration kChatOutlineBarAnim = Duration(milliseconds: 220);
const Duration kChatOutlinePeekAnim = Duration(milliseconds: 180);

const Key kChatOutlineRailKey = ValueKey('chat-outline-rail');
const Key kChatOutlineRailFocusKey = ValueKey('chat-outline-rail-focus');
const Key kChatOutlinePreviewCardKey = ValueKey('chat-outline-preview-card');
const Key kChatOutlineHostKey = ValueKey('chat-outline-host');

double chatOutlineStride({required int count}) {
  if (count <= 0) return 0;
  return kChatOutlineMinTickGap;
}

double chatOutlineTickY({required int index, required int count}) {
  final stride = chatOutlineStride(count: count);
  return stride * index + stride / 2;
}

/// Distance-based bar width: peak, then step down toward [kChatOutlineBarMin].
double chatOutlineBarLength({required int index, int? peakIndex}) {
  if (peakIndex == null) return kChatOutlineBarIdle;
  final dist = (index - peakIndex).abs();
  return math.max(
    kChatOutlineBarMin,
    kChatOutlineBarPeak - dist * kChatOutlineBarStep,
  );
}

double chatOutlineBarOpacity({
  required int index,
  int? peakIndex,
  int? activeIndex,
}) {
  if (peakIndex != null) {
    if (index == peakIndex) return 1;
    return 0.85;
  }
  if (index == activeIndex) return 0.85;
  return 0.55;
}

int? chatOutlineTickAt({
  required Offset local,
  required Size size,
  required int count,
}) {
  if (count <= 0) return null;
  final stride = chatOutlineStride(count: count);
  final blockHeight = stride * count;
  if (local.dx < -kChatOutlineTickSlop ||
      local.dx > size.width + kChatOutlineTickSlop) {
    return null;
  }
  if (local.dy < -kChatOutlineTickSlop ||
      local.dy > blockHeight + kChatOutlineTickSlop) {
    return null;
  }
  final i = (local.dy / stride).floor().clamp(0, count - 1);
  final centerY = stride * i + stride / 2;
  final dy = (local.dy - centerY).abs();
  if (dy > stride / 2 + 0.01) return null;
  return i;
}

class ChatOutlineRail extends StatefulWidget {
  const ChatOutlineRail({
    required this.entries,
    required this.activeId,
    required this.onLocate,
    this.footerBuilder,
    this.semanticLabelFor,
    super.key,
  });

  final List<ChatOutlineEntry> entries;
  final ValueListenable<String?> activeId;
  final ValueChanged<ChatOutlineEntry> onLocate;
  final Widget? Function(BuildContext context, ChatOutlineEntry entry)?
  footerBuilder;
  final String Function(int index, int total)? semanticLabelFor;

  @override
  State<ChatOutlineRail> createState() => _ChatOutlineRailState();
}

class _MoveOutlineIntent extends Intent {
  const _MoveOutlineIntent(this.delta);
  final int delta;
}

class _LocateOutlineIntent extends Intent {
  const _LocateOutlineIntent();
}

class _DismissOutlineIntent extends Intent {
  const _DismissOutlineIntent();
}

class _ChatOutlineRailState extends State<ChatOutlineRail> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final FocusNode _focus = FocusNode(debugLabel: 'chat-outline-rail');
  Timer? _dismissTimer;
  int? _hoverIndex;
  int _focusIndex = 0;
  String? _previewId;
  Size _paintSize = Size.zero;

  @override
  void didUpdateWidget(covariant ChatOutlineRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previewId = _previewId;
    if (previewId != null && !widget.entries.any((e) => e.id == previewId)) {
      _dismissTimer?.cancel();
      _hoverIndex = null;
      _previewId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_overlay.isShowing) _overlay.hide();
      });
    }
    if (_focusIndex >= widget.entries.length) {
      _focusIndex = widget.entries.isEmpty ? 0 : widget.entries.length - 1;
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  ChatOutlineEntry? _entryById(String? id) {
    if (id == null) return null;
    for (final e in widget.entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _showPreview(int index, {bool fromHover = true}) {
    if (index < 0 || index >= widget.entries.length) return;
    _dismissTimer?.cancel();
    setState(() {
      if (fromHover) _hoverIndex = index;
      _focusIndex = index;
      _previewId = widget.entries[index].id;
    });
    if (!_overlay.isShowing) _overlay.show();
  }

  void _scheduleHide() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) _hidePreview();
    });
  }

  void _hidePreview({bool clearHover = true}) {
    _dismissTimer?.cancel();
    if (_overlay.isShowing) _overlay.hide();
    if (!mounted) return;
    setState(() {
      if (clearHover) _hoverIndex = null;
      _previewId = null;
    });
  }

  void _locate(ChatOutlineEntry entry, {bool keepHover = false}) {
    widget.onLocate(entry);
    // Preview closes on locate. Hover is pointer-owned: MouseRegion does not
    // re-fire onHover until the cursor moves, so clearing it here would leave
    // the rail idle until the next mouse move.
    _hidePreview(clearHover: !keepHover);
    if (!keepHover) _focus.unfocus();
  }

  void _moveFocus(int delta) {
    if (widget.entries.isEmpty) return;
    final next = (_focusIndex + delta).clamp(0, widget.entries.length - 1);
    _showPreview(next, fromHover: false);
  }

  void _locateFocused() {
    if (_focusIndex >= 0 && _focusIndex < widget.entries.length) {
      _locate(widget.entries[_focusIndex]);
    }
  }

  void _onHover(Offset local, Size size) {
    final i = chatOutlineTickAt(
      local: local,
      size: size,
      count: widget.entries.length,
    );
    if (i == null) return;
    _showPreview(i);
  }

  void _onTapAt(Offset local, Size size) {
    final i = chatOutlineTickAt(
      local: local,
      size: size,
      count: widget.entries.length,
    );
    if (i == null) return;
    _locate(widget.entries[i], keepHover: true);
  }

  Widget _buildOverlay(BuildContext context) {
    final entry = _entryById(_previewId);
    if (entry == null) return const SizedBox.shrink();
    final index = widget.entries.indexWhere((e) => e.id == entry.id);
    final tickY = index < 0
        ? 0.0
        : chatOutlineTickY(index: index, count: widget.entries.length);
    final cs = Theme.of(context).colorScheme;
    final footer = widget.footerBuilder?.call(context, entry);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ExcludeFocus(
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.centerLeft,
        offset: Offset(kChatOutlineRailWidth + kChatOutlinePeekGap, tickY),
        child: UnconstrainedBox(
          alignment: Alignment.centerLeft,
          child: MouseRegion(
            onEnter: (_) => _dismissTimer?.cancel(),
            onExit: (_) => _scheduleHide(),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(entry.id),
              tween: Tween(begin: reduce ? 1 : 0, end: 1),
              duration: reduce ? Duration.zero : kChatOutlinePeekAnim,
              curve: Curves.ease,
              builder: (context, t, child) {
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(-6 * (1 - t), 0),
                    child: child,
                  ),
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 32,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Material(
                  key: kChatOutlinePreviewCardKey,
                  color: cs.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.9),
                    ),
                  ),
                  child: InkWell(
                    canRequestFocus: false,
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _locate(entry),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.preview,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TpTextStyles.of(context).sm,
                            ),
                            if (footer != null) footer,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final semanticIndex = (_hoverIndex ?? _focusIndex) + 1;
    final semanticLabel = widget.semanticLabelFor?.call(
      semanticIndex,
      widget.entries.length,
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          key: kChatOutlineRailKey,
          width: kChatOutlineRailWidth,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowDown): _MoveOutlineIntent(
                1,
              ),
              SingleActivator(LogicalKeyboardKey.arrowUp): _MoveOutlineIntent(
                -1,
              ),
              SingleActivator(LogicalKeyboardKey.enter): _LocateOutlineIntent(),
              SingleActivator(LogicalKeyboardKey.escape):
                  _DismissOutlineIntent(),
            },
            child: Actions(
              actions: {
                _MoveOutlineIntent: CallbackAction<_MoveOutlineIntent>(
                  onInvoke: (intent) {
                    _moveFocus(intent.delta);
                    return null;
                  },
                ),
                _LocateOutlineIntent: CallbackAction<_LocateOutlineIntent>(
                  onInvoke: (_) {
                    _locateFocused();
                    return null;
                  },
                ),
                _DismissOutlineIntent: CallbackAction<_DismissOutlineIntent>(
                  onInvoke: (_) {
                    _hidePreview();
                    _focus.unfocus();
                    return null;
                  },
                ),
              },
              child: Focus(
                key: kChatOutlineRailFocusKey,
                focusNode: _focus,
                skipTraversal: true,
                descendantsAreFocusable: false,
                descendantsAreTraversable: false,
                onFocusChange: (hasFocus) {
                  if (!hasFocus) _hidePreview();
                },
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.arrowDown) {
                    _moveFocus(1);
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowUp) {
                    _moveFocus(-1);
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.enter) {
                    _locateFocused();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.escape) {
                    _hidePreview();
                    _focus.unfocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: CompositedTransformTarget(
                  link: _link,
                  child: OverlayPortal(
                    controller: _overlay,
                    overlayChildBuilder: _buildOverlay,
                    child: ValueListenableBuilder<String?>(
                      valueListenable: widget.activeId,
                      builder: (context, activeId, _) {
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final count = widget.entries.length;
                            final viewportH = constraints.maxHeight;
                            final paintHeight = count * kChatOutlineMinTickGap;
                            final needsScroll =
                                viewportH.isFinite && paintHeight > viewportH;
                            _paintSize = Size(
                              kChatOutlineRailWidth,
                              paintHeight,
                            );
                            final menu = _MsgMenu(
                              count: count,
                              peakIndex: _hoverIndex,
                              activeIndex: _indexOfId(activeId),
                              barColor: cs.onSurfaceVariant,
                              reduceMotion: MediaQuery.disableAnimationsOf(
                                context,
                              ),
                              onHover: (local) => _onHover(local, _paintSize),
                              onExit: _scheduleHide,
                              onTap: (local) => _onTapAt(local, _paintSize),
                              onLongPress: (local) {
                                _focus.requestFocus();
                                final i = chatOutlineTickAt(
                                  local: local,
                                  size: _paintSize,
                                  count: count,
                                );
                                if (i != null) _showPreview(i);
                              },
                            );
                            if (needsScroll) {
                              return SingleChildScrollView(child: menu);
                            }
                            return menu;
                          },
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
    );
  }

  int? _indexOfId(String? id) {
    if (id == null) return null;
    final i = widget.entries.indexWhere((e) => e.id == id);
    return i < 0 ? null : i;
  }
}

class ChatOutlineHost extends StatelessWidget {
  const ChatOutlineHost({
    required this.show,
    required this.entries,
    required this.activeId,
    required this.onLocate,
    this.footerBuilder,
    this.semanticLabelFor,
    super.key,
  });

  final bool show;
  final List<ChatOutlineEntry> entries;
  final ValueListenable<String?> activeId;
  final ValueChanged<ChatOutlineEntry> onLocate;
  final Widget? Function(BuildContext context, ChatOutlineEntry entry)?
  footerBuilder;
  final String Function(int index, int total)? semanticLabelFor;

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Positioned(
      key: kChatOutlineHostKey,
      left: kChatOutlineRailLeftInset,
      top: 0,
      bottom: 0,
      width: kChatOutlineRailWidth,
      child: ChatOutlineRail(
        entries: entries,
        activeId: activeId,
        onLocate: onLocate,
        footerBuilder: footerBuilder,
        semanticLabelFor: semanticLabelFor,
      ),
    );
  }
}

class _MsgMenu extends StatelessWidget {
  const _MsgMenu({
    required this.count,
    required this.peakIndex,
    required this.activeIndex,
    required this.barColor,
    required this.reduceMotion,
    required this.onHover,
    required this.onExit,
    required this.onTap,
    required this.onLongPress,
  });

  final int count;
  final int? peakIndex;
  final int? activeIndex;
  final Color barColor;
  final bool reduceMotion;
  final ValueChanged<Offset> onHover;
  final VoidCallback onExit;
  final ValueChanged<Offset> onTap;
  final ValueChanged<Offset> onLongPress;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion ? Duration.zero : kChatOutlineBarAnim;
    return SizedBox(
      width: kChatOutlineRailWidth,
      height: count * kChatOutlineMinTickGap,
      child: MouseRegion(
        onHover: (e) {
          if (e.kind != PointerDeviceKind.mouse) return;
          onHover(e.localPosition);
        },
        onExit: (_) => onExit(),
        child: Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerHover: (e) {
            if (e.kind != PointerDeviceKind.mouse) return;
            onHover(e.localPosition);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (d) => onTap(d.localPosition),
            onLongPressStart: (d) => onLongPress(d.localPosition),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(
                    width: kChatOutlineRailWidth,
                    height: kChatOutlineMinTickGap,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: duration,
                        curve: Curves.ease,
                        width: chatOutlineBarLength(
                          index: i,
                          peakIndex: peakIndex,
                        ),
                        height: kChatOutlineBarThickness,
                        decoration: BoxDecoration(
                          color: barColor.withValues(
                            alpha: chatOutlineBarOpacity(
                              index: i,
                              peakIndex: peakIndex,
                              activeIndex: activeIndex,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
