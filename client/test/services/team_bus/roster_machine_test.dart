import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/team_bus/roster_machine.dart';

void main() {
  test('local → machine/id/kind all local', () {
    final m = rosterMachineFromTarget(RuntimeTarget.local());
    expect(m.machine, 'local');
    expect(m.machineId, 'local');
    expect(m.machineKind, 'local');
  });

  test('ssh with profile → hostIdentifier', () {
    final target = RuntimeTarget.ssh('p1', label: 'unused');
    final profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'localhost',
      username: 'root',
      port: 22,
    );
    final m = rosterMachineFromTarget(target, profile: profile);
    expect(m.machine, 'root@localhost:22');
    expect(m.machineId, 'ssh:p1');
    expect(m.machineKind, 'ssh');
  });

  test('ssh without profile → fall back to target.id', () {
    final m = rosterMachineFromTarget(RuntimeTarget.ssh('p1', label: ''));
    expect(m.machine, 'ssh:p1');
    expect(m.machineId, 'ssh:p1');
    expect(m.machineKind, 'ssh');
  });

  test('wsl → machine equals machineId', () {
    final m = rosterMachineFromTarget(RuntimeTarget.wsl('Ubuntu'));
    expect(m.machine, 'wsl:Ubuntu');
    expect(m.machineId, 'wsl:Ubuntu');
    expect(m.machineKind, 'wsl');
  });
}
