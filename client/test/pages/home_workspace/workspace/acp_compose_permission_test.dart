import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/acp_compose_permission.dart';

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
}
