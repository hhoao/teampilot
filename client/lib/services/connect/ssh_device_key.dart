import '../termux/termux_openssh_ed25519_encoder.dart';

/// The phone-install key used to authenticate against paired desktops.
class SshDeviceKey {
  const SshDeviceKey._();

  static ({String pem, String openSshPublic}) generate() {
    final keyPair = const TermuxOpenSshEd25519Encoder().generate(
      comment: 'teampilot-connect',
    );
    return (
      pem: keyPair.privateKeyPem,
      openSshPublic: keyPair.publicKeyOpenSsh,
    );
  }
}
