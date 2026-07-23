import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource_manager/resource_manager_lifecycle.dart';

void main() {
  test('chat kill uses disconnectMemberShell with sessionId+memberId', () async {
    final calls = <String>[];

    await killResourceManagerBinding(
      bindingKey: 'chat:sess-a:member-b',
      disconnectMemberShell: (sessionId, memberId) async {
        calls.add('member:$sessionId:$memberId');
      },
      killWorkspaceShell: (workspaceId, entryId) async {
        calls.add('shell:$workspaceId:$entryId');
      },
    );

    expect(calls, ['member:sess-a:member-b']);
  });

  test('shell kill routes to workspace shell dispose', () async {
    final calls = <String>[];

    await killResourceManagerBinding(
      bindingKey: 'shell:ws-1:entry-9',
      disconnectMemberShell: (sessionId, memberId) async {
        calls.add('member:$sessionId:$memberId');
      },
      killWorkspaceShell: (workspaceId, entryId) async {
        calls.add('shell:$workspaceId:$entryId');
      },
    );

    expect(calls, ['shell:ws-1:entry-9']);
  });

  test('unknown key is a no-op', () async {
    var called = false;
    await killResourceManagerBinding(
      bindingKey: 'other:x',
      disconnectMemberShell: (_, __) async => called = true,
      killWorkspaceShell: (_, __) async => called = true,
    );
    expect(called, isFalse);
  });
}
