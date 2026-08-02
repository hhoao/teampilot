import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/member_remote_provision_progress.dart';
import 'package:teampilot/pages/chat/chat_workbench_remote_provision_view.dart';
import 'package:teampilot/services/cli/installer_types.dart';

void main() {
  Widget wrap(Widget child) {
    final theme = ThemeData(useMaterial3: true);
    return TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: theme,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('hides ssh target id and session uuid from title', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ChatWorkbenchRemoteProvisionView(
          progress: MemberRemoteProvisionProgress(
            memberId: '327997c2-699f-4629-856c-931d974b0b70',
            phase: CliInstallPhase.syncingRemoteWorkspace,
            detail: 'manifest-flush',
            hostLabel: 'ssh:14f27968-1243-44f1-95cd-d17b48d06da9',
          ),
          memberLabel: '327997c2-699f-4629-856c-931d974b0b70',
        ),
      ),
    );

    expect(find.textContaining('ssh:'), findsNothing);
    expect(find.textContaining('327997c2'), findsNothing);
    expect(find.textContaining('14f27968'), findsNothing);
    expect(find.text('正在准备远程环境…'), findsOneWidget);
    expect(find.text('manifest-flush'), findsNothing);
    expect(find.text('正在同步远程工作区…'), findsOneWidget);
  });

  testWidgets('shows profile host name without member uuid', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ChatWorkbenchRemoteProvisionView(
          progress: MemberRemoteProvisionProgress(
            memberId: '327997c2-699f-4629-856c-931d974b0b70',
            phase: CliInstallPhase.syncingRemoteWorkspace,
            hostLabel: 'dev-box',
          ),
          memberLabel: '327997c2-699f-4629-856c-931d974b0b70',
        ),
      ),
    );

    expect(find.text('正在准备远程环境（dev-box）'), findsOneWidget);
    expect(find.textContaining('327997c2'), findsNothing);
  });
}
