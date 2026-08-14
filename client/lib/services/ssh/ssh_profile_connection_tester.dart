import '../../models/ssh_profile.dart';
import '../../utils/logging/logger.dart';
import 'ssh_client_factory.dart';
import 'ssh_connection_failure.dart';

class SshProfileConnectionTester {
  const SshProfileConnectionTester({required SshClientFactory clientFactory})
    : _clientFactory = clientFactory;

  final SshClientFactory _clientFactory;

  Future<void> test(
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? privateKeyPassphrase,
  }) async {
    try {
      await _clientFactory.testConnection(
        profile,
        password: password,
        privateKey: privateKey,
        privateKeyPassphrase: privateKeyPassphrase,
      );
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[ssh] profile ${profile.id} (${profile.hostIdentifier}) '
        'connection test failed: ${sshConnectionFailureLogMessage(error)}',
        error: sshConnectionFailureCause(error),
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
