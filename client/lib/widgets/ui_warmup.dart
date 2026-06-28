import 'package:flutter/material.dart';

/// Formerly warmed fonts, glyphs, and the terminal engine on the first main-ui
/// frame (blocking interaction). That work now runs in [UiInteractiveWarmup]
/// during the boot gate; this widget is a pass-through.
class UiWarmup extends StatelessWidget {
  const UiWarmup({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
