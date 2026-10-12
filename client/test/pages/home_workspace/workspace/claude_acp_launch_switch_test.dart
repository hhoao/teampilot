import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/claude_acp_launch_switch.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';

void main() {
  group('resolveLaunchAcp', () {
    test('true only for personal Claude when requested on desktop', () {
      expect(
        resolveLaunchAcp(
          isPersonal: true,
          cli: CliTool.claude,
          requested: true,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('true for personal Cursor when requested on desktop', () {
      expect(
        resolveLaunchAcp(
          isPersonal: true,
          cli: CliTool.cursor,
          requested: true,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('true for personal Codex when requested on desktop', () {
      expect(
        resolveLaunchAcp(
          isPersonal: true,
          cli: CliTool.codex,
          requested: true,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('false for Codex team, not requested, or Android', () {
      expect(
        resolveLaunchAcp(
          isPersonal: false,
          cli: CliTool.codex,
          requested: true,
          isAndroidOverride: false,
        ),
        isFalse,
      );
      expect(
        resolveLaunchAcp(
          isPersonal: true,
          cli: CliTool.codex,
          requested: false,
          isAndroidOverride: false,
        ),
        isFalse,
      );
      expect(
        resolveLaunchAcp(
          isPersonal: true,
          cli: CliTool.codex,
          requested: true,
          isAndroidOverride: true,
        ),
        isFalse,
      );
    });

    test('false for team, Gemini, not requested, or Android', () {
      bool resolve({
        bool isPersonal = true,
        CliTool? cli = CliTool.claude,
        bool requested = true,
        bool isAndroid = false,
      }) => resolveLaunchAcp(
        isPersonal: isPersonal,
        cli: cli,
        requested: requested,
        isAndroidOverride: isAndroid,
      );
      expect(resolve(isPersonal: false), isFalse);
      expect(resolve(cli: CliTool.gemini), isFalse);
      expect(resolve(cli: null), isFalse);
      expect(resolve(requested: false), isFalse);
      expect(resolve(isAndroid: true), isFalse);
      expect(resolve(cli: CliTool.cursor, isAndroid: true), isFalse);
    });
  });

  group('buildWorkspaceConversationCreateRequest', () {
    final workspace = Workspace(workspaceId: 'ws', createdAt: 1);

    test('personal Codex with ACP requested sets request.acp', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.codex,
        acp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isTrue);
    });

    test('personal Claude with ACP requested sets request.acp', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isTrue);
    });

    test('defaults to acp false until the caller passes the settings flag', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        isAndroidOverride: false,
      );
      expect(request.acp, isFalse);
    });

    test('team create stays false even when acp is requested', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: false,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isFalse);
    });

    test('Android forces acp false', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: true,
      );
      expect(request.acp, isFalse);
    });
  });

  group('resolveMemberBindingAcp', () {
    test('mixed local Claude/Codex follow requested; Gemini always', () {
      bool resolve({
        CliTool? cli = CliTool.claude,
        TeamMode mode = TeamMode.mixed,
        String target = 'local',
        bool requested = true,
        bool android = false,
      }) => resolveMemberBindingAcp(
        cli: cli,
        teamMode: mode,
        targetId: target,
        requested: requested,
        isAndroidOverride: android,
      );

      expect(resolve(), isTrue);
      expect(resolve(requested: false), isFalse);
      expect(resolve(cli: CliTool.codex), isTrue);
      expect(resolve(cli: CliTool.gemini, requested: false), isTrue);
      expect(resolve(cli: CliTool.opencode), isFalse);
      expect(resolve(mode: TeamMode.native), isFalse);
      expect(resolve(target: 'ssh:prod'), isFalse);
      expect(resolve(target: 'wsl:ubuntu'), isFalse);
      expect(resolve(android: true), isFalse);
    });
  });

  group('shouldAttachMemberAcp', () {
    test('false when binding true but target is ssh', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        createdAt: 1,
        sessionTeam: 't1',
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'lead',
            taskId: 't',
            cli: CliTool.claude,
            acp: true,
          ),
        ],
      );
      const team = TeamProfile(
        id: 't1',
        name: 'T',
        teamMode: TeamMode.mixed,
        members: [TeamMemberConfig(id: 'lead', name: 'Lead')],
      );
      expect(
        shouldAttachMemberAcp(
          session: session,
          memberId: 'lead',
          team: team,
          targetId: 'ssh:prod',
          isAndroidOverride: false,
        ),
        isFalse,
      );
      expect(
        shouldAttachMemberAcp(
          session: session,
          memberId: 'lead',
          team: team,
          targetId: 'local',
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });
  });
}
