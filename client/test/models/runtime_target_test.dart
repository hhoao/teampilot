import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';

void main() {
  test('factories build canonical ids', () {
    expect(RuntimeTarget.local().id, 'local');
    expect(RuntimeTarget.wsl('Ubuntu').id, 'wsl:Ubuntu');
    expect(RuntimeTarget.ssh('p1', label: 'box').id, 'ssh:p1');
  });

  test('id parse helpers', () {
    expect(runtimeKindOfId('local'), RuntimeKind.local);
    expect(runtimeKindOfId('wsl:Ubuntu'), RuntimeKind.wsl);
    expect(runtimeKindOfId('ssh:p1'), RuntimeKind.ssh);
    expect(wslDistroOfId('wsl:Ubuntu'), 'Ubuntu');
    expect(sshProfileIdOfId('ssh:p1'), 'p1');
    expect(sshProfileIdOfId('local'), isNull);
  });

  test('json round-trip preserves payload and null remoteOs', () {
    final t = RuntimeTarget.ssh('p1', label: 'box');
    final r = RuntimeTarget.fromJson(t.toJson());
    expect(r.id, 'ssh:p1');
    expect(r.kind, RuntimeKind.ssh);
    expect(r.sshProfileId, 'p1');
    expect(r.remoteOs, isNull);
  });

  test('wsl target carries distro', () {
    final r = RuntimeTarget.fromJson(RuntimeTarget.wsl('Debian').toJson());
    expect(r.kind, RuntimeKind.wsl);
    expect(r.wslDistro, 'Debian');
  });
}
