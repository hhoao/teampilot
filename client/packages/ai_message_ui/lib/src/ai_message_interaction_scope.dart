import 'package:flutter/widgets.dart';

/// Interaction state shared by every message in a thread.
///
/// Rewind/fork availability changes while the message list instance stays the
/// same. Passing it through an inherited scope lets cached turn bodies rebuild
/// their action bars without invalidating the whole viewport cache.
class AiMessageInteractionScope extends InheritedWidget {
  const AiMessageInteractionScope({
    required this.rewindForkEnabled,
    required super.child,
    super.key,
  });

  /// When false, edit/fork/version controls stay visible but are disabled.
  final bool rewindForkEnabled;

  static AiMessageInteractionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AiMessageInteractionScope>();

  /// Nearest scope's value, or null when the host did not provide one.
  static bool? maybeRewindEnabled(BuildContext context) =>
      maybeOf(context)?.rewindForkEnabled;

  @override
  bool updateShouldNotify(AiMessageInteractionScope oldWidget) =>
      oldWidget.rewindForkEnabled != rewindForkEnabled;
}
