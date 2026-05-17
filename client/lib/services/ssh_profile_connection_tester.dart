import 'package:logger/logger.dart';

import '../models/ssh_profile.dart';
import 'ssh_client_factory.dart';

class SshProfileConnectionTester {
  const SshProfileConnectionTester({required SshClientFactory clientFactory})
    : _clientFactory = clientFactory;

  final SshClientFactory _clientFactory;

  Future<void> test(SshProfile profile) async {
    final client = await _clientFactory.createClient(profile);
    try {
      await client.authenticated;
    } catch (e, stackTrace) {
      Logger().e(
        'Error testing SSH profile connection',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      client.close();
    }
  }
}
