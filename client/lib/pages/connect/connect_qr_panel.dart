import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/connect_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

class ConnectQrPanel extends StatelessWidget {
  const ConnectQrPanel({
    required this.state,
    required this.onCheckSshd,
    required this.onCopyLink,
    required this.onRegenerate,
    super.key,
  });

  final ConnectState state;
  final VoidCallback onCheckSshd;
  final VoidCallback onCopyLink;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final offer = state.offer;
    if (state.loading && state.sshd.enableHint.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.canPair) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.connectSshdDown),
          if (state.sshd.enableHint.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              state.sshd.enableHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          TpButton(
            key: AppKeys.connectSshdEnableCta,
            variant: TpButtonVariant.outline,
            onPressed: onCheckSshd,
            child: Text(l10n.connectCheckAgain),
          ),
        ],
      );
    }

    if (offer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TpStatusBadge(
          label: offer.relay == null
              ? l10n.connectLanOnlyStatus
              : l10n.connectRemoteReadyStatus,
          icon: offer.relay == null ? Icons.lan_outlined : Icons.public,
          tone: TpStatusBadgeTone.success,
        ),
        const SizedBox(height: 16),
        Center(
          child: QrImageView(
            key: AppKeys.connectQrCode,
            data: offer.encode(),
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text(l10n.connectScanHint)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TpButton(
              variant: TpButtonVariant.outline,
              onPressed: onCopyLink,
              child: Text(l10n.connectCopyLink),
            ),
            TpButton(
              key: AppKeys.connectRegenerateQr,
              variant: TpButtonVariant.outline,
              onPressed: onRegenerate,
              child: Text(l10n.connectRegenerate),
            ),
          ],
        ),
      ],
    );
  }
}
