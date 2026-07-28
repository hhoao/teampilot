import 'package:flutter/material.dart';

import '../../services/workspace_dnd/workspace_drop_target.dart';
import '../workspace_dnd/external_file_drop_region.dart';
import '../workspace_dnd/workspace_file_drop_region.dart';

/// Compose-card drop surface: OS files + in-app file-tree drags.
class ComposeFileDropRegion extends StatelessWidget {
  const ComposeFileDropRegion({
    required this.target,
    required this.child,
    this.onOutcome,
    super.key,
  });

  final WorkspaceDropTarget target;
  final Widget child;
  final ValueChanged<DropOutcome>? onOutcome;

  @override
  Widget build(BuildContext context) {
    return ExternalFileDropRegion(
      target: target,
      onOutcome: onOutcome,
      child: WorkspaceFileDropRegion(
        target: target,
        onOutcome: onOutcome,
        child: child,
      ),
    );
  }
}
