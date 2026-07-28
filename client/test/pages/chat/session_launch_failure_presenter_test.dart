import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_launch_failure_presenter.dart';

void main() {
  test('null and blank yield null', () {
    expect(presentSessionLaunchFailure(null), isNull);
    expect(presentSessionLaunchFailure('   '), isNull);
  });

  test('normal error yields retry only', () {
    final view = presentSessionLaunchFailure('Failed to start claude');
    expect(view, isNotNull);
    expect(view!.message, 'Failed to start claude');
    expect(view.actions.map((a) => a.kind).toList(), [
      SessionLaunchFailureActionKind.retry,
    ]);
  });

  test('dead SSH error yields remap then retry', () {
    final view = presentSessionLaunchFailure(
      'No SSH profile for target "ssh:missing-profile"',
    );
    expect(view, isNotNull);
    expect(view!.actions.map((a) => a.kind).toList(), [
      SessionLaunchFailureActionKind.remapDeadSsh,
      SessionLaunchFailureActionKind.retry,
    ]);
    expect(view.actions.first.deadSshTargetId, 'ssh:missing-profile');
  });
}
