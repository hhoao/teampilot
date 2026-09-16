import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
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

GitGraphState sampleState({
  required List<GitGraphRow> rows,
}) =>
    GitGraphState(
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
      flattenItems(specs).map((s) => s.value).whereType<GitCompareWorkingTree>(),
      hasLength(1),
    );
  });

  test('source commit hash is disabled; other commit and same-tip branch stay enabled', () {
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
    final feature = items.singleWhere((s) => s.value == const GitCompareRef('feature'));
    expect(sourceCommit.enabled, isFalse);
    expect(otherCommit.enabled, isTrue);
    expect(feature.enabled, isTrue);
  });

  test('source branch name is disabled in the branch list', () {
    final specs = gitCompareTargetSpecs(
      l10n: l10n,
      state: sampleState(rows: [commitA]),
      source: const GitCompareRef('feature'),
    );
    final items = flattenItems(specs);
    expect(
      items.singleWhere((s) => s.value == const GitCompareRef('feature')).enabled,
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
}
