import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/chat_outline.dart';
import 'package:teampilot/pages/chat/chat_outline_rail.dart';

void main() {
  testWidgets('ChatOutlineHost is absent when show is false', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            ChatOutlineHost(
              show: false,
              entries: const [
                ChatOutlineEntry(id: 'u0', messageIndex: 0, preview: 'x'),
              ],
              activeId: active,
              onLocate: (_) {},
            ),
          ],
        ),
      ),
    );
    expect(find.byKey(kChatOutlineHostKey), findsNothing);
  });

  testWidgets('ChatOutlineHost mounts the rail when show is true', (
    tester,
  ) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.blue),
          scale: 1,
        ),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Stack(
            children: [
              ChatOutlineHost(
                show: true,
                entries: const [
                  ChatOutlineEntry(id: 'u0', messageIndex: 0, preview: 'hello'),
                ],
                activeId: active,
                onLocate: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(kChatOutlineRailKey), findsOneWidget);
  });
}
