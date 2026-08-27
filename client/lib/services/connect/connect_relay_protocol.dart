/// Shared wire keys and paths for the self-hosted TeamPilot Connect relay
/// (`tools/teampilot_connect_relay`).
///
/// The tool reimplements these constants on purpose: it must never grow a
/// path dependency back into the TeamPilot client tree. Keep both sides in
/// sync when changing the protocol.
abstract final class ConnectRelayProtocol {
  static const healthPath = '/health';
  static const registerPath = '/register';
  static const dialPath = '/dial';
  static const splicePath = '/splice';

  /// Dial notification `{type: "dial", ...}` sent to the registered desktop.
  static const typeDial = 'dial';

  static const keyType = 'type';
  static const keyChannel = 'channel';
  static const keySpliceId = 'spliceId';
  static const keyDeviceId = 'deviceId';
  static const keyInviteToken = 'inviteToken';
  static const keyRelayGrant = 'relayGrant';

  /// Query keys for the /dial WebSocket upgrade.
  static const queryHostId = 'hostId';

  /// Pairing channel: forwards bytes to the local pairing HTTPS listener.
  static const channelPair = 'pair';

  /// SSH channel: forwards bytes to the local sshd listener.
  static const channelSsh = 'ssh';

  static Map<String, Object?> dialNotification({
    required String channel,
    required String spliceId,
    String? deviceId,
    String? inviteToken,
    String? relayGrant,
  }) =>
      {
        keyType: typeDial,
        keyChannel: channel,
        keySpliceId: spliceId,
        if (deviceId != null && deviceId.isNotEmpty) keyDeviceId: deviceId,
        if (inviteToken != null && inviteToken.isNotEmpty)
          keyInviteToken: inviteToken,
        if (relayGrant != null && relayGrant.isNotEmpty)
          keyRelayGrant: relayGrant,
      };
}
