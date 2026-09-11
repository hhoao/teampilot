import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';

/// The group-scoped lock affordance shared by workbench group headers.
class WorkbenchGroupLockButton extends StatelessWidget {
  const WorkbenchGroupLockButton({
    required this.locked,
    required this.onToggle,
    super.key,
  });

  final bool locked;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return TpIconButton(
      icon: locked ? Icons.lock_outlined : Icons.lock_open_outlined,
      tooltip: locked
          ? context.l10n.workbenchUnlockGroup
          : context.l10n.workbenchLockGroup,
      compact: true,
      enabled: onToggle != null,
      onTap: onToggle,
    );
  }
}
