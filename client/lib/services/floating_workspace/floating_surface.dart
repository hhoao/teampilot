import 'package:flutter/material.dart';

import 'package:teampilot/cubits/floating_workspace/floating_workspace_state.dart';

class FloatingEmptyAction {
  const FloatingEmptyAction({
    required this.commandId,
    required this.labelKey,
    required this.icon,
  });

  final String commandId;
  final String labelKey;
  final IconData icon;
}

abstract class FloatingSurface {
  String get id;
  FloatingEmptyAction? get emptyAction;
  bool get allowMultipleTabs;
  FloatingTab createTab({required String workspaceId, Object? payload});
  Widget build(BuildContext context, FloatingTab tab);
  Future<void> activate(FloatingTab tab);
  Future<bool> canClose(FloatingTab tab) async => true;
  void onTabClosed(FloatingTab tab) {}
  Stream<bool>? get attentionWhileMinimized => null;
}
