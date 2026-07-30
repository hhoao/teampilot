import 'package:flutter/material.dart';

/// Visual metrics aligned with Orca's floating-workspace trigger
/// (`FloatingTerminalToggleButton`: 36px, `rounded-lg`, right 24 / bottom 72).
const double kFloatingWorkspaceToggleSize = 36;
const double kFloatingWorkspaceToggleRadius = 8;
const double kFloatingWorkspaceToggleIconSize = 16;
const double kFloatingWorkspaceToggleDefaultRight = 24;
const double kFloatingWorkspaceToggleDefaultBottom = 72;

/// Stored as negative bottom-right insets (same convention as cubit state).
const Offset kFloatingWorkspaceToggleDefaultOffset = Offset(
  -kFloatingWorkspaceToggleDefaultRight,
  -kFloatingWorkspaceToggleDefaultBottom,
);

/// Gap between panel bottom and toggle top when auto-placing the panel.
const double kFloatingWorkspacePanelToggleGap = 12;
