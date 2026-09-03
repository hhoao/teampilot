import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:teampilot/cubits/editor_cubit.dart' show DiffReload;
import 'package:teampilot/cubits/git_compare_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/diff_identity.dart';
import 'package:teampilot/models/git_compare.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/pages/git_compare/git_compare_pane.dart';
import 'package:teampilot/services/git/git_history_service.dart';
import 'package:teampilot/services/git/git_service.dart' show GitException;
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

const _spec = GitCompareSpec(
  repoRoot: '/repo',
  left: GitCompareRef('abc1234def5678'),
  right: GitCompareWorkingTree(),
);

const _rootFile = GitFileChange(
  path: 'root.dart',
  kind: GitChangeKind.modified,
  staged: false,
);
const _nestedFile = GitFileChange(
  path: 'lib/src/nested.dart',
  kind: GitChangeKind.untracked,
  staged: false,
);

class _FakeHistory implements GitHistoryService {
  _FakeHistory({this.files = const [], this.diffText = 'diff text', this.error});

  List<GitFileChange> files;
  String diffText;
  Object? error;
  Future<void>? gate;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<GitFileChange>> listDiffFiles(
    String dir,
    GitCompareSide from,
    GitCompareSide to,
  ) async {
    final g = gate;
    if (g != null) await g;
    final err = error;
    if (err != null) throw GitException(err.toString());
    return files;
  }

  @override
  Future<String> fileDiff(
    String dir,
    GitCompareSide from,
    GitCompareSide to,
    String path, {
    bool ignoreWhitespace = false,
    bool fullContext = false,
    bool untracked = false,
  }) async => diffText;
}

class _RecordingOpener implements WorkbenchEditorOpener {
  final Map<String, Object?> calls = {};
  DiffReload? reload;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void openDiff({
    required String workspaceId,
    required DiffIdentity identity,
    required String title,
    required String diffText,
    DiffReload? reloadDiff,
    Future<void> Function()? onWorkingTreeWritten,
    bool preview = true,
  }) {
    calls['workspaceId'] = workspaceId;
    calls['identity'] = identity;
    calls['title'] = title;
    calls['diffText'] = diffText;
    reload = reloadDiff;
  }
}

Widget _host(
  GitCompareCubit cubit, {
  WorkbenchEditorOpener? opener,
  Locale? locale,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MultiProvider(
    providers: [
      BlocProvider.value(value: cubit),
      if (opener != null)
        Provider<WorkbenchEditorOpener>.value(value: opener),
    ],
    child: const Scaffold(
      body: SizedBox(
        width: 400,
        height: 600,
        child: GitComparePane(workspaceId: 'ws', spec: _spec),
      ),
    ),
  ),
);

GitCompareCubit _cubit(_FakeHistory history) =>
    GitCompareCubit(spec: _spec, history: history);

void main() {
  testWidgets('shows a spinner while the file list loads', (tester) async {
    final gate = Completer<void>();
    final history = _FakeHistory(files: const [_rootFile])..gate = gate.future;
    final cubit = _cubit(history);
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit));
    final loading = cubit.load();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await loading;
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows the empty hint when the sides are identical', (
    tester,
  ) async {
    final cubit = _cubit(_FakeHistory());
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit));
    await cubit.load();
    await tester.pumpAndSettle();

    expect(find.text('No differences'), findsOneWidget);
  });

  testWidgets('shows the load error with a retry that reloads', (tester) async {
    final history = _FakeHistory(error: 'boom');
    final cubit = _cubit(history);
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit));
    await cubit.load();
    await tester.pumpAndSettle();

    expect(find.text('Could not load differences'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);

    history.error = null;
    history.files = const [_rootFile];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load differences'), findsNothing);
    expect(find.text('root.dart'), findsOneWidget);
  });

  testWidgets('header labels the working tree side via l10n', (tester) async {
    final cubit = _cubit(_FakeHistory());
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit, locale: const Locale('zh')));
    await tester.pumpAndSettle();

    expect(find.textContaining('工作区'), findsWidgets);
    expect(find.textContaining('Working Tree'), findsNothing);
    // Long hashes shorten to the model's short form in the title.
    expect(find.textContaining('abc1234d'), findsWidgets);
  });

  testWidgets('renders nested files under expanded folders by default', (
    tester,
  ) async {
    final cubit = _cubit(_FakeHistory(files: const [_rootFile, _nestedFile]));
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit));
    await cubit.load();
    await tester.pumpAndSettle();

    expect(find.text('root.dart'), findsOneWidget);
    expect(find.text('nested.dart'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('src'), findsOneWidget);
    // Untracked entries keep their '?' badge in the single-section tree.
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('tapping a folder collapses its subtree', (tester) async {
    final cubit = _cubit(_FakeHistory(files: const [_nestedFile]));
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit));
    await cubit.load();
    await tester.pumpAndSettle();
    expect(find.text('nested.dart'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('git-compare-folder:lib')));
    await tester.pumpAndSettle();

    expect(find.text('nested.dart'), findsNothing);
    expect(find.text('src'), findsNothing);
    expect(find.text('lib'), findsOneWidget);
  });

  testWidgets('tapping a file opens a compare diff through the opener', (
    tester,
  ) async {
    final opener = _RecordingOpener();
    final history = _FakeHistory(
      files: const [_nestedFile],
      diffText: 'diff --git a/x b/x',
    );
    final cubit = _cubit(history);
    addTearDown(cubit.close);

    await tester.pumpWidget(_host(cubit, opener: opener));
    await cubit.load();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('git-compare-file:lib/src/nested.dart')),
    );
    await tester.pumpAndSettle();

    expect(opener.calls['workspaceId'], 'ws');
    expect(opener.calls['title'], 'nested.dart');
    expect(opener.calls['diffText'], 'diff --git a/x b/x');
    final identity = opener.calls['identity'];
    expect(identity, isA<CompareDiffIdentity>());
    expect(
      (identity as CompareDiffIdentity).storageKey,
      const CompareDiffIdentity(
        absolutePath: '/repo/lib/src/nested.dart',
        repoRoot: '/repo',
        left: GitCompareRef('abc1234def5678'),
        right: GitCompareWorkingTree(),
      ).storageKey,
    );
    expect(cubit.state.selectedPath, 'lib/src/nested.dart');

    // reloadDiff round-trips through the cubit so the diff view can toggle
    // whitespace / full context.
    history.diffText = 'reloaded';
    expect(await opener.reload!(true, false), 'reloaded');
  });
}
