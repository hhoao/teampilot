import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_thread.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  testWidgets(
    'laterMessages render after a divider and rewind uses that commit',
    (tester) async {
      final runtime = ExternalStoreAiThreadRuntime()
        ..setMessages([
          const AiMessage(
            id: 'm1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'live one')],
          ),
          const AiMessage(
            id: 'm2',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'live two')],
          ),
        ]);
      const later = AiMessage(
        id: 'm3',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'ghost later')],
      );
      String? rewound;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          theme: ThemeData(extensions: [AiMessageTheme.test()]),
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: SessionHistoryThread(
                runtime: runtime,
                hasOlder: false,
                isLoadingOlder: false,
                checkpointCommits: const {'m3': 'commit-later'},
                laterMessages: const [later],
                onRewindTo: (commit) => rewound = commit,
                onForkFrom: (_) {},
              ),
            ),
          ),
        ),
      );
      await pumpUntilSettled(tester);

      expect(
        find.byKey(kSessionHistoryLaterCheckpointDividerKey),
        findsOneWidget,
      );
      expect(find.text('ghost later'), findsOneWidget);
      expect(find.text('live two'), findsOneWidget);

      final laterCenter = tester.getCenter(find.text('ghost later'));
      final liveCenter = tester.getCenter(find.text('live two'));
      final dividerCenter = tester.getCenter(
        find.byKey(kSessionHistoryLaterCheckpointDividerKey),
      );
      expect(dividerCenter.dy, greaterThan(liveCenter.dy));
      expect(laterCenter.dy, greaterThan(dividerCenter.dy));

      await tester.tap(find.byTooltip('Rewind to here'));
      expect(rewound, 'commit-later');
    },
  );
}
