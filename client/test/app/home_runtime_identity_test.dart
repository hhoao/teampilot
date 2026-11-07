import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/home_runtime_identity.dart';

void main() {
  test('same target and app-data root are equal', () {
    const a = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );
    const b = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('same target with a different app-data root is a different plane', () {
    const a = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );
    const b = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/srv/team',
    );

    expect(a, isNot(b));
  });

  test('same app-data root on different targets is a different plane', () {
    const a = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );
    const b = HomeRuntimeIdentity(
      targetId: 'ssh:laptop',
      appDataRoot: '/home/ubuntu/team',
    );

    expect(a, isNot(b));
  });

  test('toString encodes both fields for ValueKey use', () {
    const identity = HomeRuntimeIdentity(
      targetId: 'ssh:studio',
      appDataRoot: '/home/ubuntu/team',
    );

    expect(identity.toString(), 'ssh:studio\u0000/home/ubuntu/team');
  });
}
