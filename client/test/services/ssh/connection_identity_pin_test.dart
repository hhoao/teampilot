import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the connection-identity contract in source: a machine is identified by
/// `(machineId, plan generation)`, never by an address.
void main() {
  const identityFiles = [
    'lib/services/ssh/ssh_client_factory_storage.dart',
    'lib/services/ssh/ssh_client_factory_legacy_storage.dart',
    'lib/services/ssh/ssh_client_factory.dart',
    'lib/services/ssh/worker/ssh_worker_protocol.dart',
    'lib/services/ssh/worker/ssh_profile_worker.dart',
    'lib/services/ssh/worker/ssh_worker_member_core.dart',
    'lib/services/ssh/worker/ssh_worker_forward_core.dart',
    'lib/services/ssh/worker/ssh_worker_storage_client.dart',
    'lib/services/ssh/worker/ssh_worker_member_session.dart',
  ];

  test('no pooled/session identity derives from the address', () {
    for (final path in identityFiles) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('hostIdentifier')),
        reason:
            '$path must key on (machineId, generation); an address is a dial '
            'attempt, not an identity',
      );
    }
  });

  test('a plan change is retired silently, without tripping the breaker', () {
    final source = File(
      'lib/services/ssh/ssh_client_factory_storage.dart',
    ).readAsStringSync();

    expect(source, contains('void _retireForPlanChange(String profileId)'));
    expect(
      source,
      contains('notifyTransportClose: false'),
      reason:
          'a local re-target must not be reported as a transport close, or the '
          'coordinator turns it into a whole-home outage',
    );
    expect(source, contains('cooldown: false'));
  });

  test('the coordinator ignores a local plan change on the storage plane', () {
    final source = File(
      'lib/services/ssh/ssh_profile_connection_coordinator.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('error.reason == SshTransportCloseReason.profileInvalidated'),
    );
  });

  test('the address-resolving catalogs are gone', () {
    for (final path in [
      'lib/services/ssh/combined_ssh_profile_resolver.dart',
      'lib/repositories/combined_ssh_profile_repository.dart',
      'lib/services/ssh/plane_ssh_profile_resolver.dart',
      'lib/models/ssh_server_profile.dart',
      'lib/repositories/ssh_server_profile_repository.dart',
      'lib/models/remote_target.dart',
    ]) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: '$path described reachability that now belongs to a connection',
      );
    }
  });

  test('the raw-client connector seam is test-only', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('ssh_client_factory.dart')) continue;
      if (entity.readAsStringSync().contains('SshClientConnector')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'only the factory may declare or accept a raw-client dialer',
    );
    expect(
      File('lib/services/ssh/ssh_client_factory.dart').readAsStringSync(),
      contains('test-only'),
      reason: 'the seam must stay documented as test-only',
    );
  });

  test('the plane catalog carries no reachability fields', () {
    final source = File(
      'lib/models/connection/catalog_entry.dart',
    ).readAsStringSync();

    for (final field in ["'host'", "'port'", 'username', 'relayUrl']) {
      expect(source, isNot(contains(field)));
    }
  });
}
