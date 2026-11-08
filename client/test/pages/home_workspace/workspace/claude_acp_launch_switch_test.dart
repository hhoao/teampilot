import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/claude_acp_launch_switch.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';
import 'package:teampilot/services/chat/launch/session/launch_acp_policy.dart';

void main() {
  group('resolveAcpOnTarget', () {
    test('true for desktop Claude, Cursor, Codex and OpenCode', () {
      for (final cli in [
        CliTool.claude,
        CliTool.cursor,
        CliTool.codex,
        CliTool.opencode,
      ]) {
        expect(
          resolveAcpOnTarget(
            cli: cli,
            requested: true,
            targetId: 'local',
          ),
          isTrue,
          reason: '$cli should honour the ACP preference on desktop',
        );
      }
    });

    test('false when not requested, null, or on WSL', () {
      expect(
        resolveAcpOnTarget(
          cli: CliTool.claude,
          requested: false,
          targetId: 'local',
        ),
        isFalse,
      );
      expect(
        resolveAcpOnTarget(
          cli: CliTool.gemini,
          requested: true,
          targetId: 'ssh:prod',
        ),
        isTrue,
        reason: 'Gemini is ACP-only on a supported target',
      );
      expect(
        resolveAcpOnTarget(cli: null, requested: true, targetId: 'local'),
        isFalse,
      );
      expect(
        resolveAcpOnTarget(
          cli: CliTool.claude,
          requested: true,
          targetId: 'wsl:Ubuntu',
        ),
        isFalse,
      );
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
      );
      expect(request.acp, isTrue);
    });

    test('personal OpenCode with ACP requested sets request.acp', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.opencode,
        acp: true,
      );
      expect(request.acp, isTrue);
    });

    test('personal Claude with ACP requested sets request.acp', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        acp: true,
      );
      expect(request.acp, isTrue);
    });

    test('defaults to acp false until the caller passes the settings flag', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
      );
      expect(request.acp, isFalse);
    });

    test('team create with a null cli never sets request.acp', () {
      // Production passes `identity?.cli`, which is null for team creates;
      // team ACP is seeded per member instead.
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: false,
        cli: null,
        acp: true,
      );
      expect(request.acp, isFalse);
    });

    test('request carries the user preference for the repository to resolve', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        acp: true,
      );
      expect(request.acp, isTrue);
    });

    test('team create copies CLI seeds and leaves request.acp false', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: false,
        cli: null,
        acp: true,
        seedClaudeMemberAcp: true,
        seedCodexMemberAcp: true,
        seedCursorMemberAcp: true,
        seedOpencodeMemberAcp: true,
      );
      expect(request.acp, isFalse);
      expect(request.seedClaudeMemberAcp, isTrue);
      expect(request.seedCodexMemberAcp, isTrue);
      expect(request.seedCursorMemberAcp, isTrue);
      expect(request.seedOpencodeMemberAcp, isTrue);
    });

    test('team create seed defaults match preference defaults', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: false,
        cli: CliTool.claude,
      );
      expect(request.acp, isFalse);
      expect(request.seedClaudeMemberAcp, isTrue);
      expect(request.seedCodexMemberAcp, isTrue);
      expect(request.seedCursorMemberAcp, isTrue);
      expect(request.seedOpencodeMemberAcp, isTrue);
    });
  });

  group('resolveMemberBindingAcp', () {
    test('follows requested on local / ssh / termux; Gemini always', () {
      bool resolve({
        CliTool? cli = CliTool.claude,
        bool requested = true,
        String targetId = 'local',
      }) => resolveMemberBindingAcp(
        targetId: targetId,
        cli: cli,
        requested: requested,
      );

      expect(resolve(), isTrue);
      expect(resolve(requested: false), isFalse);
      expect(resolve(cli: CliTool.codex), isTrue);
      expect(resolve(cli: CliTool.gemini, requested: false), isTrue);
      expect(resolve(cli: CliTool.opencode), isTrue);
      expect(resolve(cli: CliTool.opencode, requested: false), isFalse);
      expect(resolve(cli: CliTool.flashskyai), isFalse);
      expect(resolve(targetId: 'ssh:prod'), isTrue);
      expect(resolve(targetId: 'termux:default'), isTrue);
    });

    test('WSL has no ACP transport, so its seats stay PTY', () {
      expect(
        resolveMemberBindingAcp(
          targetId: 'wsl:Ubuntu',
          cli: CliTool.claude,
          requested: true,
        ),
        isFalse,
      );
      expect(
        resolveMemberBindingAcp(
          targetId: 'wsl:Ubuntu',
          cli: CliTool.gemini,
          requested: true,
        ),
        isFalse,
        reason: 'ACP-only CLIs still need an ACP transport on the target',
      );
    });
  });

  group('stampMemberAcp', () {
    SessionMemberBinding member(CliTool cli, String id) =>
        SessionMemberBinding(rosterMemberId: id, taskId: 'task-$id', cli: cli);

    List<SessionMemberBinding> stamp({
      required List<SessionMemberBinding> members,
      Map<String, String>? targets,
      bool seedClaude = true,
      bool seedCodex = false,
      bool seedCursor = true,
      bool seedOpencode = true,
      LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess,
    }) => stampMemberAcp(
      members: members,
      memberTargets:
          targets ?? {for (final m in members) m.rosterMemberId: 'local'},
      seedClaudeMemberAcp: seedClaude,
      seedCodexMemberAcp: seedCodex,
      seedCursorMemberAcp: seedCursor,
      seedOpencodeMemberAcp: seedOpencode,
      acpPermission: acpPermission,
    );

    test('Claude follows seed on mixed local and stays false when off', () {
      expect(
        stamp(
          members: [member(CliTool.claude, 'lead')],
          seedClaude: true,
        ).single.acp,
        isTrue,
      );
      expect(
        stamp(
          members: [member(CliTool.claude, 'lead')],
          seedClaude: false,
        ).single.acp,
        isFalse,
      );
    });

    test('Gemini is true even when both Claude and Codex seeds are false', () {
      expect(
        stamp(
          members: [member(CliTool.gemini, 'gem')],
          seedClaude: false,
          seedCodex: false,
          seedCursor: false,
        ).single.acp,
        isTrue,
      );
    });

    test('Cursor follows seedCursorMemberAcp', () {
      expect(
        stamp(
          members: [member(CliTool.cursor, 'cursor')],
          seedCursor: true,
        ).single.acp,
        isTrue,
      );
      expect(
        stamp(
          members: [member(CliTool.cursor, 'cursor')],
          seedCursor: false,
        ).single.acp,
        isFalse,
      );
    });

    test('OpenCode follows seedOpencodeMemberAcp', () {
      expect(
        stamp(
          members: [member(CliTool.opencode, 'oc')],
          seedOpencode: true,
        ).single.acp,
        isTrue,
      );
      expect(
        stamp(
          members: [member(CliTool.opencode, 'oc')],
          seedOpencode: false,
        ).single.acp,
        isFalse,
      );
    });

    test('SSH and native seats follow the seed; WSL seats do not', () {
      expect(
        stamp(
          members: [member(CliTool.claude, 'lead')],
          targets: const {'lead': 'ssh:prod'},
        ).single.acp,
        isTrue,
      );
      expect(
        stamp(
          members: [member(CliTool.gemini, 'gem')],
          targets: const {'gem': 'ssh:prod'},
        ).single.acp,
        isTrue,
      );
      expect(
        stamp(
          members: [member(CliTool.claude, 'wsl')],
          targets: const {'wsl': 'wsl:Ubuntu'},
        ).single.acp,
        isFalse,
      );
    });

    test('ACP seats receive acpPermission seed; PTY seats omit it', () {
      final mixed = stamp(
        members: [
          member(CliTool.claude, 'lead'),
          member(CliTool.flashskyai, 'pty'),
        ],
        seedClaude: true,
        acpPermission: LaunchSecurityPolicy.ask,
      );
      expect(mixed.first.acp, isTrue);
      expect(mixed.first.acpPermission, LaunchSecurityPolicy.ask);
      expect(mixed.last.acp, isFalse);
      expect(mixed.last.acpPermission, LaunchSecurityPolicy.fullAccess);
    });
  });

  group('shouldAttachMemberAcp', () {
    test('attaches for a local seat that is ACP', () {
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
      expect(
        shouldAttachMemberAcp(
          session: session,
          memberId: 'lead',
          targetId: 'local',
        ),
        isTrue,
      );
    });

    test('OpenCode attaches for an SSH seat that is ACP', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        createdAt: 1,
        sessionTeam: 't1',
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'lead',
            taskId: 't',
            cli: CliTool.opencode,
            acp: true,
          ),
        ],
      );
      expect(
        shouldAttachMemberAcp(
          session: session,
          memberId: 'lead',
          targetId: 'ssh:prod',
        ),
        isTrue,
      );
    });

    test('does not attach an ACP seat placed on WSL', () {
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
      expect(
        shouldAttachMemberAcp(
          session: session,
          memberId: 'lead',
          targetId: 'wsl:Ubuntu',
        ),
        isFalse,
      );
    });
  });
}
