import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../theme/workspace_surface_layers.dart';

/// Defers the heavy workspace page so Frame 0 paints empty card chrome only.
///
/// Used by [HomeWorkspaceBodyStack] tab slots. [retainWhenInactive] keeps the
/// page mounted after the first reveal so tab switches do not re-defer.
class WorkspaceTabDeferredMount extends StatelessWidget {
  const WorkspaceTabDeferredMount({
    required this.active,
    required this.builder,
    super.key,
  });

  final bool active;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return TpDeferredForegroundMount(
      active: active,
      retainWhenInactive: true,
      placeholder: const WorkspacePageCardShell(
        chrome: WorkspacePageChrome.workspace,
        child: SizedBox.expand(),
      ),
      builder: builder,
    );
  }
}
