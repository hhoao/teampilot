import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

void main() {
  test('launchWorkTarget rewrites folder local when home is ssh', () {
    final home = RuntimeTarget.ssh('p1', label: 'box');
    final lifecycle = SessionLifecycleService(homeTarget: () => home);
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/repo')], // targetId defaults to local
      createdAt: 1,
    );
    final ctx = WorkspaceLaunchContext(
      session: session,
      workspace: Workspace(
        workspaceId: 'w1',
        folders: session.folders,
        createdAt: 1,
      ),
    );
    final target = lifecycle.launchWorkTarget(ctx);
    expect(target.kind, RuntimeKind.ssh);
    expect(target.id, 'ssh:p1');
  });
}
