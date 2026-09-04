import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_graph_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/git_graph.dart';
import '../../widgets/diff/diff_viewer.dart';

/// 右侧详情栏：选中提交的元数据 + 文件列表；点击文件切换内嵌 diff 视图，
/// diff 文本由 cubit.openCommitFile 加载，渲染复用 widgets/diff/diff_viewer.dart。
class GitGraphDetailPane extends StatelessWidget {
  const GitGraphDetailPane({super.key, required this.onBack});

  /// 收起详情栏（清除当前选中提交）；宿主决定具体行为（如 `selectCommit(null)`）。
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GitGraphCubit, GitGraphState>(
      builder: (context, state) {
        if (state.detailLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final detail = state.commitDetail;
        if (detail == null) {
          return _EmptyHint(message: context.l10n.gitGraphSelectCommit);
        }
        final openPath = state.openFilePath;
        if (openPath != null) {
          return _FileDiffView(
            filePath: openPath,
            diffLoading: state.fileDiffLoading,
            diffText: state.fileDiffText ?? '',
          );
        }
        return _CommitSummary(detail: detail, onBack: onBack);
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TpTextStyles.of(
          context,
        ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _CommitSummary extends StatelessWidget {
  const _CommitSummary({required this.detail, required this.onBack});

  final GitCommitDetail detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail.subject,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TpTextStyles.of(context).mdBold,
                  ),
                ),
              ),
              TpIconButton(
                icon: Icons.close_rounded,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onTap: onBack,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: Text(
            '${detail.authorName} · '
            '${DateFormat.yMMMd(context.l10n.localeName).format(detail.authorDate.toLocal())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  detail.hash,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(
                    context,
                  ).xsColored(cs.onSurfaceVariant),
                ),
              ),
              TpIconButton(
                icon: Icons.copy_rounded,
                compact: true,
                tooltip: context.l10n.gitGraphHashCopied,
                onTap: () => unawaited(_copyHash(context)),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        Expanded(child: _FileList(files: detail.files)),
      ],
    );
  }

  Future<void> _copyHash(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: detail.hash));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(context.l10n.gitGraphHashCopied)));
  }
}

class _FileList extends StatelessWidget {
  const _FileList({required this.files});

  final List<GitCommitFileChange> files;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return _EmptyHint(message: context.l10n.diffNoChanges);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: files.length,
      itemBuilder: (context, index) => _FileRow(
        key: ValueKey('git-graph-file-${files[index].path}'),
        file: files[index],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({super.key, required this.file});

  final GitCommitFileChange file;

  String get _label => file.previousPath == null
      ? file.path
      : '${file.previousPath} → ${file.path}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (file.status) {
      GitCommitFileStatus.added => const Color(0xFF2EA043),
      GitCommitFileStatus.modified => const Color(0xFFB58900),
      GitCommitFileStatus.deleted => cs.error,
      GitCommitFileStatus.renamed => cs.primary,
      GitCommitFileStatus.typeChanged => Colors.purpleAccent,
    };
    return TpHover(
      onTap: () => context.read<GitGraphCubit>().openCommitFile(file),
      borderRadius: BorderRadius.circular(6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(switch (file.status) {
                GitCommitFileStatus.added => 'A',
                GitCommitFileStatus.modified => 'M',
                GitCommitFileStatus.deleted => 'D',
                GitCommitFileStatus.renamed => 'R',
                GitCommitFileStatus.typeChanged => 'T',
              }, style: TpTextStyles.of(context).xsBoldColored(color)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTextStyles.of(context).md,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileDiffView extends StatelessWidget {
  const _FileDiffView({
    required this.filePath,
    required this.diffLoading,
    required this.diffText,
  });

  final String filePath;
  final bool diffLoading;
  final String diffText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          child: Row(
            children: [
              TpIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onTap: () => context.read<GitGraphCubit>().closeFileDiff(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  filePath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).smSemibold,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
        Expanded(
          child: diffLoading
              ? const Center(child: CircularProgressIndicator())
              : DiffViewer.fromUnifiedDiff(
                  diffText: diffText,
                  filePath: filePath,
                ),
        ),
      ],
    );
  }
}
