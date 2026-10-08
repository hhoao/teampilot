import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/models/git_compare.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_compare_targets.dart';

import '../../support/git_graph_test_fakes.dart';

List<TpActionMenuSpec> flattenItems(List<TpActionMenuSpec> specs) {
  final out = <TpActionMenuSpec>[];
  for (final spec in specs) {
    if (spec.isDivider) continue;
    if (spec.isScrollBlock) {
      out.addAll(spec.scrollChildren!);
    } else {
      out.add(spec);
    }
  }
  return out;
}

GitGraphState sampleState({required List<GitGraphRow> rows}) => GitGraphState(
  repoRoot: '/repo',
  currentBranch: 'main',
  branches: const [
    GitBranchInfo('main', 'h0', isRemote: false, isCurrent: true),
    GitBranchInfo('feature', 'h1', isRemote: false, isCurrent: false),
    GitBranchInfo('origin/main', 'h0', isRemote: true, isCurrent: false),
  ],
  tags: const [GitTagInfo('v1.0', 'h1')],
  rows: rows,
);

void main() {
  final l10n = AppLocalizationsEn();
  final commitA = graphCommitRow('aaaaaaaaaaaaaaaa');
  final commitB = graphCommitRow('bbbbbbbbbbbbbbbb');

  test('order is working tree, refs, then loaded commits; spacers skipped', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(
        rows: [
          commitA,
          const GitGraphSpacerRow(edges: []),
          commitB,
        ],
      ),
      source: GitCompareRef(commitA.hash),
    );
    final labels = flattenItems(specs).map((s) => s.label).toList();
    expect(labels, [
      'Working Tree (main)',
      'Local branches',
      'main',
      'feature',
      'Remote branches',
      'origin/main',
      'Tags',
      'v1.0',
      'Commits',
      'aaaaaaaa ${commitA.subject}',
      'bbbbbbbb ${commitB.subject}',
    ]);
    expect(
      flattenItems(
        specs,
      ).map((s) => s.value).whereType<GitCompareWorkingTree>(),
      hasLength(1),
    );
  });

  test(
    'source commit hash is disabled; other commit and same-tip branch stay enabled',
    () {
      final specs = gitCompareTargetSpecs(
        l10n: l10n,
        state: sampleState(rows: [commitA, commitB]),
        source: GitCompareRef(commitA.hash),
      );
      final items = flattenItems(specs);
      final sourceCommit = items.singleWhere(
        (s) => s.value == GitCompareRef(commitA.hash),
      );
      final otherCommit = items.singleWhere(
        (s) => s.value == GitCompareRef(commitB.hash),
      );
      final feature = items.singleWhere(
        (s) => s.value == const GitCompareRef('feature'),
      );
      expect(sourceCommit.enabled, isFalse);
      expect(otherCommit.enabled, isTrue);
      expect(feature.enabled, isTrue);
    },
  );

  test('source branch name is disabled in the branch list', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: [commitA]),
      source: const GitCompareRef('feature'),
    );
    final items = flattenItems(specs);
    expect(
      items
          .singleWhere((s) => s.value == const GitCompareRef('feature'))
          .enabled,
      isFalse,
    );
    expect(
      items.singleWhere((s) => s.value == GitCompareRef(commitA.hash)).enabled,
      isTrue,
    );
  });

  test('omits empty commit group', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: const []),
      source: const GitCompareRef('feature'),
    );
    expect(flattenItems(specs).any((s) => s.label == 'Commits'), isFalse);
  });

  test('filterQuery keeps working tree and matching refs only', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: [commitA, commitB]),
      source: const GitCompareRef('feature'),
      filterQuery: 'v1.0',
    );
    final labels = flattenItems(specs).map((s) => s.label).toList();
    expect(labels.first, 'Working Tree (main)');
    expect(labels, contains('v1.0'));
    expect(labels, isNot(contains('feature')));
    expect(labels, isNot(contains('origin/main')));
  });

  test('filterQuery matches commit hash prefix and subject', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: [commitA, commitB]),
      source: const GitCompareRef('feature'),
      filterQuery: commitB.hash.substring(0, 8),
    );
    final labels = flattenItems(specs).map((s) => s.label).toList();
    expect(
      labels.where((l) => l?.startsWith('bbbbbbbb') ?? false),
      hasLength(1),
    );
    expect(labels.any((l) => l?.startsWith('aaaaaaaa') ?? false), isFalse);
  });

  test('filterQuery with no matches shows empty row after working tree', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: [commitA]),
      source: const GitCompareRef('feature'),
      filterQuery: 'no-such-ref',
    );
    final labels = flattenItems(specs).map((s) => s.label).toList();
    expect(labels, ['Working Tree (main)', 'No matches']);
  });

  testWidgets('compare overlay search field has Material ancestor', (tester) async {
    final branches = [
      for (var i = 0; i < 11; i++)
        GitBranchInfo('branch-$i', 'h$i', isRemote: false, isCurrent: i == 0),
    ];
    final state = GitGraphState(
      repoRoot: '/repo',
      currentBranch: 'branch-0',
      branches: branches,
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showGitCompareTargetMenu(
                  context: context,
                  globalPosition: const Offset(120, 120),
                  workspaceId: 'ws',
                  state: state,
                  source: const GitCompareRef('branch-0'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });
}
