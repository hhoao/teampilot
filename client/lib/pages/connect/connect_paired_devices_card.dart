import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/connect_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/connect/connect_ssh_backend.dart';

class ConnectPairedDevicesCard extends StatelessWidget {
  const ConnectPairedDevicesCard({
    required this.devices,
    required this.sshBackend,
    required this.onRevoke,
    super.key,
  });

  final List<ConnectPairedDevice> devices;
  final ConnectSshBackendKind sshBackend;
  final Future<void> Function(String deviceId) onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpSectionHeader(title: l10n.connectPairedDevicesTitle),
          if (sshBackend == ConnectSshBackendKind.system)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                l10n.connectRevokeSystemHint,
                style: TpTextStyles.of(context).mutedSm,
              ),
            ),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Text(l10n.connectNoPairedDevices),
            )
          else
            for (final device in devices)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Row(
                  children: [
                    const Icon(Icons.phone_android_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(device.name),
                          Text(
                            device.deviceId,
                            style: TpTextStyles.of(context).mutedSm,
                          ),
                        ],
                      ),
                    ),
                    TpButton(
                      variant: TpButtonVariant.destructive,
                      onPressed: () => unawaited(onRevoke(device.deviceId)),
                      child: Text(l10n.connectRevokeDevice),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
