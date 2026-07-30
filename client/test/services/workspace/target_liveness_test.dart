import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/workspace/target_liveness.dart';

void main() {
  test('ssh missing profile is dead', () async {
    final tmp = await Directory.systemTemp.createTemp('liveness_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ssh = SshProfileRepository(rootDir: tmp.path);
    final liveness = DefaultTargetLiveness(sshProfiles: ssh);
    expect(await liveness.isAlive('ssh:gone'), isFalse);
  });

  test('ssh present profile is alive', () async {
    final tmp = await Directory.systemTemp.createTemp('liveness_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ssh = SshProfileRepository(rootDir: tmp.path);
    await ssh.saveAll([
      const SshProfile(
        id: 'p1',
        name: 'dev',
        host: 'localhost',
        username: 'root',
        port: 22,
      ),
    ]);
    final liveness = DefaultTargetLiveness(sshProfiles: ssh);
    expect(await liveness.isAlive('ssh:p1'), isTrue);
  });

  test('local is always alive', () async {
    final tmp = await Directory.systemTemp.createTemp('liveness_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ssh = SshProfileRepository(rootDir: tmp.path);
    final liveness = DefaultTargetLiveness(sshProfiles: ssh);
    expect(await liveness.isAlive('local'), isTrue);
  });

  test('wsl well-formed is alive (no probe yet)', () async {
    final tmp = await Directory.systemTemp.createTemp('liveness_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ssh = SshProfileRepository(rootDir: tmp.path);
    final liveness = DefaultTargetLiveness(sshProfiles: ssh);
    expect(await liveness.isAlive('wsl:Ubuntu'), isTrue);
  });

  test('empty string is dead', () async {
    final tmp = await Directory.systemTemp.createTemp('liveness_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ssh = SshProfileRepository(rootDir: tmp.path);
    final liveness = DefaultTargetLiveness(sshProfiles: ssh);
    expect(await liveness.isAlive(''), isFalse);
    expect(await liveness.isAlive('   '), isFalse);
  });

  test('malformed ssh target is dead', () async {
    final tmp = await Directory.systemTemp.createTemp('liveness_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ssh = SshProfileRepository(rootDir: tmp.path);
    final liveness = DefaultTargetLiveness(sshProfiles: ssh);
    expect(await liveness.isAlive('ssh:'), isFalse);
  });

  test('termux without config is dead when checker provided', () async {
    final tmp = await Directory.systemTemp.createTemp('liveness_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ssh = SshProfileRepository(rootDir: tmp.path);
    final liveness = DefaultTargetLiveness(
      sshProfiles: ssh,
      hasTermuxConfig: () => false,
    );
    expect(await liveness.isAlive('termux:default'), isFalse);
  });

  test('termux with config is alive when checker provided', () async {
    final tmp = await Directory.systemTemp.createTemp('liveness_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ssh = SshProfileRepository(rootDir: tmp.path);
    final liveness = DefaultTargetLiveness(
      sshProfiles: ssh,
      hasTermuxConfig: () => true,
    );
    expect(await liveness.isAlive('termux:default'), isTrue);
  });
}
