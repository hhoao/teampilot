import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/team_generation_builder_status.dart';

Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

Future<TeamGenerationBuilderStatus> pumpStatus(
  WidgetTester tester, {
  required String phase,
  bool profilePersisted = false,
  String? errorCode,
  VoidCallback? onRetry,
  VoidCallback? onCancel,
  VoidCallback? onOpenLeadSession,
  VoidCallback? onConfirmArrived,
  VoidCallback? onSendAgain,
}) async {
  final widget = TeamGenerationBuilderStatus(
    phase: phase,
    teamName: 'Delivery Team',
    previewLines: const [
      'Lead · claude-strong · Local',
      'Worker ×2 · codex-fast · Build SSH',
      '2 skills · 1 plugin · 1 MCP server',
    ],
    profilePersisted: profilePersisted,
    errorCode: errorCode,
    onRetry: onRetry,
    onCancel: onCancel,
    onOpenLeadSession: onOpenLeadSession,
    onConfirmArrived: onConfirmArrived,
    onSendAgain: onSendAgain,
  );
  await tester.pumpWidget(wrap(widget));
  return widget;
}

void main() {
  testWidgets('status is rendered only for a team-generation session shape',
      (tester) async {
    await pumpStatus(tester, phase: 'probing');
    expect(find.text('Team Builder'), findsOneWidget);
    expect(find.text('Checking machines and CLIs…'), findsOneWidget);
  });

  testWidgets('valid plan shows roles, presets, resources, and machines',
      (tester) async {
    await pumpStatus(tester, phase: 'validating');
    expect(find.text('Delivery Team'), findsOneWidget);
    expect(find.text('Lead · claude-strong · Local'), findsOneWidget);
    expect(find.text('Worker ×2 · codex-fast · Build SSH'), findsOneWidget);
    expect(find.text('2 skills · 1 plugin · 1 MCP server'), findsOneWidget);
  });

  testWidgets('pre-commit failure offers Retry and Cancel', (tester) async {
    var retried = false;
    await pumpStatus(
      tester,
      phase: 'failed',
      onRetry: () => retried = true,
      onCancel: () {},
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Cancel generation'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('profile-persisted failure cannot cancel and retries forward',
      (tester) async {
    await pumpStatus(
      tester,
      phase: 'failed',
      profilePersisted: true,
      onRetry: () {},
    );
    expect(find.text('Cancel generation'), findsNothing);
    expect(find.text('Continue setup'), findsOneWidget);
  });

  testWidgets('ambiguous prompt offers inspect, arrived, and guarded resend',
      (tester) async {
    await pumpStatus(
      tester,
      phase: 'failed',
      errorCode: 'prompt_delivery_unknown',
      onOpenLeadSession: () {},
      onConfirmArrived: () {},
      onSendAgain: () {},
    );
    expect(find.text('Open lead session'), findsOneWidget);
    expect(find.text('It arrived'), findsOneWidget);
    expect(find.text('Send again…'), findsOneWidget);
  });

  testWidgets('committing phase hides cancel (post-profile boundary)',
      (tester) async {
    await pumpStatus(tester, phase: 'committing', onCancel: () {});
    expect(find.text('Cancel generation'), findsNothing);
  });
}
