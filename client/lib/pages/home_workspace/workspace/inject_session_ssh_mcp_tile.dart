import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import 'package:shared_ui/shared_ui.dart';

/// Workspace-scoped toggle to inject Session SSH MCP when the workspace has
/// `ssh:*` folders. Default **on**; no confirm dialog.
class InjectSessionSshMcpTile extends StatelessWidget {
  const InjectSessionSshMcpTile({
    required this.enabled,
    required this.onChanged,
    this.showDividerBelow = true,
    super.key,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpPreferenceRow(
      title: l10n.injectSessionSshMcpTitle,
      subtitle: l10n.injectSessionSshMcpSubtitle,
      trailing: Switch(value: enabled, onChanged: onChanged),
      showDividerBelow: showDividerBelow,
    );
  }
}
