import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_file_drop_ingestor.dart';
import 'package:teampilot/widgets/compose/compose_chrome.dart';
import 'package:teampilot/widgets/compose/compose_trigger_field.dart';
import 'package:teampilot/widgets/compose/workspace_compose_card.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import '../../support/post_frame_test_harness.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Widget pumpComposeCard({
    required String? expertChipLabel,
    ValueChanged<Object?>? onExpertChipSelected,
    bool deferFieldMount = true,
  }) {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: WorkspaceComposeCard(
          controller: controller,
          focusNode: focusNode,
          hint: 'Ask anything',
          isSubmitting: false,
          canSubmit: false,
          onSubmit: () {},
          onChanged: (_) {},
          chrome: UnboundComposeChrome(
            conversationModeLabel: 'Simple',
            autoChipLabel: 'Preset',
            conversationModeSpecs: const [],
            autoChipSpecs: const [],
            onConversationModeSelected: (_) {},
            onAutoChipSelected: (_) {},
            expertChipLabel: expertChipLabel,
            expertChipSpecs: expertChipLabel == null
                ? const []
                : const [
                    TpActionMenuSpec.item(
                      icon: Icons.person_off_outlined,
                      label: 'No expert',
                    ),
                  ],
            onExpertChipSelected: onExpertChipSelected,
          ),
          dropTarget: ComposeFileDropIngestor(
            workspaceRoot: '/tmp',
            onInsertReferences: (_) {},
            usesPosixPaths: false,
          ),
          attachTooltip: 'Attach',
          voiceTooltip: 'Voice',
          voiceCancelTooltip: 'Cancel',
          voiceStopTooltip: 'Stop',
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
          deferFieldMount: deferFieldMount,
        ),
      ),
    );
  }

  testWidgets('expert chip visible in simple mode', (tester) async {
    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: pumpComposeCard(
          expertChipLabel: 'No expert',
          onExpertChipSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No expert'), findsOneWidget);
    expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
  });

  testWidgets('defers compose field behind TpDeferredMountShell', (
    tester,
  ) async {
    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: pumpComposeCard(expertChipLabel: null),
      ),
    );

    expect(find.byType(TpDeferredMountShell), findsOneWidget);
    // Tests mount the child immediately (FLUTTER_TEST).
    expect(find.byType(ComposeTriggerField), findsOneWidget);
  });

  testWidgets('expert chip hidden in team mode', (tester) async {
    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: pumpComposeCard(
          expertChipLabel: null,
          onExpertChipSelected: null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No expert'), findsNothing);
    expect(find.byIcon(Icons.psychology_outlined), findsNothing);
  });
}
