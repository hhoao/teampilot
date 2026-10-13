import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/acp_compose_permission.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test(
    'willLaunchPersonalAcp is true for Gemini and for requested Claude desktop',
    () {
      expect(
        willLaunchPersonalAcp(
          isPersonal: true,
          cli: CliTool.gemini,
          requested: false,
        ),
        isTrue,
      );
      expect(
        willLaunchPersonalAcp(
          isPersonal: true,
          cli: CliTool.claude,
          requested: true,
        ),
        isTrue,
      );
      expect(
        willLaunchPersonalAcp(
          isPersonal: true,
          cli: CliTool.claude,
          requested: false,
        ),
        isFalse,
      );
      expect(
        willLaunchPersonalAcp(
          isPersonal: true,
          cli: CliTool.claude,
          requested: true,
          isAndroidOverride: true,
        ),
        isFalse,
      );
    },
  );

  group('showLandingAcpPermissionChip', () {
    test('true for Gemini personal desktop', () {
      expect(
        showLandingAcpPermissionChip(
          isPersonal: true,
          cli: CliTool.gemini,
          requested: false,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('false for PTY Claude personal when not requested', () {
      expect(
        showLandingAcpPermissionChip(
          isPersonal: true,
          cli: CliTool.claude,
          requested: false,
          isAndroidOverride: false,
        ),
        isFalse,
      );
    });

    test('true for personal Claude when requested', () {
      expect(
        showLandingAcpPermissionChip(
          isPersonal: true,
          cli: CliTool.claude,
          requested: true,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('false on Android', () {
      expect(
        showLandingAcpPermissionChip(
          isPersonal: true,
          cli: CliTool.gemini,
          requested: false,
          isAndroidOverride: true,
        ),
        isFalse,
      );
      expect(
        showLandingAcpPermissionChip(
          isPersonal: true,
          cli: CliTool.claude,
          requested: true,
          isAndroidOverride: true,
        ),
        isFalse,
      );
    });

    test('true when stamped mixed members have any acp', () {
      expect(
        showLandingAcpPermissionChip(
          isPersonal: false,
          cli: null,
          requested: false,
          stampedMembers: const [
            SessionMemberBinding(
              rosterMemberId: 'lead',
              taskId: 'task-lead',
              cli: CliTool.claude,
            ),
            SessionMemberBinding(
              rosterMemberId: 'gem',
              taskId: 'task-gem',
              cli: CliTool.gemini,
              acp: true,
            ),
          ],
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('false when all stamped members are PTY', () {
      expect(
        showLandingAcpPermissionChip(
          isPersonal: false,
          cli: null,
          requested: false,
          stampedMembers: const [
            SessionMemberBinding(
              rosterMemberId: 'lead',
              taskId: 'task-lead',
              cli: CliTool.claude,
            ),
            SessionMemberBinding(
              rosterMemberId: 'op',
              taskId: 'task-op',
              cli: CliTool.opencode,
            ),
          ],
          isAndroidOverride: false,
        ),
        isFalse,
      );
    });
  });

  group('acpComposePermissionControl', () {
    final l10n = AppLocalizationsEn();

    test('returns null when supported is fullAccess only', () {
      expect(
        acpComposePermissionControl(
          current: LaunchSecurityPolicy.fullAccess,
          supported: {LaunchSecurityPolicy.fullAccess},
          l10n: l10n,
          onSelected: (_) {},
        ),
        isNull,
      );
    });

    test('returns control with l10n labels when ask and fullAccess', () {
      final control = acpComposePermissionControl(
        current: LaunchSecurityPolicy.ask,
        supported: {LaunchSecurityPolicy.ask, LaunchSecurityPolicy.fullAccess},
        l10n: l10n,
        onSelected: (_) {},
      );

      expect(control, isNotNull);
      expect(control!.askLabel, l10n.acpPermissionAskLabel);
      expect(control.fullAccessLabel, l10n.acpPermissionFullAccessLabel);
      expect(control.defaultLabel, l10n.acpPermissionAskLabel);
      expect(control.launchSecurityPolicy, LaunchSecurityPolicy.ask);
    });
  });

  group('stampedLandingMembers', () {
    test('mixed Gemini member is stamped acp so landing chip can show', () {
      const team = TeamProfile(
        id: 'team-gem',
        name: 'Gem team',
        teamMode: TeamMode.mixed,
        members: [
          TeamMemberConfig(id: 'gem', name: 'Gem', cli: CliTool.gemini),
        ],
      );
      final workspace = Workspace(
        workspaceId: 'w1',
        folders: const [WorkspaceFolder(path: '/repo')],
        createdAt: 1,
      );
      final stamped = stampedLandingMembers(
        team: team,
        workspace: workspace,
        seedClaudeMemberAcp: false,
        seedCodexMemberAcp: false,
        seedCursorMemberAcp: false,
      );
      expect(stamped, isNotEmpty);
      expect(stamped.any((m) => m.acp), isTrue);
      expect(
        showLandingAcpPermissionChip(
          isPersonal: false,
          cli: null,
          requested: false,
          stampedMembers: stamped,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('native team members stay PTY', () {
      const team = TeamProfile(
        id: 'team-native',
        name: 'Native',
        members: [
          TeamMemberConfig(id: 'gem', name: 'Gem', cli: CliTool.gemini),
        ],
      );
      final workspace = Workspace(
        workspaceId: 'w1',
        folders: const [WorkspaceFolder(path: '/repo')],
        createdAt: 1,
      );
      final stamped = stampedLandingMembers(
        team: team,
        workspace: workspace,
        seedClaudeMemberAcp: true,
        seedCodexMemberAcp: true,
        seedCursorMemberAcp: true,
      );
      expect(stamped.any((m) => m.acp), isFalse);
    });
  });

  group('buildLandingAcpComposePermissionControl', () {
    final l10n = AppLocalizationsEn();
    final registry = CliToolRegistry.builtIn();

    test('non-null for Gemini personal desktop', () {
      expect(
        showLandingAcpPermissionChip(
          isPersonal: true,
          cli: CliTool.gemini,
          requested: false,
          isAndroidOverride: false,
        ),
        isTrue,
      );
      final control = buildLandingAcpComposePermissionControl(
        isPersonal: true,
        launchCli: CliTool.gemini,
        requested: false,
        stampedMembers: const [],
        current: LaunchSecurityPolicy.fullAccess,
        registry: registry,
        l10n: l10n,
        onSelected: (_) {},
        isAndroidOverride: false,
      );
      expect(control, isNotNull);
      expect(control!.askLabel, l10n.acpPermissionAskLabel);
    });

    test('null for PTY Claude personal when not requested', () {
      expect(
        buildLandingAcpComposePermissionControl(
          isPersonal: true,
          launchCli: CliTool.claude,
          requested: false,
          stampedMembers: const [],
          current: LaunchSecurityPolicy.fullAccess,
          registry: registry,
          l10n: l10n,
          onSelected: (_) {},
          isAndroidOverride: false,
        ),
        isNull,
      );
    });
  });

  group('buildSessionAcpComposePermissionControl', () {
    final l10n = AppLocalizationsEn();
    final registry = CliToolRegistry.builtIn();

    test('non-null for personal ACP Claude', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        cli: CliTool.claude,
        acp: true,
        acpPermission: LaunchSecurityPolicy.ask,
        createdAt: 1,
      );
      final control = buildSessionAcpComposePermissionControl(
        session: session,
        selectedMemberId: session.sessionId,
        registry: registry,
        l10n: l10n,
        onSelected: (_) {},
      );
      expect(control, isNotNull);
      expect(control!.launchSecurityPolicy, LaunchSecurityPolicy.ask);
      expect(control.askLabel, l10n.acpPermissionAskLabel);
    });

    test('null for personal PTY Claude', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        cli: CliTool.claude,
        acp: false,
        createdAt: 1,
      );
      expect(
        buildSessionAcpComposePermissionControl(
          session: session,
          selectedMemberId: session.sessionId,
          registry: registry,
          l10n: l10n,
          onSelected: (_) {},
        ),
        isNull,
      );
    });
  });
}
