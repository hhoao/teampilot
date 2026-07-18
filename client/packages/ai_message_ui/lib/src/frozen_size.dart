import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// When [frozen], reports [frozenHeight] and skips child layout/paint so an
/// offstage Element cache does not pay markdown layout every frame.
class FrozenSize extends SingleChildRenderObjectWidget {
  const FrozenSize({
    required this.frozen,
    required this.frozenHeight,
    required super.child,
    super.key,
  });

  final bool frozen;
  final double? frozenHeight;

  @override
  RenderFrozenSize createRenderObject(BuildContext context) {
    return RenderFrozenSize(frozen: frozen, frozenHeight: frozenHeight);
  }

  @override
  void updateRenderObject(BuildContext context, RenderFrozenSize renderObject) {
    renderObject
      ..frozen = frozen
      ..frozenHeight = frozenHeight;
  }
}

class RenderFrozenSize extends RenderProxyBox {
  RenderFrozenSize({required bool frozen, required double? frozenHeight})
      : _frozen = frozen,
        _frozenHeight = frozenHeight;

  bool _frozen;
  bool get frozen => _frozen;
  set frozen(bool value) {
    if (_frozen == value) return;
    _frozen = value;
    markNeedsLayout();
    markNeedsPaint();
  }

  double? _frozenHeight;
  double? get frozenHeight => _frozenHeight;
  set frozenHeight(double? value) {
    if (_frozenHeight == value) return;
    _frozenHeight = value;
    if (_frozen) markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_frozen && _frozenHeight != null) {
      final w = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : constraints.constrainWidth(0);
      size = constraints.constrain(Size(w, _frozenHeight!));
      return;
    }
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_frozen) return;
    super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_frozen) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_frozen) return;
    super.visitChildrenForSemantics(visitor);
  }
}
