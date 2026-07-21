import 'package:flutter/widgets.dart';

/// Absorbs selection long-press / drag on non-text chrome under a parent
/// [SelectionArea].
///
/// Flutter's scrollable selection delegate asserts when a select-word gesture
/// starts in empty padding or an unselectable gap inside a [Scrollable]
/// ([flutter/flutter#115787](https://github.com/flutter/flutter/issues/115787)).
/// Wrapping those regions with [SelectionContainer.disabled] plus an opaque
/// [GestureDetector] that claims `onLongPress` keeps the gesture from entering
/// that broken path.
class SelectionDeadZone extends StatelessWidget {
  const SelectionDeadZone({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {},
        child: child,
      ),
    );
  }
}
