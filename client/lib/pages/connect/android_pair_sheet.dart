import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_known_host_repository.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../services/connect/connect_pair_client.dart';
import '../../services/connect/paired_profile_writer.dart';
import '../../services/connect/pairing_http.dart';
import '../../services/connect/ssh_device_key.dart';
import '../../services/connect/ssh_pairing_offer.dart';
import '../../utils/logging/logger_utils.dart';
import '../../utils/ui/app_keys.dart';

typedef SshDeviceKeyFactory = ({String pem, String openSshPublic}) Function();

Future<void> showAndroidPairSheet(
  BuildContext context, {
  Future<String?> Function()? scanCode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (_) => AndroidPairSheet(scanCode: scanCode),
  );
}

/// Android's first-pair flow: scan or paste a desktop's one-time SSH offer.
class AndroidPairSheet extends StatefulWidget {
  const AndroidPairSheet({
    this.scanCode,
    this.pairClient,
    this.profileWriter,
    this.deviceKeyFactory,
    this.deviceId,
    this.deviceName,
    super.key,
  });

  /// Test seam. Production opens [MobileScanner] when this is omitted.
  final Future<String?> Function()? scanCode;
  final ConnectPairClient? pairClient;
  final PairedProfileWriter? profileWriter;
  final SshDeviceKeyFactory? deviceKeyFactory;
  final String? deviceId;
  final String? deviceName;

  @override
  State<AndroidPairSheet> createState() => _AndroidPairSheetState();
}

