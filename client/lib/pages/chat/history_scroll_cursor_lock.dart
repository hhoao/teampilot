import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// When [active], forces [SystemMouseCursors.basic] over the subtree without
/// absorbing pointer events (descendants still receive hit tests / gestures).
///
/// Used by History while scrolling so text/click cursors do not flicker as
/// content moves under a stationary pointer.
class HistoryScrollCursorLock extends SingleChildRenderObjectWidget {
  const HistoryScrollCursorLock({
    required this.active,
    required Widget child,
    super.key,
  }) : super(child: child);

  final bool active;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderHistoryScrollCursorLock(active: active);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHistoryScrollCursorLock renderObject,
  ) {
    renderObject.active = active;
  }
}

class RenderHistoryScrollCursorLock extends RenderProxyBox
    implements MouseTrackerAnnotation {
  RenderHistoryScrollCursorLock({required bool active}) : _active = active;

  bool get active => _active;
  bool _active;
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    // Cursor candidates are recomputed on the next mouse tracker pass.
    markNeedsPaint();
  }

  @override
  MouseCursor get cursor =>
      _active ? SystemMouseCursors.basic : MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  @override
  bool get validForMouseTracker => true;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    // Insert our annotation first so cursor resolution prefers basic while
    // still hit-testing children (gestures keep working).
    if (_active) {
      result.add(BoxHitTestEntry(this, position));
    }
    final hitChild = hitTestChildren(result, position: position);
    return hitChild || _active;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty('active', value: _active, ifTrue: 'active'));
  }
}
