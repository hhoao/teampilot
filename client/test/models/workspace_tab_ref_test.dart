import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_tab_ref.dart';

void main() {
  test('tabKey is workspace id', () {
    const tab = WorkspaceTabRef(workspaceId: 'ws-1');
    expect(tab.tabKey, 'ws-1');
  });

  test('fromLocation parses workspace route', () {
    final tab = WorkspaceTabRef.fromLocation('/home-v2/workspace/ws-2');
    expect(tab?.workspaceId, 'ws-2');
    expect(tab?.route, '/home-v2/workspace/ws-2');
  });

  test('fromJson round-trips workspace id', () {
    const tab = WorkspaceTabRef(workspaceId: 'ws-3');
    expect(
      WorkspaceTabRef.fromJson(tab.toJson()),
      tab,
    );
  });
}
