import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/connect_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/connect/ssh_pairing_offer.dart';
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

    // Reachability must be labeled honestly: without an extra endpoint or a
    // live relay registration the phone can only pair on LAN.
    final lanOnly = state.extraEndpoints.isEmpty &&
        state.relayUrl.trim().isEmpty &&
        offer.relay == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TpStatusBadge(
          label: lanOnly
              ? l10n.connectLanOnlyStatus
              : l10n.connectRemoteReadyStatus,
          icon: lanOnly ? Icons.lan_outlined : Icons.public,
          tone: TpStatusBadgeTone.success,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final size = available.isFinite
                ? available.clamp(160.0, 400.0)
                : 400.0;
            return Center(
              child: InkWell(
                onTap: () => _showFullscreenQr(context, offer),
                child: _PairingQr(
                  offer: offer,
                  size: size,
                  qrKey: AppKeys.connectQrCode,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            l10n.connectQrEnlargeHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 4),
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

  void _showFullscreenQr(BuildContext context, SshPairingOffer offer) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            // The QR sizes itself to the space left after the hint text, so
            // tall (zh / large text scale) hints shrink the square instead of
            // overflowing the dialog.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Center(child: _PairingQr(offer: offer)),
                ),
                const SizedBox(height: 8),
                Text(context.l10n.connectScanHint),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Raw-bytes QR with medium error correction: compact payloads keep the
/// module grid coarse and M survives screen glare better than L.
///
/// A null [size] lets the QR fill the biggest square its constraints allow,
/// so callers with tight height budgets can wrap it in [Flexible].
class _PairingQr extends StatelessWidget {
  const _PairingQr({required this.offer, this.size, this.qrKey});

  final SshPairingOffer offer;
  final double? size;
  final Key? qrKey;

  @override
  Widget build(BuildContext context) {
    final qr = QrCode.fromUint8List(
      data: Uint8List.fromList(offer.qrBytes),
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    return QrImageView.withQr(
      key: qrKey,
      qr: qr,
      size: size,
      backgroundColor: Colors.white,
      padding: const EdgeInsets.all(12),
    );
  }
}
