import 'package:flutter/material.dart';

import '../../theme/app_icon_sizes.dart';
import '../../theme/app_outline_input_theme.dart';

/// Off-screen [TextField] matching the workspace file-tree filter row.
///
/// [TextPainter] glyph warmup does not touch [RenderEditable]; [UiWarmup] lays
/// this out off-screen during the boot splash (after [HomeShell] mounts) so the
/// first real filter field avoids cold [RenderEditable] layout.
class WorkspaceSearchFieldWarmup extends StatelessWidget {
  const WorkspaceSearchFieldWarmup({super.key});

  static const fieldWidth = 320.0;
  static const fieldHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'a',
          prefixIcon: Icon(
            Icons.search,
            size: context.appIconSizes.md,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.never,
        ),
        style: appTextFieldStyle(Theme.of(context).textTheme),
      ),
    );
  }
}
