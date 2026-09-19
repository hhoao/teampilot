import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_compare.dart';
import '../../models/git_graph.dart';
import '../git_compare/open_git_compare.dart';

List<TpActionMenuSpec> gitCompareTargetSpecs({
  required AppLocalizations l10n,
  required GitGraphState state,
  required GitCompareRef source,
}) {
  final locals = state.branches.where((b) => !b.isRemote);
  final remotes = state.branches.where((b) => b.isRemote);
  final commits = state.rows.whereType<GitCommitRow>();
  return [
    TpActionMenuSpec.item(
      value: const GitCompareWorkingTree(),
      icon: Icons.difference_outlined,
      label: l10n.gitGraphCompareWorkingTree(
        state.currentBranch.isEmpty ? 'HEAD' : state.currentBranch,
      ),
    ),
    const TpActionMenuSpec.divider(),
    if (locals.isNotEmpty) ...[
      _sectionHeader(Icons.call_split, l10n.gitGraphLocalBranches),
      TpActionMenuSpec.scroll(
        children: [
          for (final branch in locals)
            TpActionMenuSpec.item(
              value: GitCompareRef(branch.name),
              icon: Icons.call_split_outlined,
              label: branch.name,
              enabled: branch.name != source.nameOrHash,
            ),
        ],
      ),
    ],
    if (remotes.isNotEmpty) ...[
      _sectionHeader(Icons.cloud_outlined, l10n.gitGraphRemoteBranches),
      TpActionMenuSpec.scroll(
        children: [
          for (final branch in remotes)
            TpActionMenuSpec.item(
              value: GitCompareRef(branch.name),
              icon: Icons.cloud_outlined,
              label: branch.name,
              enabled: branch.name != source.nameOrHash,
            ),
        ],
      ),
    ],
    if (state.tags.isNotEmpty) ...[
      _sectionHeader(Icons.sell_outlined, l10n.gitGraphTags),
      TpActionMenuSpec.scroll(
        children: [
          for (final tag in state.tags)
            TpActionMenuSpec.item(
              value: GitCompareRef(tag.name),
              icon: Icons.sell_outlined,
              label: tag.name,
              enabled: tag.name != source.nameOrHash,
            ),
        ],
      ),
    ],
    if (commits.isNotEmpty) ...[
      _sectionHeader(Icons.commit, l10n.gitGraphCommits),
      TpActionMenuSpec.scroll(
        children: [
          for (final row in commits)
            TpActionMenuSpec.item(
              value: GitCompareRef(row.hash),
              icon: Icons.commit,
              label: '${GitCompareRef(row.hash).titleLabel()} ${row.subject}',
              enabled: row.hash != source.nameOrHash,
            ),
        ],
      ),
    ],
  ];
}

TpActionMenuSpec _sectionHeader(IconData icon, String label) =>
    TpActionMenuSpec.item(icon: icon, label: label, enabled: false);

Future<void> showGitCompareTargetMenu({
  required BuildContext context,
  required Offset globalPosition,
  required String workspaceId,
  required GitGraphState state,
  required GitCompareRef source,
}) async {
  if (!context.mounted) return;
  final l10n = context.l10n;
  final target = await showTpActionMenuOverlay<GitCompareSide>(
    context: context,
    globalPosition: globalPosition,
    useRootNavigator: true,
    transitionDuration: const Duration(milliseconds: 160),
    transitionCurve: Curves.easeOutCubic,
    menuBuilder: (overlayContext, complete) {
      final children = buildTpActionMenuChildren(
        context: overlayContext,
        specs: gitCompareTargetSpecs(l10n: l10n, state: state, source: source),
        menuController: TpActionMenuController(TpPopoverController()),
        onSelect: (value) => complete(value as GitCompareSide?),
      );
      return DecoratedBox(
        decoration: TpActionMenuMetrics.panelDecoration(overlayContext),
        child: Padding(
          padding: TpActionMenuMetrics.panelPadding,
          child: TpActionMenuPanel(
            minWidth: 200,
            menuAnchorShell: true,
            children: children,
          ),
        ),
      );
    },
  );
  if (target == null || !context.mounted) return;
  openGitCompareTab(
    context,
    workspaceId: workspaceId,
    spec: GitCompareSpec(repoRoot: state.repoRoot, left: source, right: target),
  );
}
