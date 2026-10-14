import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  late Directory tmp;
  late SessionRepository repo;
  late String workspaceId;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fs_session_repo_acp_');
    repo = SessionRepository(rootDir: tmp.path, storage: fakeHomeStorage());
    final ws = await repo.createWorkspace([
      WorkspaceFolder(path: '/repo/main'),
    ]);
    workspaceId = ws.workspaceId;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('personal Claude acp true persists true', () async {
    final session = (await repo.createSession(
      workspaceId,
      cli: CliTool.claude,
      acp: true,
    )).session;
    expect(session.acp, isTrue);
  });

  test('personal Claude acp true persists ask permission', () async {
    final session = (await repo.createSession(
      workspaceId,
      cli: CliTool.claude,
      acp: true,
      acpPermission: LaunchSecurityPolicy.ask,
    )).session;
    expect(session.acpPermission, LaunchSecurityPolicy.ask);

    final loaded = await repo.loadSessionsForWorkspace(workspaceId);
    final reloaded = loaded.singleWhere(
      (s) => s.sessionId == session.sessionId,
    );
    expect(reloaded.acpPermission, LaunchSecurityPolicy.ask);
  });

  test('personal Claude default persists false', () async {
    final session = (await repo.createSession(
      workspaceId,
      cli: CliTool.claude,
    )).session;
    expect(session.acp, isFalse);
  });

  test('personal Claude acp false persists fullAccess permission', () async {
    final session = (await repo.createSession(
      workspaceId,
      cli: CliTool.claude,
      acp: false,
      acpPermission: LaunchSecurityPolicy.ask,
    )).session;
    expect(session.acp, isFalse);
    expect(session.acpPermission, LaunchSecurityPolicy.fullAccess);
  });

  test('personal Gemini persists true even when acp is false', () async {
    final session = (await repo.createSession(
      workspaceId,
      cli: CliTool.gemini,
      acp: false,
    )).session;
    expect(session.acp, isTrue);
  });

  test(
    'personal Gemini acp false + acpPermission ask persists ask',
    () async {
      final session = (await repo.createSession(
        workspaceId,
        cli: CliTool.gemini,
        acp: false,
        acpPermission: LaunchSecurityPolicy.ask,
      )).session;
      expect(session.acp, isTrue);
      expect(session.acpPermission, LaunchSecurityPolicy.ask);

      final loaded = await repo.loadSessionsForWorkspace(workspaceId);
      final reloaded = loaded.singleWhere(
        (s) => s.sessionId == session.sessionId,
      );
      expect(reloaded.acp, isTrue);
      expect(reloaded.acpPermission, LaunchSecurityPolicy.ask);
    },
  );

  test('team session persists false even when acp is true', () async {
    final session = (await repo.createSession(
      workspaceId,
      sessionTeam: 'team-1',
      rosterMembers: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      memberClis: const {'team-lead': CliTool.claude},
      cli: CliTool.gemini,
      acp: true,
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'team-lead',
          taskId: 'task-lead',
          cli: CliTool.claude,
          acp: true,
        ),
      ],
    )).session;
    expect(session.acp, isFalse);
    expect(session.members.first.acp, isTrue);
  });

  test(
    'mixed local Gemini plan path persists binding acp and keeps session acp false',
    () async {
      final created = await repo.createSession(
        workspaceId,
        sessionTeam: 'team-1',
        rosterMembers: const [TeamMemberConfig(id: 'gem', name: 'Gem')],
        memberClis: const {'gem': CliTool.gemini},
        teamMode: TeamMode.mixed,
      );
      final loaded = await repo.loadSessionsForWorkspace(workspaceId);
      final session = loaded.singleWhere(
        (s) => s.sessionId == created.session.sessionId,
      );
      expect(session.acp, isFalse);
      expect(session.members.single.cli, CliTool.gemini);
      expect(session.members.single.acp, isTrue);
    },
  );

  test('mixed local Claude plan path follows seedClaudeMemberAcp', () async {
    final on = (await repo.createSession(
      workspaceId,
      sessionTeam: 'team-claude-on',
      rosterMembers: const [TeamMemberConfig(id: 'lead', name: 'Lead')],
      memberClis: const {'lead': CliTool.claude},
      teamMode: TeamMode.mixed,
    )).session;
    expect(on.acp, isFalse);
    expect(on.members.single.acp, isTrue);

    final off = (await repo.createSession(
      workspaceId,
      sessionTeam: 'team-claude-off',
      rosterMembers: const [TeamMemberConfig(id: 'lead', name: 'Lead')],
      memberClis: const {'lead': CliTool.claude},
      teamMode: TeamMode.mixed,
      seedClaudeMemberAcp: false,
    )).session;
    expect(off.members.single.acp, isFalse);
  });

  test('mixed local Codex plan path follows seedCodexMemberAcp', () async {
    final on = (await repo.createSession(
      workspaceId,
      sessionTeam: 'team-codex-on',
      rosterMembers: const [TeamMemberConfig(id: 'lead', name: 'Lead')],
      memberClis: const {'lead': CliTool.codex},
      teamMode: TeamMode.mixed,
    )).session;
    expect(on.acp, isFalse);
    expect(on.members.single.acp, isTrue);

    final off = (await repo.createSession(
      workspaceId,
      sessionTeam: 'team-codex-off',
      rosterMembers: const [TeamMemberConfig(id: 'lead', name: 'Lead')],
      memberClis: const {'lead': CliTool.codex},
      teamMode: TeamMode.mixed,
      seedCodexMemberAcp: false,
    )).session;
    expect(off.members.single.acp, isFalse);
  });

  test(
    'mixed local Claude plan path stamps binding ask and keeps session fullAccess',
    () async {
      final created = await repo.createSession(
        workspaceId,
        sessionTeam: 'team-claude-ask',
        rosterMembers: const [TeamMemberConfig(id: 'lead', name: 'Lead')],
        memberClis: const {'lead': CliTool.claude},
        teamMode: TeamMode.mixed,
        acpPermission: LaunchSecurityPolicy.ask,
      );
      expect(created.session.acp, isFalse);
      expect(created.session.acpPermission, LaunchSecurityPolicy.fullAccess);
      expect(created.session.members.single.acp, isTrue);
      expect(
        created.session.members.single.acpPermission,
        LaunchSecurityPolicy.ask,
      );

      final loaded = await repo.loadSessionsForWorkspace(workspaceId);
      final session = loaded.singleWhere(
        (s) => s.sessionId == created.session.sessionId,
      );
      expect(session.acp, isFalse);
      expect(session.acpPermission, LaunchSecurityPolicy.fullAccess);
      expect(session.members.single.acpPermission, LaunchSecurityPolicy.ask);
    },
  );

  test('native Gemini plan path keeps binding acp false', () async {
    final session = (await repo.createSession(
      workspaceId,
      sessionTeam: 'team-1',
      rosterMembers: const [TeamMemberConfig(id: 'gem', name: 'Gem')],
      memberClis: const {'gem': CliTool.gemini},
      teamMode: TeamMode.native,
    )).session;
    expect(session.acp, isFalse);
    expect(session.members.single.acp, isFalse);
  });
}
