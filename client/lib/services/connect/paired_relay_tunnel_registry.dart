import 'dart:async';
import 'dart:io';

import '../../models/ssh_profile.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../utils/logging/logger_utils.dart';
import 'phone_relay_tunnel.dart';
import 'ssh_device_key.dart';

typedef RelayTunnelFactory = PhoneRelayTunnel Function();

/// Keeps one live relay tunnel per paired profile on the phone.
///
/// While an entry exists, every dial for that profile routes through the
/// registry (see `SshClientFactory.dialTargetResolver`), so pooled storage
/// clients and member sessions ride the same loopback port until the profile
/// disconnects. The loopback address is never persisted.
class PairedRelayTunnelRegistry {
  PairedRelayTunnelRegistry({
    required this.credentialStore,
    this.tunnelFactory,
  });

  final SshCredentialStore credentialStore;
  final RelayTunnelFactory? tunnelFactory;

  final _tunnels = <String, PhoneRelayTunnel>{};
  final _deviceIds = <String, String>{};

  /// Opens (or reuses) the SSH tunnel for [profile].
  Future<({InternetAddress address, int port})> ensureSshTunnel(
    SshProfile profile,
  ) async {
    final existing = _tunnels[profile.id];
    if (existing != null && !existing.isClosed) {
      return (address: existing.address, port: existing.port);
    }
    final hostId = profile.pairedDesktopId;
    final relayUrl = profile.relayUrl;
    if (hostId == null || hostId.isEmpty || relayUrl == null || relayUrl.isEmpty) {
      throw const SocketException('profile has no relay endpoint');
    }

    final grant = await credentialStore.loadRelayGrant(profile.id);
    if (grant == null || grant.isEmpty) {
      throw const SocketException('no relay grant stored for profile');
    }

    final tunnel =
        _tunnels[profile.id] = (tunnelFactory ?? PhoneRelayTunnel.new)();
    try {
      await tunnel.open(
        relayUrl: Uri.parse(relayUrl),
        hostId: hostId,
        channel: 'ssh',
        deviceId: await _deviceIdFor(profile.id),
        relayGrant: grant,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[connect-relay] ssh tunnel failed class=${error.runtimeType}',
        stackTrace: stackTrace,
      );
      await tunnel.close();
      _tunnels.remove(profile.id);
      rethrow;
    }
    return (address: tunnel.address, port: tunnel.port);
  }

  Future<void> closeFor(String profileId) async {
    final tunnel = _tunnels.remove(profileId);
    await tunnel?.close();
  }

  /// Loopback target while a tunnel lives; null means dial directly.
  Future<({InternetAddress address, int port})?> targetFor(String profileId) async {
    final tunnel = _tunnels[profileId];
    if (tunnel == null || tunnel.isClosed) return null;
    return (address: tunnel.address, port: tunnel.port);
  }

  Future<String> _deviceIdFor(String profileId) async {
    final cached = _deviceIds[profileId];
    if (cached != null) return cached;
    final pem = await credentialStore.loadDevicePrivateKey();
    if (pem == null || pem.trim().isEmpty) {
      throw const SocketException('device key missing');
    }
    final deviceId = SshDeviceKey.deviceIdFromPem(pem);
    return _deviceIds[profileId] = deviceId;
  }

  Future<void> dispose() async {
    final tunnels = List.of(_tunnels.values);
    _tunnels.clear();
    for (final tunnel in tunnels) {
      await tunnel.close();
    }
  }
}
