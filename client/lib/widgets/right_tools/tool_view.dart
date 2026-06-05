import 'package:flutter/widgets.dart';

/// One selectable view in the right tools switcher: an icon + tooltip label,
/// its content, and an optional badge count (e.g. mailbox unread).
class ToolView {
  const ToolView({
    required this.icon,
    required this.label,
    required this.child,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final int badgeCount;
}