class _AndroidPairSheetState extends State<AndroidPairSheet> {
  final _codeController = TextEditingController();
  var _showPaste = false;
  var _pairing = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<String?> _scan() async {
    final injected = widget.scanCode;
    if (injected != null) return injected();
    return Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _AndroidQrScannerPage()),
    );
  }

  Future<void> _scanAndPair() async {
    final code = await _scan();
    if (code == null || code.trim().isEmpty || !mounted) return;
    await _pair(code);
  }

  Future<void> _pair(String rawCode) async {
    if (_pairing) return;
    final l10n = context.l10n;
    final credentials = context.read<SshCredentialStore>();
    final pairClient = widget.pairClient ?? ConnectPairClient();
    final writer =
        widget.profileWriter ??
        PairedProfileWriter(
          profileRepository: context.read<SshProfileRepository>(),
          credentialStore: credentials,
          knownHostRepository: context.read<SshKnownHostRepository>(),
        );
    final profiles = context.read<SshProfileCubit>();
    final connections = context.read<SshConnectionCubit>();
    setState(() {
      _pairing = true;
      _error = null;
    });

    try {
      final offer = SshPairingOffer.decode(rawCode);
      final key = await _loadDeviceKey(credentials);
      final result = await pairClient.pair(
        offer: offer,
        deviceId: widget.deviceId ?? _deviceIdFor(key.openSshPublic),
        deviceName: widget.deviceName ?? Platform.localHostname,
        publicKey: key.openSshPublic,
      );
      final profile = await writer.upsert(
        offer: offer,
        result: result,
        devicePem: key.pem,
      );
      final relayGrant = result.relayGrant;
      if (relayGrant != null && relayGrant.isNotEmpty) {
        await credentials.saveRelayGrant(profile.id, relayGrant);
      }

      await profiles.load();
      await connections.syncProfiles(profiles.state.profiles);
      await connections.connect(profile.id);
      if (mounted) await Navigator.of(context).maybePop();
    } on PairingHttpException catch (error, stackTrace) {
      AppLogger.instance.w(
        '[connect-pair] pairing request rejected code=${error.code}',
        stackTrace: stackTrace,
      );
      _showError(
        error.code == 'expired' ||
                error.code == 'used' ||
                error.code == 'invalid'
            ? l10n.connectPairExpired
            : l10n.connectPairFailed,
      );
    } on SshPairingOfferFormatException catch (error, stackTrace) {
      AppLogger.instance.w(
        '[connect-pair] pairing offer rejected reason=${error.message}',
        stackTrace: stackTrace,
      );
      _showError(
        error.message == 'unsupported offer version'
            ? l10n.connectPairUpdateApp
            : l10n.connectPairInvalid,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[connect-pair] pairing failed type=${error.runtimeType}',
        stackTrace: stackTrace,
      );
      _showError(l10n.connectPairFailed);
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  Future<({String pem, String openSshPublic})> _loadDeviceKey(
    SshCredentialStore credentials,
  ) async {
    final existing = await credentials.loadDevicePrivateKey();
    if (existing != null && existing.trim().isNotEmpty) {
      try {
        return _materialFromPem(existing);
      } on Object catch (error, stackTrace) {
        AppLogger.instance.w(
          '[connect-pair] replacing unusable device key '
          'type=${error.runtimeType}',
          stackTrace: stackTrace,
        );
      }
    }
    final generated = (widget.deviceKeyFactory ?? SshDeviceKey.generate)();
    if (!generated.openSshPublic.startsWith('ssh-ed25519 ')) {
      throw const FormatException('device key must be Ed25519');
    }
    await credentials.saveDevicePrivateKey(generated.pem);
    return generated;
  }

  ({String pem, String openSshPublic}) _materialFromPem(String pem) {
    final pairs = SSHKeyPair.fromPem(pem);
    if (pairs.length != 1 || pairs.single.name != 'ssh-ed25519') {
      throw const FormatException('device key must be one Ed25519 key');
    }
    final pair = pairs.single;
    final encodedPublic = pair.toPublicKey().encode();
    return (
      pem: pem,
      openSshPublic:
          '${pair.name} ${base64.encode(encodedPublic)} teampilot-connect',
    );
  }

  String _deviceIdFor(String openSshPublic) {
    final digest = sha256.convert(utf8.encode(openSshPublic));
    return base64Url
        .encode(digest.bytes.take(12).toList(growable: false))
        .replaceAll('=', '');
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = _error;
    return PopScope(
      canPop: !_pairing,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.connectPairSheetTitle,
                style: TpTextStyles.of(context).lgBoldSnug,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.connectPairSheetSubtitle,
                style: TpTextStyles.of(context).mutedSm,
              ),
              const SizedBox(height: 20),
              TpButton(
                key: AppKeys.connectScanQr,
                onPressed: _pairing ? null : _scanAndPair,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.qr_code_scanner, size: 18),
                    const SizedBox(width: 8),
                    Text(_pairing ? l10n.connectPairing : l10n.connectScanQr),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TpButton(
                key: AppKeys.connectPasteCode,
                variant: TpButtonVariant.outline,
                onPressed: _pairing
                    ? null
                    : () => setState(() => _showPaste = !_showPaste),
                child: Text(l10n.connectPasteCode),
              ),
              if (_showPaste) ...[
                const SizedBox(height: 12),
                TpInput(
                  controller: _codeController,
                  autofocus: true,
                  enabled: !_pairing,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: l10n.connectPairCodeHint,
                  ),
                  onSubmitted: _pairing ? null : _pair,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TpButton(
                    onPressed: _pairing
                        ? null
                        : () => _pair(_codeController.text),
                    child: Text(l10n.connectPairNow),
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AndroidQrScannerPage extends StatefulWidget {
  const _AndroidQrScannerPage();

  @override
  State<_AndroidQrScannerPage> createState() => _AndroidQrScannerPageState();
}

class _AndroidQrScannerPageState extends State<_AndroidQrScannerPage> {
  var _finished = false;

  void _detected(BarcodeCapture capture) {
    if (_finished) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (value == null) return;
    _finished = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.connectScanQr)),
      body: MobileScanner(
        onDetect: _detected,
        errorBuilder: (context, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.connectScannerUnavailable,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        overlayBuilder: (context, constraints) => Center(
          child: Container(
            width: constraints.maxWidth * 0.7,
            height: constraints.maxWidth * 0.7,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}
