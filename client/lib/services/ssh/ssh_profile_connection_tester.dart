import 'package:logger/logger.dart';
import '../../models/ssh_profile.dart';
import 'ssh_client_factory.dart';

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
    } catch (e, stackTrace) {
      Logger().e(
        'Error testing SSH profile connection',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
