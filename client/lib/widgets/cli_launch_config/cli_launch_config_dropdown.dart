import 'package:flutter/material.dart';

import 'cli_launch_config_tokens.dart';

Widget cliLaunchConfigDropdown(Widget child) {
  return ConstrainedBox(
    constraints: const BoxConstraints(
      minWidth: CliLaunchConfigTokens.dropdownMinWidth,
    ),
    child: child,
  );
}
