import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/app/app_text_field_warmup.dart';
import '../utils/yield_ui_frame.dart';

/// Mounts canonical [TextField] profiles off-screen as soon as [MaterialApp]
/// provides production [ThemeData] — before [HomeShell] — so
/// [RenderEditable] cold layout stays under the boot splash.
class AppTextFieldWarmupHost extends StatefulWidget {
  const AppTextFieldWarmupHost({required this.child, super.key});

  final Widget child;

  @override
  State<AppTextFieldWarmupHost> createState() => _AppTextFieldWarmupHostState();
}

class _AppTextFieldWarmupHostState extends State<AppTextFieldWarmupHost> {
  var _profileIndex = -1;

  static bool get _inTest {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } on Object {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_inTest || AppTextFieldWarmup.isReady) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_runWarmup());
    });
  }

  Future<void> _runWarmup() async {
    final profiles = AppTextFieldWarmup.profiles;
    for (var i = 0; i < profiles.length; i++) {
      if (!mounted) return;
      setState(() => _profileIndex = i);
      await yieldUiFrame();
      await yieldUiFrame();
    }
    if (!mounted) return;
    setState(() => _profileIndex = -1);
    AppTextFieldWarmup.markReady();
  }

  @override
  Widget build(BuildContext context) {
    if (_profileIndex < 0) return widget.child;

    final index = _profileIndex;
    final height = index == AppTextFieldWarmup.profiles.length - 1
        ? AppTextFieldWarmup.multilineHeight
        : AppTextFieldWarmup.singleLineHeight;

    return Stack(
      clipBehavior: Clip.hardEdge,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned(
          left: -AppTextFieldWarmup.fieldWidth - 64,
          top: 0,
          width: AppTextFieldWarmup.fieldWidth,
          height: height,
          child: IgnorePointer(
            child: AppTextFieldWarmup.profiles[index](context),
          ),
        ),
      ],
    );
  }
}
