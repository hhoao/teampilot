import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kSecondaryMouseButton;
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

  // Builds a folder tile wrapped in a MaterialApp + BlocProvider for the
  // (required) GitCubit ancestor. Returns the cubit via `onCubit` so callers
  // can close it in addTearDown.
  Widget buildTile({
    required int subtreeSelectedCount,
    required int subtreeTotalCount,
    VoidCallback? onStage,
    VoidCallback? onUnstage,
    VoidCallback? onDiscardFolder,
    ValueChanged<GitCubit>? onCubit,
  }) {
    final cubit = GitCubit(service: _FolderGitStub())..setRepoRoot('/repo');
    onCubit?.call(cubit);
    return MaterialApp(
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
              subtreeSelectedCount: subtreeSelectedCount,
              subtreeTotalCount: subtreeTotalCount,
              cubit: cubit,
              onStage: onStage ?? () {},
              onUnstage: onUnstage ?? () {},
              onDiscardFolder: onDiscardFolder ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('folder checkbox is checked when all staged', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTile(subtreeSelectedCount: 2, subtreeTotalCount: 2),
      );
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isTrue);
    });
  });

  testWidgets('folder checkbox is tri-state when partially staged', (
    tester,
  ) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTile(subtreeSelectedCount: 1, subtreeTotalCount: 2),
      );
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isNull);
    });
  });

  testWidgets('folder checkbox unchecked when none staged', (tester) async {
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTile(subtreeSelectedCount: 0, subtreeTotalCount: 2),
      );
      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isFalse);
    });
  });

  testWidgets('folder context menu discards folder', (tester) async {
    var discardCalls = 0;
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTile(
          subtreeSelectedCount: 0,
          subtreeTotalCount: 1,
          onDiscardFolder: () => discardCalls++,
        ),
      );
      final center = tester.getCenter(find.byType(GitChangeFolderTile));
      final gesture = await tester.startGesture(
        center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Discard changes in folder'));
      await tester.pump();
      expect(discardCalls, 1);
    });
  });
}
