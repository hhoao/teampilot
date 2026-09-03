import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/git_compare_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/diff_identity.dart';
import '../../models/git_compare.dart';
import '../../models/git_status.dart';
import '../../services/git/git_changes_visible_rows.dart';
import '../../services/git/git_history_service.dart';
import '../../services/storage/runtime_context.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../services/workspace/workspace_tools_scope_registry.dart';
import 'git_compare_file_tree.dart';

/// Floating / workbench Git Compare panel: header, changed-file tree, diff open.
class GitComparePane extends StatefulWidget {
  const GitComparePane({
    super.key,
    required this.workspaceId,
    required this.spec,
  });

  final String workspaceId;
  final GitCompareSpec spec;

  @override
  State<GitComparePane> createState() => _GitComparePaneState();
}

class _GitComparePaneState extends State<GitComparePane> {
  GitCompareCubit? _ownedCubit;
  WorkspaceToolsScopeRegistry? _registry;

  @override
  void initState() {
    super.initState();
    _listenRegistry(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenRegistry(context);
  }

  void _listenRegistry(BuildContext context) {
    WorkspaceToolsScopeRegistry? registry;
    try {
      registry = context.read<WorkspaceToolsScopeRegistry>();
    } catch (_) {
      return;
    }
    if (identical(registry, _registry)) return;
    _registry?.removeListener(_onRegistryChanged);
    _registry = registry;
    _onRegistryChanged();
    registry.addListener(_onRegistryChanged);
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _registry?.removeListener(_onRegistryChanged);
    _ownedCubit?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provided = _providedCubit(context);
    if (provided != null) {
      return BlocProvider.value(
        value: provided,
        child: _PaneBody(workspaceId: widget.workspaceId),
      );
    }

    final scopeCubit = _registry?.peek(widget.workspaceId);
    if (scopeCubit != null) {
      return BlocProvider<WorkspaceToolsScopeCubit>.value(
        value: scopeCubit,
        child: BlocBuilder<WorkspaceToolsScopeCubit, WorkspaceToolsScopeState>(
          builder: (context, state) {
            final ctx = _ctxFromState(state);
            if (ctx == null) {
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return BlocProvider.value(
              value: _cubitForContext(ctx),
              child: _PaneBody(workspaceId: widget.workspaceId),
            );
          },
        ),
      );
    }

    return const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  GitCompareCubit _cubitForContext(RuntimeContext ctx) {
    return _ownedCubit ??= GitCompareCubit(
      spec: widget.spec,
      history: GitHistoryService.forContext(ctx),
    )..load();
  }

  RuntimeContext? _ctxFromState(WorkspaceToolsScopeState state) {
    RuntimeContext? ctx;
    for (final slice in state.targetSlices) {
      if (slice.roots.contains(widget.spec.repoRoot)) {
        ctx = slice.tools.context;
        break;
      }
    }
    ctx ??= state.tools?.context;
    return ctx;
  }

  static GitCompareCubit? _providedCubit(BuildContext context) {
    try {
      return context.read<GitCompareCubit>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _PaneBody extends StatelessWidget {
  const _PaneBody({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GitCompareCubit, GitCompareState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(spec: state.spec),
            Expanded(child: _Content(state: state, workspaceId: workspaceId)),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.spec});

  final GitCompareSpec spec;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final title =
        '${_sideTitle(context, spec.left)} ↔ ${_sideTitle(context, spec.right)}';
    final subtitle = spec.right is GitCompareWorkingTree
        ? l10n.gitCompareSubtitle(spec.left.titleLabel())
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TpTextStyles.of(context).mdSemibold),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  static String _sideTitle(BuildContext context, GitCompareSide side) {
    if (side is GitCompareWorkingTree) {
      return context.l10n.gitCompareWorkingTree;
    }
    return side.titleLabel();
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.state, required this.workspaceId});

  final GitCompareState state;
  final String workspaceId;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.files.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final error = state.error;
    if (error != null) {
      return _LoadError(
        message: context.l10n.gitCompareLoadError,
        detail: error,
        onRetry: () => unawaited(context.read<GitCompareCubit>().refresh()),
      );
    }

    if (state.files.isEmpty) {
      return Center(
        child: Text(
          context.l10n.gitCompareEmpty,
          style: TpTextStyles.of(
            context,
          ).smColored(Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    final rows = visibleGitChangesRows(
      changes: state.files,
      expandedFolderPaths: state.expandedFolderPaths,
    );
    final cubit = context.read<GitCompareCubit>();

    return GitCompareFileTree(
      rows: rows,
      expandedFolderPaths: state.expandedFolderPaths,
      selectedPath: state.selectedPath,
      onToggleFolder: cubit.toggleFolder,
      onOpenFile: (change) => unawaited(_openFile(context, change)),
    );
  }

  Future<void> _openFile(BuildContext context, GitFileChange change) async {
    final cubit = context.read<GitCompareCubit>();
    final spec = cubit.state.spec;
    cubit.selectPath(change.path);
    final abs = p.join(spec.repoRoot, change.path);
    final identity = CompareDiffIdentity(
      absolutePath: abs,
      repoRoot: spec.repoRoot,
      left: spec.left,
      right: spec.right,
    );
    final text =
        await cubit.diffFor(
          change.path,
          fullContext: true,
        ) ??
        '';
    if (!context.mounted) return;
    context.read<WorkbenchEditorOpener>().openDiff(
      workspaceId: workspaceId,
      identity: identity,
      title: p.basename(change.path),
      diffText: text,
      reloadDiff: (ignoreWhitespace, fullContext) => cubit.diffFor(
        change.path,
        ignoreWhitespace: ignoreWhitespace,
        fullContext: fullContext,
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: cs.error),
            const SizedBox(height: 8),
            Text(message, style: TpTextStyles.of(context).smSemibold),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TpButton(
              variant: TpButtonVariant.outline,
              onPressed: onRetry,
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
