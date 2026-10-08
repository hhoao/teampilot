import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/connect_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/connect/connect_ssh_backend.dart';
import '../../utils/ui/app_keys.dart';

class ConnectSshBackendSelector extends StatelessWidget {
  const ConnectSshBackendSelector({
    required this.state,
    required this.onChanged,
    super.key,
  });

  final ConnectState state;
  final ValueChanged<ConnectSshBackendKind> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!state.systemSshdSelectable) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          l10n.connectSshBackendLabel,
          style: TpTextStyles.of(context).smMedium,
        ),
        const SizedBox(height: 6),
        TpSelect<ConnectSshBackendKind>(
          key: AppKeys.connectSshBackendSelect,
          items: ConnectSshBackendKind.values,
          initialItem: state.sshBackend,
          itemLabel: (kind) => switch (kind) {
            ConnectSshBackendKind.embedded => l10n.connectSshBackendEmbedded,
            ConnectSshBackendKind.system => l10n.connectSshBackendSystem,
          },
          decoration: TpSelectDecorations.themed(context),
          searchable: false,
          onChanged: (kind) {
            if (kind != null) onChanged(kind);
          },
        ),
        const SizedBox(height: 6),
        Text(
          l10n.connectSshBackendHelp,
          style: TpTextStyles.of(context).mutedSm,
        ),
      ],
    );
  }
}
