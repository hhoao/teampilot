import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

void main() {
  late Directory tmp;
  late TargetsRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('targets_p3c_');
    repo = TargetsRepository(rootDir: tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('credentialOptIn defaults off and round-trips', () async {
    expect(await repo.isCredentialOptIn('ssh:p1'), isFalse);

    await repo.setCredentialOptIn('ssh:p1', true);
    expect(await repo.isCredentialOptIn('ssh:p1'), isTrue);
    expect(await repo.isCredentialOptIn('ssh:p2'), isFalse);

    await repo.setCredentialOptIn('ssh:p1', false);
    expect(await repo.isCredentialOptIn('ssh:p1'), isFalse);
  });

  test('installOptIn defaults off and round-trips (sorted)', () async {
    expect(await repo.isInstallOptIn('ssh:p1'), isFalse);
    await repo.setInstallOptIn('ssh:p2', true);
    await repo.setInstallOptIn('ssh:p1', true);
    expect(await repo.isInstallOptIn('ssh:p1'), isTrue);
    final reloaded = await repo.load();
    expect(reloaded.installOptIn, ['ssh:p1', 'ssh:p2']); // sorted, stable

    await repo.setInstallOptIn('ssh:p1', false);
    expect(await repo.isInstallOptIn('ssh:p1'), isFalse);
  });

  test('cli path override round-trips per target+cli and clears on empty',
      () async {
    expect(await repo.cliPathOverride('ssh:p1', 'claude'), isNull);

    await repo.setCliPathOverride('ssh:p1', 'claude', '/opt/claude');
    await repo.setCliPathOverride('ssh:p1', 'codex', '/opt/codex');
    expect(await repo.cliPathOverride('ssh:p1', 'claude'), '/opt/claude');
    expect(await repo.cliPathOverride('ssh:p1', 'codex'), '/opt/codex');
    expect(await repo.cliPathOverride('ssh:p2', 'claude'), isNull);

    await repo.setCliPathOverride('ssh:p1', 'claude', '');
    expect(await repo.cliPathOverride('ssh:p1', 'claude'), isNull);
    expect(await repo.cliPathOverride('ssh:p1', 'codex'), '/opt/codex');
  });

  test('omits empty p3c fields from json but persists set values', () async {
    await repo.setCredentialOptIn('ssh:p1', true);
    final reloaded = await repo.load();
    expect(reloaded.credentialOptIn, ['ssh:p1']);
    expect(reloaded.toJson().containsKey('cliPathOverrides'), isFalse);
  });
}
