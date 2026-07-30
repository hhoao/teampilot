import '../../models/ssh_profile.dart';
import 'termux_config.dart';

/// Ephemeral SSH transport profile for Termux loopback — never persisted in
/// [SshProfileRepository].
SshProfile termuxTransportProfile(TermuxConfig config) {
  return SshProfile(
    id: 'termux',
    name: 'Termux',
    host: config.host,
    port: config.port,
    username: config.username,
    authType: SshAuthType.privateKey,
  );
}
