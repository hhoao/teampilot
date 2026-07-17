import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart';
import 'package:teampilot/widgets/compose/compose_trigger_field.dart';
import 'package:teampilot/widgets/deferred_mount_shell.dart';

void main() {
  Widget pumpComposeCard({
    required String? expertChipLabel,
    ValueChanged<Object?>? onExpertChipSelected,
  }) {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: WorkspaceChatLandingComposeCard(
          controller: controller,
          focusNode: focusNode,
          hint: 'Ask anything',
          isSubmitting: false,
          canSubmit: false,
          onSubmit: () {},
          onChanged: (_) {},
          conversationModeLabel: 'Simple',
          autoChipLabel: 'Preset',
          dangerouslySkipPermissions: false,
          defaultPermissionsLabel: 'Default permissions',
          fullAccessPermissionsLabel: 'Full access',
          conversationModeSpecs: const [],
          autoChipSpecs: const [],
          onConversationModeSelected: (_) {},
          onAutoChipSelected: (_) {},
          onPermissionSelected: (_) {},
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
          attachTooltip: 'Attach',
          enhanceTooltip: 'Enhance',
          voiceTooltip: 'Voice',
          voiceCancelTooltip: 'Cancel',
          voiceStopTooltip: 'Stop',
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
        ),
      ),
    );
  }

  testWidgets('expert chip visible in simple mode', (tester) async {
    await tester.pumpWidget(
      pumpComposeCard(
        expertChipLabel: 'No expert',
        onExpertChipSelected: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No expert'), findsOneWidget);
    expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
  });

  testWidgets(
    'defers compose field behind DeferredMountShell',
    (tester) async {
      await tester.pumpWidget(pumpComposeCard(expertChipLabel: null));

      expect(find.byType(DeferredMountShell), findsOneWidget);
      // Tests mount the child immediately (FLUTTER_TEST).
      expect(find.byType(ComposeTriggerField), findsOneWidget);
    },
  );

  testWidgets('expert chip hidden in team mode', (tester) async {
    await tester.pumpWidget(
      pumpComposeCard(
        expertChipLabel: null,
        onExpertChipSelected: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No expert'), findsNothing);
    expect(find.byIcon(Icons.psychology_outlined), findsNothing);
  });
}
