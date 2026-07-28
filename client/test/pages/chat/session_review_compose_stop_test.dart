import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/pages/chat/session_review_compose_card.dart';

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
          body: SessionReviewComposeCard(
            controller: textController,
            focusNode: focusNode,
            hint: 'Continue',
            canSubmit: true,
            onSubmit: () {},
            onChanged: (_) {},
            attachTooltip: 'Attach',
            enhanceTooltip: 'Enhance',
            voiceTooltip: 'Voice',
            voiceCancelTooltip: 'Cancel',
            voiceStopTooltip: 'Stop voice',
            isEnhancing: false,
            isVoiceListening: false,
            voiceElapsed: Duration.zero,
            voiceSoundLevel: 0,
            onAttach: () {},
            onEnhance: () {},
            onVoice: () {},
            onVoiceCancel: () {},
            onVoiceStop: () {},
            workspaceRoot: '/tmp',
            skills: const [],
            plugins: const [],
            slashBundle: const ConfigBundle(),
            showStop: showStop,
            onStop: onStop,
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

  testWidgets('shows send when showStop is false', (tester) async {
    await pumpCompose(tester: tester, showStop: false);

    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
  });
}
