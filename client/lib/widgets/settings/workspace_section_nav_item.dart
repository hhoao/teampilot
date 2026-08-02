import 'package:flutter/material.dart';

class WorkspaceSectionNavItem {
  const WorkspaceSectionNavItem({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final IconData? icon; // wide left nav only
}
