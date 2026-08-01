import 'package:flutter/widgets.dart';

/// Host-injected chrome copy for markdown widgets (package stays l10n-free).
@immutable
class MarkdownStrings {
  const MarkdownStrings({
    required this.copy,
    required this.copied,
    required this.code,
  });

  final String copy;
  final String copied;
  final String code;

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
      strings.code != oldWidget.strings.code;
}
