import 'package:teampilot/models/launch_security_policy.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/pages/chat/session_history_review_submit.dart';
import 'package:teampilot/services/compose/compose_file_drop_ingestor.dart';
import 'package:teampilot/widgets/compose/compose_chrome.dart';
import 'package:teampilot/widgets/compose/compose_file_drop_region.dart';
import 'package:teampilot/widgets/compose/workspace_compose_card.dart';

void main() {
  group('shouldSwitchToTerminalAfterChatSubmit', () {
    test('false keeps Chat', () {
      expect(shouldSwitchToTerminalAfterChatSubmit(false), isFalse);
    });
    test('true switches to Terminal', () {
      expect(shouldSwitchToTerminalAfterChatSubmit(true), isTrue);
    });
  });

  group('History continue submit re-entrancy', () {
    test('lock rejects overlapping submit while in flight', () async {
      final lock = HistoryContinueSubmitLock();
      final gate = Completer<void>();
      var calls = 0;

      final first = lock.run(() async {
        calls++;
        await gate.future;
        return const HistoryContinueSubmitResult(
          ok: true,
          channel: HistoryContinueChannel.pty,
        );
      });
      // Second call while first is awaiting must not run the action.
      final second = await lock.run(() async {
        calls++;
        return const HistoryContinueSubmitResult(
          ok: true,
          channel: HistoryContinueChannel.pty,
        );
      });
      expect(second.ok, isFalse);
      expect(calls, 1);
      expect(lock.isBusy, isTrue);

      gate.complete();
      expect((await first).ok, isTrue);
      expect(lock.isBusy, isFalse);
      expect(calls, 1);
    });

    testWidgets('compose send is disabled while isSubmitting', (tester) async {
      var submits = 0;
      final textController = TextEditingController(text: 'hello');
      final focusNode = FocusNode();
      addTearDown(textController.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceComposeCard(
              controller: textController,
              focusNode: focusNode,
              hint: 'Continue',
              canSubmit: true,
              isSubmitting: true,
              onSubmit: () => submits++,
              onChanged: (_) {},
              chrome: const BoundComposeChrome(
                identityLabel: 'Simple',
                modelPresetLabel: 'Model',
                emptyPresetHintLabel: 'No presets',
                onPresetSelected: _noopString,
                launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
                defaultPermissionsLabel: 'Default',
                fullAccessPermissionsLabel: 'Full access',
                onPermissionSelected: _noopPolicy,
              ),
              dropTarget: ComposeFileDropIngestor(
                workspaceRoot: '/tmp',
                onInsertReferences: (_) {},
              ),
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
              deferFieldMount: false,
            ),
          ),
        ),
      );

      expect(find.byType(ComposeFileDropRegion), findsOneWidget);

      await tester.tap(find.byType(CircularProgressIndicator));
      await tester.pump();
      expect(submits, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

void _noopString(String _) {}
void _noopBool(bool _) {}
void _noopPolicy(LaunchSecurityPolicy _) {}
