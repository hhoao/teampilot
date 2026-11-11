import 'package:flutter/widgets.dart';

/// Host-injected chrome copy for markdown widgets (package stays l10n-free).
@immutable
class MarkdownStrings {
  const MarkdownStrings({
    required this.copy,
    required this.copied,
    required this.code,
    this.showMore = 'Show more',
    this.showLess = 'Show less',
  });

  final String copy;
  final String copied;
  final String code;
  final String showMore;
  final String showLess;

  static const MarkdownStrings english = MarkdownStrings(
    copy: 'Copy',
    copied: 'Copied',
    code: 'code',
  );

  static MarkdownStrings of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MarkdownStringsScope>()!
        .strings;
  }

  /// Value equality so callers that rebuild the string bundle every frame can
  /// still reuse cached markdown subtrees.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MarkdownStrings &&
        other.copy == copy &&
        other.copied == copied &&
        other.code == code &&
        other.showMore == showMore &&
        other.showLess == showLess;
  }

  @override
  int get hashCode => Object.hash(copy, copied, code, showMore, showLess);
}

/// Provides [MarkdownStrings] to descendant markdown chrome (e.g. code copy).
class MarkdownStringsScope extends InheritedWidget {
  const MarkdownStringsScope({
    required this.strings,
    required super.child,
    super.key,
  });

  final MarkdownStrings strings;

  @override
  bool updateShouldNotify(MarkdownStringsScope oldWidget) =>
      strings.copy != oldWidget.strings.copy ||
      strings.copied != oldWidget.strings.copied ||
      strings.code != oldWidget.strings.code ||
      strings.showMore != oldWidget.strings.showMore ||
      strings.showLess != oldWidget.strings.showLess;
}
