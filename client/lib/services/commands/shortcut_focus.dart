import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';

import 'key_chord.dart';

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
///
/// [claims] lets a surface declare that it owns certain [KeyChord]s while its
/// subtree has focus; the live [ShortcutContext] unions `claims` over every
/// [ShortcutFocus] ancestor of the primary focus and [KeybindingResolver.match]
/// skips a global command whose chord is claimed (the surface's own `Shortcuts`
/// is the single handler for it).
class ShortcutFocus extends InheritedWidget {
  const ShortcutFocus({
    this.kind,
    this.claims = const {},
    required super.child,
    super.key,
  });

  /// Null when the surface only claims chords and does not change the
  /// `inCompose` / `inTerminal` / `inTextInput` classification (e.g. the
  /// code editor wrapper).
  final ShortcutFocusKind? kind;

  /// Chords this surface owns while its subtree has focus. A global command
  /// whose chord is claimed is skipped by [KeybindingResolver.match]; the
  /// surface's own `Shortcuts` is the single handler for it.
  final Set<KeyChord> claims;

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

  /// Union of [claims] over every [ShortcutFocus] ancestor of [context]
  /// (nearest → root). Called outside build() on every key event, so it must
  /// not register a rebuild dependency.
  static Set<KeyChord> claimsOf(BuildContext context) {
    final result = <KeyChord>{};
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is ShortcutFocus) result.addAll(widget.claims);
      return true;
    });
    return result;
  }

  @override
  bool updateShouldNotify(ShortcutFocus oldWidget) =>
      kind != oldWidget.kind || !setEquals(claims, oldWidget.claims);
}
