import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/models/workspace_tab_ref.dart';

void main() {
  test('tabKey encodes workspace id and launch identity', () {
    const tab = WorkspaceTabRef(
      workspaceId: 'ws-1',
      identity: LaunchProfileRef('team-a'),
    );
    expect(tab.tabKey, 'ws-1\x1eteam-a');
    expect(
      WorkspaceTabRef.decodeTabKey(tab.tabKey),
      tab,
    );
  });

  test('decodeTabKey rejects plain workspace ids', () {
    expect(WorkspaceTabRef.decodeTabKey('ws-legacy'), isNull);
  });

  test('fromLocation parses workspace route', () {
    final tab = WorkspaceTabRef.fromLocation(
      '/home-v2/workspace/ws-2?as=${LaunchProfileProvisioner.defaultPersonalId}',
    );
    expect(tab?.workspaceId, 'ws-2');
    expect(tab?.identity.profileId, LaunchProfileProvisioner.defaultPersonalId);
    expect(tab?.route, contains('/home-v2/workspace/ws-2'));
  });
}
