import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_detail_pane.dart';
import 'package:teampilot/widgets/diff/diff_viewer.dart';

import '../../support/git_graph_test_fakes.dart';

GitCommitDetail detail() => GitCommitDetail(
  hash: 'c1',
  parents: const ['p0'],
  authorName: 'Ann',
  authorEmail: 'ann@x',
  authorDate: DateTime.utc(2026, 8, 25),
  subject: 'subj',
  body: 'body',
  files: const [GitCommitFileChange('a.dart', GitCommitFileStatus.modified)],
);

void main() {
  testWidgets(
    'shows metadata and file list; tapping file opens embedded diff',
    (tester) async {
      final history = FakeHistoryForGraph(
        rows: [graphCommitRow('c1')],
        detail: detail(),
      );
      final cubit = GitGraphCubit(
        history: history,
        git: FakeGitForGraph(repoStatus()),
      );
      await cubit.setRepoRoot('/repo');
      await cubit.selectCommit('c1');

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider.value(
            value: cubit,
            child: Scaffold(body: GitGraphDetailPane(onBack: () {})),
          ),
        ),
      );
      expect(find.text('subj'), findsWidgets);
      expect(find.text('a.dart'), findsOneWidget);

      await tester.tap(find.text('a.dart'));
      await tester.pumpAndSettle();
      expect(cubit.state.openFilePath, 'a.dart');
      expect(find.byType(DiffViewer), findsOneWidget);
      await cubit.close();
    },
  );
}
