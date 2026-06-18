import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/member_detail_dialog.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders skills tab from a loaded detail', (tester) async {
    const detail = MemberConfigDetail(
      cli: CliTool.claude,
      resolvedDir: '/tp/.../claude',
      sourceLayer: MemberConfigSourceLayer.runtime,
      skills: [SkillEntry(name: 'alpha', description: 'does alpha')],
    );

    await tester.pumpWidget(_host(
      MemberDetailDialogBody(
        memberName: 'Backend',
        detail: detail,
        onOpenInFileManager: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(MemberDetailDialogBody)),
    );
    await tester.tap(find.text(l10n.memberDetailTabSkills));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('alpha'), findsOneWidget);
  });

  testWidgets('shows empty state when there is no config', (tester) async {
    const detail = MemberConfigDetail.none(cli: CliTool.claude);
    await tester.pumpWidget(_host(
      MemberDetailDialogBody(
        memberName: 'Backend',
        detail: detail,
        onOpenInFileManager: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MemberDetailDialogBody)),
    );
    expect(find.text(l10n.memberDetailEmpty), findsOneWidget);
  });

  testWidgets('shows a warning banner when a section failed to parse',
      (tester) async {
    const detail = MemberConfigDetail(
      cli: CliTool.claude,
      resolvedDir: '/x',
      sourceLayer: MemberConfigSourceLayer.runtime,
      warnings: [SectionWarning(section: 'settings', message: 'bad json')],
    );
    await tester.pumpWidget(_host(
      MemberDetailDialogBody(
        memberName: 'Backend',
        detail: detail,
        onOpenInFileManager: () {},
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MemberDetailDialogBody)),
    );
    // Switch to the Settings tab (last tab) and confirm the warning shows.
    await tester.tap(find.text(l10n.memberDetailTabSettings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.memberDetailLoadError), findsOneWidget);
  });
}
