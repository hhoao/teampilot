import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import 'chat_outline.dart';

const double kChatOutlineRailWidth = 20;
const double kChatOutlineMinTickGap = 10;
const double kChatOutlineTickSlop = 16;

const Key kChatOutlineRailKey = ValueKey('chat-outline-rail');
const Key kChatOutlineRailFocusKey = ValueKey('chat-outline-rail-focus');
const Key kChatOutlinePreviewCardKey = ValueKey('chat-outline-preview-card');
const Key kChatOutlineHostKey = ValueKey('chat-outline-host');

double chatOutlineStride({required double height, required int count}) {
  if (count <= 0) return 0;
  return math.max(kChatOutlineMinTickGap, height / count);
}

int? chatOutlineTickAt({
  required Offset local,
  required Size size,
  required int count,
}) {
  if (count <= 0) return null;
  final stride = chatOutlineStride(height: size.height, count: count);
  final i = (local.dy / stride).floor().clamp(0, count - 1);
  final centerY = stride * i + stride / 2;
  final dx = (local.dx - size.width / 2).abs();
  final dy = (local.dy - centerY).abs();
  if (dy > kChatOutlineTickSlop && dx > kChatOutlineTickSlop) return null;
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
  String? _locatedId;
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
      _focusIndex = math.max(0, widget.entries.length - 1);
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

  void _showPreview(int index) {
    if (index < 0 || index >= widget.entries.length) return;
    _dismissTimer?.cancel();
    setState(() {
      _hoverIndex = index;
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

  void _hidePreview() {
    _dismissTimer?.cancel();
    if (_overlay.isShowing) _overlay.hide();
    if (!mounted) return;
    setState(() {
      _hoverIndex = null;
      _previewId = null;
    });
  }

  void _locate(ChatOutlineEntry entry) {
    _locatedId = entry.id;
    widget.onLocate(entry);
    _hidePreview();
  }

  void _moveFocus(int delta) {
    if (widget.entries.isEmpty) return;
    final next = (_focusIndex + delta).clamp(0, widget.entries.length - 1);
    _showPreview(next);
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
    _focus.requestFocus();
    final i = chatOutlineTickAt(
      local: local,
      size: size,
      count: widget.entries.length,
    );
    if (i == null) return;
    _locate(widget.entries[i]);
  }

  Widget _buildOverlay(BuildContext context) {
    final entry = _entryById(_previewId);
    if (entry == null) return const SizedBox.shrink();
    final index = widget.entries.indexWhere((e) => e.id == entry.id);
    final stride = chatOutlineStride(
      height: _paintSize.height,
      count: widget.entries.length,
    );
    final tickY = index < 0 ? 0.0 : stride * index + stride / 2;
    final cs = Theme.of(context).colorScheme;
    final footer = widget.footerBuilder?.call(context, entry);
    return ExcludeFocus(
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.topLeft,
        offset: Offset(kChatOutlineRailWidth + 4, tickY - 18),
        child: Align(
          alignment: Alignment.topLeft,
          child: MouseRegion(
            onEnter: (_) => _dismissTimer?.cancel(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              key: kChatOutlinePreviewCardKey,
              elevation: 2,
              color: cs.surface,
              shadowColor: cs.shadow,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                canRequestFocus: false,
                onTap: () => _locate(entry),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                            final needsScroll =
                                count * kChatOutlineMinTickGap > viewportH;
                            final paintHeight = needsScroll
                                ? count * kChatOutlineMinTickGap
                                : viewportH;
                            _paintSize = Size(
                              kChatOutlineRailWidth,
                              paintHeight,
                            );
                            final activeIndex = _indexOfId(activeId);
                            final locatedIndex = _indexOfId(_locatedId);
                            final emphasized =
                                _hoverIndex ??
                                (_focus.hasFocus ? _focusIndex : null);
                            final paint = _TickHitTarget(
                              count: count,
                              child: Listener(
                                behavior: HitTestBehavior.deferToChild,
                                onPointerHover: (e) {
                                  if (e.kind != PointerDeviceKind.mouse) {
                                    return;
                                  }
                                  _onHover(e.localPosition, _paintSize);
                                },
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapDown: (d) =>
                                      _onTapAt(d.localPosition, _paintSize),
                                  onLongPressStart: (d) {
                                    _focus.requestFocus();
                                    final i = chatOutlineTickAt(
                                      local: d.localPosition,
                                      size: _paintSize,
                                      count: count,
                                    );
                                    if (i != null) _showPreview(i);
                                  },
                                  child: MouseRegion(
                                    onHover: (e) {
                                      if (e.kind != PointerDeviceKind.mouse) {
                                        return;
                                      }
                                      _onHover(e.localPosition, _paintSize);
                                    },
                                    onExit: (_) => _scheduleHide(),
                                    child: CustomPaint(
                                      size: Size(
                                        kChatOutlineRailWidth,
                                        paintHeight,
                                      ),
                                      painter: _ChatOutlineRailPainter(
                                        count: count,
                                        emphasizedIndex: emphasized,
                                        activeIndex: activeIndex,
                                        locatedIndex: locatedIndex,
                                        trackColor: cs.onSurfaceVariant
                                            .withValues(alpha: 0.35),
                                        tickColor: cs.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                        emphasisColor: cs.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                            if (needsScroll) {
                              return SingleChildScrollView(
                                child: SizedBox(
                                  height: paintHeight,
                                  child: paint,
                                ),
                              );
                            }
                            return paint;
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
      left: 0,
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

class _TickHitTarget extends SingleChildRenderObjectWidget {
  const _TickHitTarget({required this.count, super.child});

  final int count;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _TickHitRender(count: count);
  }

  @override
  void updateRenderObject(BuildContext context, _TickHitRender renderObject) {
    renderObject.count = count;
  }
}

class _TickHitRender extends RenderProxyBox {
  _TickHitRender({required int count}) : _count = count;

  int _count;
  set count(int value) {
    if (_count == value) return;
    _count = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (chatOutlineTickAt(local: position, size: size, count: _count) == null) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

class _ChatOutlineRailPainter extends CustomPainter {
  _ChatOutlineRailPainter({
    required this.count,
    required this.emphasizedIndex,
    required this.activeIndex,
    required this.locatedIndex,
    required this.trackColor,
    required this.tickColor,
    required this.emphasisColor,
  });

  final int count;
  final int? emphasizedIndex;
  final int? activeIndex;
  final int? locatedIndex;
  final Color trackColor;
  final Color tickColor;
  final Color emphasisColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) return;
    final cx = size.width / 2;
    final stride = chatOutlineStride(height: size.height, count: count);
    final track = Paint()
      ..color = trackColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), track);
    for (var i = 0; i < count; i++) {
      final y = stride * i + stride / 2;
      final strong =
          i == emphasizedIndex || i == activeIndex || i == locatedIndex;
      final half = strong ? 6.0 : 3.5;
      final paint = Paint()
        ..color = i == emphasizedIndex
            ? emphasisColor
            : (strong ? emphasisColor.withValues(alpha: 0.85) : tickColor)
        ..strokeWidth = strong ? 1.5 : 1;
      canvas.drawLine(Offset(cx - half, y), Offset(cx + half, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChatOutlineRailPainter old) {
    return old.count != count ||
        old.emphasizedIndex != emphasizedIndex ||
        old.activeIndex != activeIndex ||
        old.locatedIndex != locatedIndex ||
        old.trackColor != trackColor ||
        old.tickColor != tickColor ||
        old.emphasisColor != emphasisColor;
  }
}
