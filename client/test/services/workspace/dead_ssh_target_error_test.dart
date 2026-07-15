import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/workspace/dead_ssh_target_error.dart';

void main() {
  test('returns null for null message', () {
    expect(deadSshTargetIdFromError(null), isNull);
  });

  test('returns null for unrelated messages', () {
    expect(deadSshTargetIdFromError('connection refused'), isNull);
    expect(deadSshTargetIdFromError('No SSH profile for target "local".'), isNull);
  });

  test('parses workspace provisioner StateError text', () {
    const targetId = 'ssh:deleted-profile';
    expect(
      deadSshTargetIdFromError(
        'No SSH profile for target "$targetId".',
      ),
      targetId,
    );
  });

  test('parses remote cli readiness failure message text', () {
    const targetId = 'ssh:stale-host';
    expect(
      deadSshTargetIdFromError(
        'No SSH profile for target "$targetId".',
      ),
      targetId,
    );
  });
}
