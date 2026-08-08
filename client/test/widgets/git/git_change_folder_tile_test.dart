import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/widgets/git/git_change_folder_tile.dart';

class _FolderGitStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    branch: 'main',
  );

  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

void main() {
  // TpHover renders its desktop (GestureDetector + animated fill) path on a
  // desktop platform. flutter_test defaults to Android, which would render the
  // touch (InkWell) path with no onHoverChanged callback. The override must be
  // reset inside the test body (before flutter_test's invariant check runs), so
  // it is set/reset via try/finally rather than setUp/tearDown.
  Future<void> runOnDesktop(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('folder hover shows right-aligned stage button', (tester) async {
    await runOnDesktop(tester, () async {
      final cubit = GitCubit(service: _FolderGitStub())..setRepoRoot('/repo');
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(
              body: SizedBox(
                width: 400,
                height: 36,
                child: GitChangeFolderTile(
                  folderPath: 'src',
                  name: 'src',
                  depth: 0,
                  cubit: cubit,
                  onStage: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.byType(GitChangeFolderTile)));
      await tester.pump();

      expect(find.byIcon(Icons.add), findsOneWidget);
      final rowRect = tester.getRect(find.byType(GitChangeFolderTile).first);
      final btnRect = tester.getRect(find.byIcon(Icons.add));
      expect(rowRect.right - btnRect.right, lessThan(16));
    });
  });
}
