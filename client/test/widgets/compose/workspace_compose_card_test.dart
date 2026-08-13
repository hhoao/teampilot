import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/services/compose/compose_clip.dart';
import 'package:teampilot/services/compose/compose_file_drop_ingestor.dart';
import 'package:teampilot/widgets/compose/compose_at_file_chip_row.dart';
import 'package:teampilot/widgets/compose/compose_paste_clip_bar.dart';
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
    ComposeClip? clip,
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
          clip: clip,
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

  testWidgets('empty input shows voice in trailing slot; text shows send', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(pumpCard(chrome: unboundChrome, controller: controller));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

    controller.text = 'hello';
    await tester.pump();

    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_outlined), findsNothing);
  });

  testWidgets('renders paste clip bar only while clip is collapsed', (
    tester,
  ) async {
    final clip = ComposeClip();
    addTearDown(clip.dispose);

    await tester.pumpWidget(
      pumpCard(chrome: unboundChrome, clip: clip),
    );
    expect(find.byType(ComposePasteClipBar), findsNothing);

    clip.setPasted('a\nb\nc');
    await tester.pump();
    expect(find.byType(ComposePasteClipBar), findsOneWidget);
    expect(find.textContaining('3 lines'), findsOneWidget);

    clip.clear();
    await tester.pump();
    expect(find.byType(ComposePasteClipBar), findsNothing);
  });

  testWidgets('at-file chips scan the collapsed block text', (tester) async {
    final clip = ComposeClip();
    addTearDown(clip.dispose);

    await tester.pumpWidget(
      pumpCard(chrome: unboundChrome, clip: clip),
    );
    clip.setPasted('see @lib/main.dart inside the block');
    await tester.pump();

    expect(find.byType(ComposeAtFileChipRow), findsOneWidget);
  });
}

void _noop(Object? _) {}
void _noopBool(bool _) {}
void _noopString(String _) {}
