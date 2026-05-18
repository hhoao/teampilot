import 'dart:io';
import 'package:flutter/material.dart';

class WorkspaceDrawer extends StatelessWidget {
  const WorkspaceDrawer({
    super.key,
    required this.child,
    required this.drawerContent,
    this.appBarTitle = 'FlashSkyAI',
    this.appBarActions = const [],
  });

  final Widget child;
  final Widget drawerContent;
  final String appBarTitle;
  final List<Widget> appBarActions;

  static bool get isNarrowScreen {
    if (Platform.isAndroid) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!isNarrowScreen) {
      return child;
    }

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle), actions: appBarActions),
      drawer: Drawer(child: SafeArea(child: drawerContent)),
      body: child,
    );
  }
}
