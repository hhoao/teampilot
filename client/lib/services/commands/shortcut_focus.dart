import 'package:flutter/widgets.dart';

/// Kind of shortcut-relevant focus target that a [ShortcutFocus] ancestor
/// marks its subtree with.
///
/// Consumed by the live [ShortcutContext] builder (Task 6) to classify
/// [FocusManager.instance.primaryFocus] into `inCompose` / `inTerminal` /
/// `inTextInput` without every feature widget needing to know about the
/// shortcut platform.
enum ShortcutFocusKind { compose, terminal, text }

/// Marks the nearest focusable descendant (compose field, terminal view,
/// text input) with a [ShortcutFocusKind] so the context builder can look it
/// up from a [FocusNode]'s `context` without a static/global registry.
///
/// Wrap the focusable widget itself (or its direct parent) — the lookup in
/// [maybeOf] intentionally does not establish a build dependency since it is
/// called from outside `build()` (on every key event).
class ShortcutFocus extends InheritedWidget {
  const ShortcutFocus({super.key, required this.kind, required super.child});

  final ShortcutFocusKind kind;

  /// Returns the nearest [ShortcutFocus] ancestor's kind visible from
  /// [context], or `null` if [context] is not under a [ShortcutFocus].
  ///
  /// Uses [BuildContext.getElementForInheritedWidgetOfExactType] rather than
  /// `dependOnInheritedWidgetOfExactType` so calling this outside `build()`
  /// (e.g. from a [FocusNode.context] on every key event) does not register a
  /// spurious rebuild dependency.
  static ShortcutFocus? maybeOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<ShortcutFocus>();
    return element?.widget as ShortcutFocus?;
  }

  @override
  bool updateShouldNotify(ShortcutFocus oldWidget) => kind != oldWidget.kind;
}
