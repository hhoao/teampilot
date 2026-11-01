import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace_card.dart';
import 'package:teampilot/repositories/session_repository.dart';

import '../../support/post_frame_test_harness.dart';

final _workspace = Workspace(
  workspaceId: 'p1',
  folders: const [WorkspaceFolder(path: '/tmp/p1')],
  display: 'Original',
  createdAt: 1,
);

/// Records metadata writes instead of hitting the repository.
class _RenameRecordingCubit extends ChatCubit {
  _RenameRecordingCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
      );

  final renamed = <String, String?>{};

  @override
  Future<void> updateWorkspaceMetadata(
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    bool? rootSandboxEnvOptIn,
    bool? injectSessionSshMcp,
  }) async {
    renamed[workspaceId] = display;
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('rename from the hover overflow menu applies the new name', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final chatCubit = _RenameRecordingCubit();
    addTearDown(chatCubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<SessionRepository>.value(
              value: SessionRepository(storage: testHomeStorage),
            ),
          ],
          child: BlocProvider<ChatCubit>.value(
            value: chatCubit,
            child: Scaffold(
              body: SizedBox(
                width: 320,
                height: 220,
                child: WorkspaceCard(
                  workspace: _workspace,
                  sessionCount: 0,
                  favorited: false,
                  onToggleFavorite: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(WorkspaceCard)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename workspace'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Renamed');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(chatCubit.renamed['p1'], 'Renamed');
    debugDefaultTargetPlatformOverride = null;
  });
}
