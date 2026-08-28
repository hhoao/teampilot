import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/compose/compose_file_drop_ingestor.dart';
import 'package:teampilot/widgets/compose/compose_chrome.dart';
import 'package:teampilot/widgets/compose/workspace_compose_card.dart';

void main() {
  Future<void> pumpCompose({
    required WidgetTester tester,
    required bool showStop,
    VoidCallback? onStop,
  }) async {
    final textController = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(textController.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WorkspaceComposeCard(
            controller: textController,
            focusNode: focusNode,
            hint: 'Continue',
            canSubmit: true,
            onSubmit: () {},
            onChanged: (_) {},
            chrome: BoundComposeChrome(
              identityLabel: 'Team',
              identityIcon: Icons.groups_outlined,
              showStop: showStop,
              onStop: onStop,
            ),
            dropTarget: ComposeFileDropIngestor(
              workspaceRoot: '/tmp',
              onInsertReferences: (_) {},
            ),
            attachTooltip: 'Attach',
            voiceTooltip: 'Voice',
            voiceCancelTooltip: 'Cancel',
            voiceStopTooltip: 'Stop voice',
            isVoiceListening: false,
            voiceElapsed: Duration.zero,
            voiceSoundLevel: 0,
            onAttach: () {},
            onVoice: () {},
            onVoiceCancel: () {},
            onVoiceStop: () {},
            workspaceRoot: '/tmp',
            skills: const [],
            plugins: const [],
            slashBundle: const ConfigBundle(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows stop icon and tooltip when showStop is true', (
    tester,
  ) async {
    await pumpCompose(tester: tester, showStop: true, onStop: () {});

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byTooltip('Stop generating'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
  });

  testWidgets('tap stop invokes onStop', (tester) async {
    var stopCalls = 0;
    await pumpCompose(
      tester: tester,
      showStop: true,
      onStop: () => stopCalls++,
    );

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    expect(stopCalls, 1);
  });

  testWidgets('second tap on stop is ignored while still showing stop', (
    tester,
  ) async {
    var stopCalls = 0;
    await pumpCompose(
      tester: tester,
      showStop: true,
      onStop: () => stopCalls++,
    );

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();
    expect(stopCalls, 1);
  });

  testWidgets('shows send when showStop is false and input has text', (
    tester,
  ) async {
    final textController = TextEditingController(text: 'hello');
    addTearDown(textController.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: WorkspaceComposeCard(
            controller: textController,
            focusNode: focusNode,
            hint: 'Continue',
            canSubmit: true,
            onSubmit: () {},
            onChanged: (_) {},
            chrome: const BoundComposeChrome(
              identityLabel: 'Team',
              identityIcon: Icons.groups_outlined,
            ),
            dropTarget: ComposeFileDropIngestor(
              workspaceRoot: '/tmp',
              onInsertReferences: (_) {},
            ),
            attachTooltip: 'Attach',
            voiceTooltip: 'Voice',
            voiceCancelTooltip: 'Cancel',
            voiceStopTooltip: 'Stop voice',
            isVoiceListening: false,
            voiceElapsed: Duration.zero,
            voiceSoundLevel: 0,
            onAttach: () {},
            onVoice: () {},
            onVoiceCancel: () {},
            onVoiceStop: () {},
            workspaceRoot: '/tmp',
            skills: const [],
            plugins: const [],
            slashBundle: const ConfigBundle(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_outlined), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
  });

  testWidgets('shows voice when showStop is false and input is empty', (
    tester,
  ) async {
    await pumpCompose(tester: tester, showStop: false);

    expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
  });
}
