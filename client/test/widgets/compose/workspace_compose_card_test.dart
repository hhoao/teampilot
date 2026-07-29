import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/compose/compose_file_drop_ingestor.dart';
import 'package:teampilot/widgets/compose/compose_at_file_chip_row.dart';
import 'package:teampilot/widgets/compose/compose_chrome.dart';
import 'package:teampilot/widgets/compose/compose_file_drop_region.dart';
import 'package:teampilot/widgets/compose/compose_trigger_field.dart';
import 'package:teampilot/widgets/compose/workspace_compose_card.dart';

void main() {
  Widget pumpCard({
    required ComposeChrome chrome,
    bool deferFieldMount = false,
    TextEditingController? controller,
    FocusNode? focusNode,
    ValueChanged<String>? onOpenAtFile,
  }) {
    final resolvedController = controller ?? TextEditingController();
    if (controller == null) addTearDown(resolvedController.dispose);
    final resolvedFocusNode = focusNode ?? FocusNode();
    if (focusNode == null) addTearDown(resolvedFocusNode.dispose);
    final dropTarget = ComposeFileDropIngestor(
      workspaceRoot: '/tmp',
      onInsertReferences: (_) {},
    );

    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: WorkspaceComposeCard(
          controller: resolvedController,
          focusNode: resolvedFocusNode,
          hint: 'Ask anything',
          canSubmit: false,
          onSubmit: () {},
          onChanged: (_) {},
          chrome: chrome,
          dropTarget: dropTarget,
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
          deferFieldMount: deferFieldMount,
          onOpenAtFile: onOpenAtFile,
        ),
      ),
    );
  }

  const unboundChrome = UnboundComposeChrome(
    conversationModeLabel: 'Simple',
    autoChipLabel: 'Preset',
    dangerouslySkipPermissions: false,
    defaultPermissionsLabel: 'Default',
    fullAccessPermissionsLabel: 'Full',
    conversationModeSpecs: [],
    autoChipSpecs: [],
    onConversationModeSelected: _noop,
    onAutoChipSelected: _noop,
    onPermissionSelected: _noopBool,
  );

  const boundChrome = BoundComposeChrome(
    identityLabel: 'Team',
    identityIcon: Icons.groups_outlined,
    modelPresetLabel: 'Model',
    emptyPresetHintLabel: 'No presets',
    onPresetSelected: _noopString,
  );

  testWidgets('unbound chrome shows conversation mode label and drop region', (
    tester,
  ) async {
    await tester.pumpWidget(pumpCard(chrome: unboundChrome));
    await tester.pumpAndSettle();

    expect(find.text('Simple'), findsOneWidget);
    expect(find.byType(ComposeFileDropRegion), findsOneWidget);
  });

  testWidgets(
    'bound chrome shows identity label and model preset chip, no mode labels',
    (tester) async {
      await tester.pumpWidget(pumpCard(chrome: boundChrome));
      await tester.pumpAndSettle();

      expect(find.text('Team'), findsOneWidget);
      expect(find.text('Model'), findsOneWidget);
      expect(find.text('Simple'), findsNothing);
    },
  );

  testWidgets('deferFieldMount true wraps field in TpDeferredMountShell', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpCard(chrome: unboundChrome, deferFieldMount: true),
    );

    expect(find.byType(TpDeferredMountShell), findsOneWidget);
    // Tests mount the child immediately (FLUTTER_TEST).
    expect(find.byType(ComposeTriggerField), findsOneWidget);
  });

  testWidgets('deferFieldMount false does not wrap field in deferred shell', (
    tester,
  ) async {
    await tester.pumpWidget(pumpCard(chrome: unboundChrome));

    expect(find.byType(TpDeferredMountShell), findsNothing);
    expect(find.byType(ComposeTriggerField), findsOneWidget);
  });

  testWidgets('shows at-file chip row when controller has @ refs', (
    tester,
  ) async {
    final controller = TextEditingController(text: '@src/main.dart hello');
    addTearDown(controller.dispose);
    final opened = <String>[];

    await tester.pumpWidget(
      pumpCard(
        chrome: unboundChrome,
        controller: controller,
        onOpenAtFile: opened.add,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ComposeAtFileChipRow), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(ComposeAtFileChipRow),
        matching: find.text('main.dart'),
      ),
    );
    expect(opened.single, '/tmp/src/main.dart');
  });

  testWidgets('bound chrome shows launch error banner', (tester) async {
    await tester.pumpWidget(
      pumpCard(
        chrome: const BoundComposeChrome(
          identityLabel: 'Team',
          launchError: 'Something went wrong',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
  });
}

void _noop(Object? _) {}
void _noopBool(bool _) {}
void _noopString(String _) {}
