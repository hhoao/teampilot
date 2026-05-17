import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/connection_mode.dart';
import '../models/layout_preferences.dart';

ConnectionMode defaultConnectionMode() {
  if (Platform.isAndroid) return ConnectionMode.ssh;
  return ConnectionMode.localPty;
}

bool get requiresSshProfile => Platform.isAndroid;

/// On narrow/mobile layouts the right tools panel is hidden from the split
/// view and exposed via [Scaffold.endDrawer] instead.
bool useRightToolsAsDrawer(BuildContext context) => Platform.isAndroid;

/// Hub landing + pushed section pages instead of a side-by-side workspace shell.
bool useAndroidHubNavigation(BuildContext context) => Platform.isAndroid;

@Deprecated('Use useAndroidHubNavigation')
bool useAndroidConfigNavigation(BuildContext context) =>
    useAndroidHubNavigation(context);

double rightToolsDrawerWidth(
  BuildContext context,
  LayoutPreferences preferences,
) {
  final maxWidth = MediaQuery.sizeOf(context).width;
  return preferences.rightToolsWidth.clamp(
    LayoutPreferences.minRightToolsWidth,
    math.min(LayoutPreferences.maxRightToolsWidth, maxWidth * 0.9),
  );
}
