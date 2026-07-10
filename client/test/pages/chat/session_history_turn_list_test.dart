import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session_history_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_history_turn_list.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('loading shows history loading copy not session starting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SessionHistoryTurnList(
          state: SessionHistoryState(status: SessionHistoryViewStatus.loading),
          onRetry: _noop,
        ),
      ),
    );

    expect(find.text('Loading conversation history…'), findsOneWidget);
    expect(find.text('Starting session…'), findsNothing);
  });

  testWidgets('empty shows empty copy', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SessionHistoryTurnList(
          state: SessionHistoryState(status: SessionHistoryViewStatus.empty),
          onRetry: _noop,
        ),
      ),
    );

    expect(
      find.text('No prior messages for this member yet.'),
      findsOneWidget,
    );
  });

  testWidgets('error shows message and retry invokes callback', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _wrap(
        SessionHistoryTurnList(
          state: const SessionHistoryState(
            status: SessionHistoryViewStatus.error,
            errorMessage: 'disk failed',
          ),
          onRetry: () => retries++,
        ),
      ),
    );

    expect(find.textContaining('disk failed'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('ready renders user and assistant markdown', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SessionHistoryTurnList(
          state: SessionHistoryState(
            status: SessionHistoryViewStatus.ready,
            turns: [
              SessionHistoryTurn(
                role: SessionHistoryRole.user,
                markdown: 'Hello user turn',
              ),
              SessionHistoryTurn(
                role: SessionHistoryRole.assistant,
                markdown: 'Hello **assistant**',
              ),
            ],
          ),
          onRetry: _noop,
        ),
      ),
    );

    expect(find.text('Hello user turn'), findsOneWidget);
    expect(find.textContaining('assistant'), findsWidgets);
  });

  testWidgets('tool turns start collapsed', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SessionHistoryTurnList(
          state: SessionHistoryState(
            status: SessionHistoryViewStatus.ready,
            turns: [
              SessionHistoryTurn(
                role: SessionHistoryRole.tool,
                markdown: 'tool body secret',
                toolName: 'Bash',
                collapsedByDefault: true,
              ),
            ],
          ),
          onRetry: _noop,
        ),
      ),
    );

    expect(find.text('Bash'), findsOneWidget);
    expect(find.text('tool body secret'), findsNothing);
  });
}

void _noop() {}
