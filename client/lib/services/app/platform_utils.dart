import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/connection_mode.dart';

ConnectionMode defaultConnectionMode() {
  if (Platform.isAndroid) return ConnectionMode.ssh;
  return ConnectionMode.localPty;
}

/// Linux / Windows / macOS window chrome; false on Android.
bool get useCustomDesktopWindowTitleBar => !Platform.isAndroid;

/// Desktop undoes OS display scaling via `1/dpr` in [autoUiZoomForDevicePixelRatio]
/// / [autoTextScaleForSystem]. Android/iOS already use density-independent
/// logical pixels — leave baseline at 1.0 instead of compensating again.
bool get usesDesktopDisplayScalingCompensation =>
    !Platform.isAndroid && !Platform.isIOS;

/// macOS uses left-aligned traffic-light window controls instead of the
/// Windows-style buttons on the right.
bool get useMacWindowChromeStyle =>
    useCustomDesktopWindowTitleBar && Platform.isMacOS;

@Deprecated('Use ConnectionModeService.requiresSshProfileSetup')
bool get requiresSshProfile => Platform.isAndroid;

/// Hub landing + pushed section pages instead of a side-by-side workspace shell.
bool useAndroidHubNavigation(BuildContext context) => Platform.isAndroid;

/// Closes the mobile [TpSidebar] overlay after a sidebar navigation action.
void closeAndroidDrawerIfOpen(BuildContext context) {
  final scope = TpSidebarScope.maybeOf(context);
  if (scope != null && scope.openMobile) {
    scope.setOpenMobile(false);
  }
}

/// [GoRouter.go] from the navigation sidebar and dismiss the mobile drawer.
void goFromSidebar(BuildContext context, String path) {
  closeAndroidDrawerIfOpen(context);
  context.go(path);
}

/// Hub section navigation: push on Android hub flow, go on desktop split shell.
void navigateWorkspaceRoute(BuildContext context, String path) {
  if (useAndroidHubNavigation(context)) {
    context.push(path);
  } else {
    context.go(path);
  }
}

@Deprecated('Use useAndroidHubNavigation')
bool useAndroidConfigNavigation(BuildContext context) =>
    useAndroidHubNavigation(context);
