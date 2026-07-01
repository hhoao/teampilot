import 'package:flutter/material.dart';

const _dropdownMinWidth = 180.0;

Widget cliLaunchConfigDropdown(Widget child) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: _dropdownMinWidth),
    child: child,
  );
}
