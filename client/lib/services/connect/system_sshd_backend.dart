import 'authorized_keys_file.dart';
import 'connect_ssh_backend.dart';
import 'sshd_presence.dart';

/// Connect backend that pairs against the host's existing OpenSSH on port 22.
class SystemSshdBackend implements ConnectSshBackend {
  SystemSshdBackend({
    required SshdPresence presence,
    required AuthorizedKeysFile authorizedKeys,
  }) : _presence = presence,
       _authorizedKeys = authorizedKeys;

  final SshdPresence _presence;
  final AuthorizedKeysFile _authorizedKeys;

  bool _isListening = false;
  List<String> _hostKeyFingerprints = const [];

  @override
  bool get isListening => _isListening;

  @override
  int get port => systemSshdPort;

  @override
  List<String> get hostKeyFingerprints => _hostKeyFingerprints;

  @override
  bool get isEmbedded => false;

  @override
  Future<void> start() async {
    _applySample(await _presence.sample());
  }

  @override
  Future<void> stop() async {
    _isListening = false;
    _hostKeyFingerprints = const [];
  }

  @override
  Future<void> restart() async {
    _applySample(await _presence.sample());
  }

  @override
  Future<void> authorizePublicKey(String publicKey) {
    return _authorizedKeys.authorize(publicKey);
  }

  @override
  Future<void> revokePublicKey(String publicKey) {
    return _authorizedKeys.revoke(publicKey);
  }

  void _applySample(({bool listening, List<String> fingerprints}) sample) {
    _isListening = sample.listening;
    _hostKeyFingerprints = sample.fingerprints;
  }
}
