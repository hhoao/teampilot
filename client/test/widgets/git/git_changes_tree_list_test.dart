import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/widgets/git/git_change_tile.dart';
import 'package:teampilot/widgets/git/git_changes_tree_list.dart';

class _TreeStub extends GitService {
  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => GitRepoStatus(
    isRepository: true,
    branch: 'main',
    staged: const [
      GitFileChange(path: 'a.java', kind: GitChangeKind.added, staged: true),
    ],
    unstaged: const [
      GitFileChange(
        path: 'b.dart',
        kind: GitChangeKind.modified,
        staged: false,
      ),
    ],
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

  Widget buildTreeList({
    required GitCubit cubit,
    String? selectedPath,
    ValueChanged<String>? onSelect,
  }) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit, // folder tiles read expanded state via context
          child: Scaffold(
            body: GitChangesTreeList(
              treeView: cubit.state.changesTreeView,
              cubit: cubit,
              listScrollController: ScrollController(),
              horizontalScrollController: ScrollController(),
              selectedPath: selectedPath,
              onSelect: onSelect ?? (_) {},
              onOpenDiff: (_) {},
              onConfirmDiscard: (_) {},
              onOpenFile: (_) {},
            ),
          ),
        ),
      );

  testWidgets('renders Changes root header with count and rows', (
    tester,
  ) async {
    final cubit = GitCubit(service: _TreeStub());
    addTearDown(cubit.close);
    // Fully await the initial status load (a fire-and-forget cascade +
    // `refresh()` coalescing would capture an empty treeView).
    await cubit.setRepoRoot('/repo');
    final treeView = cubit.state.changesTreeView;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit, // folder tiles read expanded state via context
          child: Scaffold(
            body: GitChangesTreeList(
              treeView: treeView,
              cubit: cubit,
              listScrollController: ScrollController(),
              horizontalScrollController: ScrollController(),
              selectedPath: null,
              onSelect: (_) {},
              onOpenDiff: (_) {},
              onConfirmDiscard: (_) {},
              onOpenFile: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Changes'), findsOneWidget);
    expect(find.byType(Checkbox), findsWidgets); // root select-all + file row
    // both file rows rendered
    expect(find.text('a.java'), findsOneWidget);
    expect(find.text('b.dart'), findsOneWidget);
  });

  testWidgets('single click on a row calls onSelect with the change path', (
    tester,
  ) async {
    final cubit = GitCubit(service: _TreeStub());
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');
    final selected = <String>[];
    await runOnDesktop(tester, () async {
      await tester.pumpWidget(
        buildTreeList(cubit: cubit, onSelect: (path) => selected.add(path)),
      );
      await tester.pump();

      await tester.tap(find.text('a.java'));
      // Both onTap and onDoubleTap registered → tap fires after the
      // double-tap window expires.
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, ['a.java']);
    });
  });

  testWidgets('selectedPath highlights the matching file row', (tester) async {
    final cubit = GitCubit(service: _TreeStub());
    addTearDown(cubit.close);
    await cubit.setRepoRoot('/repo');
    await tester.pumpWidget(
      buildTreeList(cubit: cubit, selectedPath: 'a.java'),
    );
    await tester.pump();

    GitChangeTile tileOf(String name) => tester.widget<GitChangeTile>(
      find.ancestor(
        of: find.text(name),
        matching: find.byType(GitChangeTile),
      ),
    );
    expect(tileOf('a.java').selected, isTrue);
    expect(tileOf('b.dart').selected, isFalse);
  });

  testWidgets(
    'root select-all is checked when all selected; tapping it clears the selection',
    (tester) async {
      final cubit = GitCubit(service: _TreeStub());
      addTearDown(cubit.close);
      await cubit.setRepoRoot('/repo'); // a.java + b.dart auto-selected
      await tester.pumpWidget(buildTreeList(cubit: cubit));
      await tester.pump();

      // Root header is the first sliver, so its checkbox is first in tree order.
      final rootCheckbox = tester.widget<Checkbox>(find.byType(Checkbox).first);
      expect(rootCheckbox.value, isTrue);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      // selectNone is a pure selection op now (no git), so the selection clears.
      expect(cubit.state.selectedPaths, isEmpty);
    },
  );
}
