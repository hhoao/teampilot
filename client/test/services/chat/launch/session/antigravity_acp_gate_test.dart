import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/acp_compose_permission.dart';
import 'package:teampilot/services/chat/launch/session/member_acp_stamp.dart';
import 'package:teampilot/services/chat/launch/session/session_provisional_builder.dart';

/// Antigravity is ACP-only on personal desktop and forced to ACP for mixed-team
/// local seats; Android never launches personal ACP.
void main() {
  final workspace = Workspace(
    workspaceId: 'ws-1',
    createdAt: 0,
    folders: [WorkspaceFolder(path: '/repo/main')],
  );

  group('personal sessions', () {
    test('AppSession infers acp for Antigravity via launchesAcpOnly', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'ws-1',
        cli: CliTool.antigravity,
        createdAt: 0,
      );
      expect(session.acp, isTrue);
    });

    test('provisional builder infers acp for Antigravity', () {
      final session = buildProvisionalSession(
        sessionId: 's1',
        workspace: workspace,
        isPersonal: true,
        usesPosixPaths: true,
        cli: CliTool.antigravity,
      );
      expect(session.acp, isTrue);
    });

    test('team session does not infer acp from the CLI', () {
      final session = buildProvisionalSession(
        sessionId: 's1',
        workspace: workspace,
        isPersonal: false,
        usesPosixPaths: true,
        cli: CliTool.antigravity,
        sessionTeamId: 'team-1',
      );
      expect(session.acp, isFalse);
    });

    test('willLaunchAcp is true on desktop and false on Android', () {
      expect(
        willLaunchAcp(
          cli: CliTool.antigravity,
          requested: false,
        ),
        isTrue,
      );
      expect(
        willLaunchAcp(
          cli: CliTool.antigravity,
          requested: false,
          isAndroidOverride: true,
        ),
        isFalse,
      );
    });
  });

  group('mixed-team seats', () {
    SessionMemberBinding member(String id) => SessionMemberBinding(
      rosterMemberId: id,
      taskId: 'task-$id',
      cli: CliTool.antigravity,
    );

    test('resolveMemberBindingAcp forces ACP for a local seat', () {
      expect(
        resolveMemberBindingAcp(
          cli: CliTool.antigravity,
          targetId: 'local',
          requested: false,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('resolveMemberBindingAcp rejects non-local or Android seats', () {
      expect(
        resolveMemberBindingAcp(
          cli: CliTool.antigravity,
          targetId: 'ssh:prod',
          requested: true,
          isAndroidOverride: false,
        ),
        isFalse,
      );
      expect(
        resolveMemberBindingAcp(
          cli: CliTool.antigravity,
          targetId: 'local',
          requested: true,
          isAndroidOverride: true,
        ),
        isFalse,
      );
    });

    test('stampMemberAcp forces ACP for a local Antigravity seat', () {
      final stamped = stampMemberAcp(
        members: [member('agy')],
        memberTargets: const {'agy': 'local'},
        seedClaudeMemberAcp: false,
        seedCodexMemberAcp: false,
        isAndroidOverride: false,
      );
      expect(stamped.single.acp, isTrue);
    });

    test('stampMemberAcp keeps ACP off on Android', () {
      final stamped = stampMemberAcp(
        members: [member('agy')],
        memberTargets: const {'agy': 'local'},
        seedClaudeMemberAcp: false,
        seedCodexMemberAcp: false,
        isAndroidOverride: true,
      );
      expect(stamped.single.acp, isFalse);
    });
  });
}
