import 'package:flutter/widgets.dart';

/// Uniformly scales the entire UI subtree by [scale] — the app-owned "Interface
/// scale" / zoom level.
///
/// Unlike text-only scaling, this scales fonts, icons, padding, and every
/// control together so the whole interface gets denser or roomier as one unit,
/// the same model a desktop app's zoom uses. It lets the app own its density
/// independent of the OS display-scaling ([MediaQuery.devicePixelRatio]), so
/// Linux/Windows/macOS can present one consistent layout.
///
/// Mechanics: the child is laid out into a logical canvas of `size / scale`
/// (via [OverflowBox]), then painted back down with a [Transform.scale]. The
/// [MediaQuery] metrics are rewritten to that rescaled canvas so descendants
/// lay out responsively against the real space, and pointer hit-testing stays
/// correct (Transform hit-tests are transformed by default).
///
/// At [scale] `1.0` this is a pass-through (no extra widgets inserted).
class UiZoom extends StatelessWidget {
  const UiZoom({required this.scale, required this.child, super.key});

  /// Multiplier applied to the whole UI. `1.0` = native size; `< 1.0` denser
  /// (zoom out); `> 1.0` roomier (zoom in).
  final double scale;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child;
    final mq = MediaQuery.of(context);
    final size = mq.size;
    if (size.isEmpty) return child;

    final inverse = 1 / scale;
    final scaledSize = Size(size.width * inverse, size.height * inverse);

    return Transform.scale(
      scale: scale,
      alignment: Alignment.topLeft,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: scaledSize.width,
        maxWidth: scaledSize.width,
        minHeight: scaledSize.height,
        maxHeight: scaledSize.height,
        child: MediaQuery(
          data: mq.copyWith(
            size: scaledSize,
            padding: mq.padding * inverse,
            viewPadding: mq.viewPadding * inverse,
            viewInsets: mq.viewInsets * inverse,
          ),
          child: SizedBox.fromSize(size: scaledSize, child: child),
        ),
      ),
    );
  }
}
