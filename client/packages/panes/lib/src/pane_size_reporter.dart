import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Lays out [child] and reports its size without a [LayoutBuilder] rebuild.
///
/// [onSize] runs in a post-frame callback when the laid-out size changes, so
/// callers can update state without doing widget BUILD during layout.
class PaneSizeReporter extends SingleChildRenderObjectWidget {
  const PaneSizeReporter({
    required this.onSize,
    required Widget super.child,
    super.key,
  });

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPaneSizeReporter(onSize: onSize);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPaneSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class _RenderPaneSizeReporter extends RenderProxyBox {
  _RenderPaneSizeReporter({required this.onSize});

  ValueChanged<Size> onSize;

  Size? _lastReported;
  var _scheduled = false;

  @override
  void performLayout() {
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.biggest;
    }
    final reported = size;
    if (_lastReported == reported) return;
    _lastReported = reported;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      onSize(reported);
    });
  }
}
