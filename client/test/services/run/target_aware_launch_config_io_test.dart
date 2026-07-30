import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/run/launch_config_store.dart';
import 'package:teampilot/services/storage/work_target_canonicalizer.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  final sshHome = RuntimeTarget.ssh('p1', label: 'box');

  test('canonicalizes local to ssh home before filesystem resolve', () async {
    String? resolvedTargetId;
    final remoteFs = InMemoryFilesystem();
    final io = TargetAwareLaunchConfigIo(
      homeTarget: () => sshHome,
      resolveFilesystem: (targetId) async {
        resolvedTargetId = targetId;
        return remoteFs;
      },
    );

    await io.exists('/repo/.teampilot/launch.json', targetId: 'local');

    expect(resolvedTargetId, 'ssh:p1');
  });

  test('localFallback throws for ssh-home local without custom resolver', () async {
    final io = TargetAwareLaunchConfigIo.localFallback(
      homeTarget: () => sshHome,
    );

    expect(
      () => io.exists('/repo/.teampilot/launch.json', targetId: 'local'),
      throwsA(isA<StateError>()),
    );
  });

  test('canonicalize decision maps local to home id', () {
    expect(
      WorkTargetCanonicalizer.resolve('local', home: sshHome).id,
      'ssh:p1',
    );
    expect(
      WorkTargetCanonicalizer.fromId(
        WorkTargetCanonicalizer.resolve('local', home: sshHome).id,
      ).kind,
      RuntimeKind.ssh,
    );
  });
}
