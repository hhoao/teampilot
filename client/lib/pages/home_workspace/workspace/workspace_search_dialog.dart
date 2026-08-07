import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../services/file_tree/workspace_file_search.dart';
import '../../../services/search/workspace_search_indexes.dart';
import '../../../services/session/workspace_session_content_index.dart';
import '../../../services/workbench/workbench_editor_opener.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/session/workspace_sessions.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_session_actions.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../services/workspace/workspace_pane_policy.dart';

/// Result-count caps shown in the dialog.
const _maxFileResults = 50;
const _maxContentResults = 20;
const _maxRecentSessions = 8;

/// Opens the workspace search dialog, which searches conversation sessions
/// (by title and by transcript content) and workspace files by name. Reads the
/// current session list, CLI fallback title, and shared search indexes from
/// [context] up front; selecting a result pops the dialog and performs the
/// action against the still-mounted [context].
///
/// No-ops if a search dialog is already open (e.g. repeated shortcut presses).
Future<void> showWorkspaceSearchDialog(
  BuildContext context, {
  required Workspace workspace,
}) async {
  if (_workspaceSearchDialogOpen) return;
  _workspaceSearchDialogOpen = true;
  try {
    final chatCubit = context.read<ChatCubit>();
    final opener = context.read<WorkbenchEditorOpener>();
    final indexes = context.read<WorkspaceSearchIndexes>();
    final fallback = context.l10n.defaultNewChatSessionTitle;
    final sessions = sessionsForWorkspace(workspace, chatCubit.state.sessions);

    await showTpDialog<void>(
      context: context,
      presentation: TpDialogPresentation.page,
      mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
      maxWidth: 560,
      maxHeight: 560,
      builder: (dialogContext) => WorkspaceSearchDialog(
        workspace: workspace,
        sessions: sessions,
        indexes: indexes,
        emptyTitleFallback: fallback,
        onOpenSession: (session) async {
          Navigator.of(dialogContext).pop();
          if (!context.mounted) return;
          // Awaited by SidebarSessionTile before a needs-you jump.
          await openWorkspaceSessionTab(context, workspace, session);
        },
        onOpenFile: (path) {
          Navigator.of(dialogContext).pop();
          unawaited(opener.openFile(workspace.workspaceId, path));
        },
      ),
    );
  } finally {
    _workspaceSearchDialogOpen = false;
  }
}

var _workspaceSearchDialogOpen = false;

/// Centered modal that filters sessions (title + transcript content) and
/// workspace files for name matches. Pure UI: result actions are delegated to
/// callbacks, and searches hit the shared [WorkspaceSearchIndexes] so files and
/// transcripts are indexed once per workspace instead of re-walking on every
/// keystroke.
class WorkspaceSearchDialog extends StatefulWidget {
  const WorkspaceSearchDialog({
    required this.workspace,
    required this.sessions,
    required this.indexes,
    required this.emptyTitleFallback,
    required this.onOpenSession,
    required this.onOpenFile,
    super.key,
  });

  final Workspace workspace;
  final List<AppSession> sessions;
  final WorkspaceSearchIndexes indexes;
  final String emptyTitleFallback;
  final FutureOr<void> Function(AppSession session) onOpenSession;
  final ValueChanged<String> onOpenFile;

  @override
  State<WorkspaceSearchDialog> createState() => _WorkspaceSearchDialogState();
}

class _WorkspaceSearchDialogState extends State<WorkspaceSearchDialog> {
  final _controller = TextEditingController();
  late final String _debounceTag =
      'workspace_search_${widget.workspace.workspaceId}_${identityHashCode(this)}';

  var _query = '';
  var _searchingFiles = false;
  var _fileResultsTruncated = false;
  var _contentResultsTruncated = false;
  List<WorkspaceFileMatch> _fileMatches = const [];
  List<WorkspaceSessionContentMatch> _contentMatches = const [];

  /// True while the transcript content index is warming (dialog open or first
  /// query after staleness). Set optimistically so the very first frame shows
  /// the indexing hint; cleared when the background warm completes.
  var _contentIndexing = true;

  /// Bumped per search; stale async results are discarded.
  var _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_warmIndexes());
  }

  @override
  void dispose() {
    Debounces.cancel(_debounceTag);
    _controller.dispose();
    super.dispose();
  }

  /// Warm the shared file + transcript content indexes in the background so the
  /// first query is served from memory.
  Future<void> _warmIndexes() async {
    final indexes = widget.indexes;
    final workspaceId = widget.workspace.workspaceId;
    final contentWarm = indexes
        .contentIndexFor(workspaceId)
        .warm(sessions: widget.sessions);
    final root = widget.workspace.firstFolderPath;
    final fileWarm = root.isEmpty
        ? Future<void>.value()
        : indexes.fileIndexFor(root).ensureFresh();
    try {
      await contentWarm;
      await fileWarm;
      // Re-run the active query so matches that only surfaced once the warm
      // completed appear without the user needing another keystroke.
      if (mounted && _query.trim().isNotEmpty) {
        await _runSearches(_query);
      }
    } finally {
      if (mounted) setState(() => _contentIndexing = false);
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    Debounces.debounce(
      _debounceTag,
      const Duration(milliseconds: 180),
      () => unawaited(_runSearches(value)),
    );
  }

  Future<void> _runSearches(String value) async {
    final seq = ++_searchSeq;
    final query = value.trim();

    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchingFiles = false;
        _fileMatches = const [];
        _fileResultsTruncated = false;
        _contentMatches = const [];
        _contentResultsTruncated = false;
      });
      return;
    }

    // Transcript content: synchronous over the warmed docs. The background
    // warm fills in seats progressively, so partial results appear early.
    final content = widget.indexes
        .contentIndexFor(widget.workspace.workspaceId)
        .search(query, sessions: widget.sessions);
    final contentTruncated = content.length > _maxContentResults;
    final cappedContent = contentTruncated
        ? content.sublist(0, _maxContentResults)
        : content;
    if (mounted) {
      setState(() {
        _contentMatches = cappedContent;
        _contentResultsTruncated = contentTruncated;
      });
    }

    // Files: cached index, synchronous after the first build.
    final root = widget.workspace.firstFolderPath;
    if (root.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchingFiles = false;
        _fileMatches = const [];
        _fileResultsTruncated = false;
      });
      return;
    }
    final fileIndex = widget.indexes.fileIndexFor(root);
    if (!fileIndex.isReady && mounted) setState(() => _searchingFiles = true);
    await fileIndex.ensureFresh();
    if (!mounted || seq != _searchSeq) return;
    final fileQuery = fileIndex.query(query, limit: _maxFileResults + 1);
    final truncated = fileQuery.length > _maxFileResults;
    final files = truncated ? fileQuery.sublist(0, _maxFileResults) : fileQuery;
    setState(() {
      _searchingFiles = false;
      _fileMatches = files;
      _fileResultsTruncated = truncated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasQuery = _query.trim().isNotEmpty;

    final sessions = hasQuery
        ? filterSessionsByQuery(
            widget.sessions,
            query: _query,
            emptyTitleFallback: widget.emptyTitleFallback,
          )
        : _recentSessions(widget.sessions);

    final hasResults =
        sessions.isNotEmpty ||
        _contentMatches.isNotEmpty ||
        _fileMatches.isNotEmpty ||
        _searchingFiles ||
        _contentIndexing;

    return TpDialogPageShell(
      title: l10n.workspaceSearchTitle,
      mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
      fillBody: true,
      child: Padding(
        padding: _pageHostPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SearchField(
              controller: _controller,
              hint: l10n.workspaceSearchHint,
              onChanged: _onQueryChanged,
              onClear: () {
                _controller.clear();
                _onQueryChanged('');
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: !hasQuery
                  ? _RecentSessions(
                      sessions: sessions,
                      header: l10n.workspaceSearchRecentSessions,
                      onOpenSession: widget.onOpenSession,
                    )
                  : (!hasResults)
                  ? _EmptyResults(label: l10n.workspaceSearchNoResults)
                  : _Results(
                      query: _query,
                      sessions: sessions,
                      contentMatches: _contentMatches,
                      contentIndexing: _contentIndexing,
                      contentTruncated: _contentResultsTruncated,
                      fileMatches: _fileMatches,
                      searchingFiles: _searchingFiles,
                      fileResultsTruncated: _fileResultsTruncated,
                      sessionsHeader: l10n.homeWorkspaceConversationsSection,
                      contentHeader: l10n.workspaceSearchSessionContentSection,
                      filesHeader: l10n.workspaceSearchFilesSection,
                      indexingLabel: l10n.workspaceSearchIndexing,
                      searchingLabel: l10n.workspaceSearchSearching,
                      contentTruncatedLabel:
                          l10n.workspaceSearchContentTruncated,
                      truncatedLabel: l10n.workspaceSearchFilesTruncated,
                      emptyTitleFallback: widget.emptyTitleFallback,
                      onOpenSession: widget.onOpenSession,
                      onOpenFile: widget.onOpenFile,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sessions sorted most-recent-first (updatedAt, else createdAt), capped.
List<AppSession> _recentSessions(List<AppSession> all) {
  final sorted = [...all]
    ..sort((a, b) {
      final at = a.updatedAt != 0 ? a.updatedAt : a.createdAt;
      final bt = b.updatedAt != 0 ? b.updatedAt : b.createdAt;
      return bt.compareTo(at);
    });
  return sorted.take(_maxRecentSessions).toList();
}

EdgeInsets _pageHostPadding(BuildContext context) {
  final narrow =
      MediaQuery.sizeOf(context).width <
      WorkspacePanePolicy.narrowBreakpointWidth;
  return narrow ? const EdgeInsets.fromLTRB(16, 0, 16, 16) : EdgeInsets.zero;
}

/// Compact recent-sessions list shown before any query is typed.
class _RecentSessions extends StatelessWidget {
  const _RecentSessions({
    required this.sessions,
    required this.header,
    required this.onOpenSession,
  });

  final List<AppSession> sessions;
  final String header;
  final FutureOr<void> Function(AppSession session) onOpenSession;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(label: header),
          for (final session in sessions)
            SidebarSessionTile(
              session: session,
              tapThrottleKeyPrefix: 'workspace_search_recent',
              onTap: () => onOpenSession(session),
            ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.sessions,
    required this.contentMatches,
    required this.contentIndexing,
    required this.contentTruncated,
    required this.fileMatches,
    required this.searchingFiles,
    required this.fileResultsTruncated,
    required this.sessionsHeader,
    required this.contentHeader,
    required this.filesHeader,
    required this.indexingLabel,
    required this.searchingLabel,
    required this.contentTruncatedLabel,
    required this.truncatedLabel,
    required this.emptyTitleFallback,
    required this.onOpenSession,
    required this.onOpenFile,
  });

  final String query;
  final List<AppSession> sessions;
  final List<WorkspaceSessionContentMatch> contentMatches;
  final bool contentIndexing;
  final bool contentTruncated;
  final List<WorkspaceFileMatch> fileMatches;
  final bool searchingFiles;
  final bool fileResultsTruncated;
  final String sessionsHeader;
  final String contentHeader;
  final String filesHeader;
  final String indexingLabel;
  final String searchingLabel;
  final String contentTruncatedLabel;
  final String truncatedLabel;
  final String emptyTitleFallback;
  final FutureOr<void> Function(AppSession session) onOpenSession;
  final ValueChanged<String> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final showContent =
        contentMatches.isNotEmpty || contentIndexing || contentTruncated;
    return CustomScrollView(
      slivers: [
        if (sessions.isNotEmpty) ...[
          SliverToBoxAdapter(child: _SectionHeader(label: sessionsHeader)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => SidebarSessionTile(
                session: sessions[index],
                tapThrottleKeyPrefix: 'workspace_search_session',
                onTap: () => onOpenSession(sessions[index]),
              ),
              childCount: sessions.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        if (showContent) ...[
          SliverToBoxAdapter(child: _SectionHeader(label: contentHeader)),
          if (contentIndexing && contentMatches.isEmpty)
            SliverToBoxAdapter(child: _StatusRow(label: indexingLabel))
          else ...[
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ContentResultTile(
                  match: contentMatches[index],
                  query: query,
                  emptyTitleFallback: emptyTitleFallback,
                  onTap: () => onOpenSession(contentMatches[index].session),
                ),
                childCount: contentMatches.length,
              ),
            ),
            if (contentTruncated)
              SliverToBoxAdapter(
                child: _StatusRow(label: contentTruncatedLabel),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        SliverToBoxAdapter(child: _SectionHeader(label: filesHeader)),
        if (searchingFiles)
          SliverToBoxAdapter(child: _StatusRow(label: searchingLabel))
        else ...[
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _FileResultTile(
                match: fileMatches[index],
                onTap: () => onOpenFile(fileMatches[index].path),
              ),
              childCount: fileMatches.length,
            ),
          ),
          if (fileResultsTruncated)
            SliverToBoxAdapter(child: _StatusRow(label: truncatedLabel)),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Text(
        label,
        style: TpTextStyles.of(context).smSemiboldColored(cs.onSurfaceVariant),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Text(
        label,
        style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant),
      ),
    );
  }
}

/// A transcript content hit: the session title plus a one-line snippet with the
/// matched query emphasized.
class _ContentResultTile extends StatelessWidget {
  const _ContentResultTile({
    required this.match,
    required this.query,
    required this.emptyTitleFallback,
    required this.onTap,
  });

  final WorkspaceSessionContentMatch match;
  final String query;
  final String emptyTitleFallback;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final title = match.session.resolveDisplayTitle(emptyTitleFallback);
    final member = match.memberLabel.trim();
    final subtitle = member.isEmpty
        ? match.snippet
        : '$member · ${match.snippet}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: TpHover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: cs.onSurface.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: context.tpIconSizes.md,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.mdMediumColored(cs.onSurface),
                  ),
                  const SizedBox(height: 2),
                  _HighlightedSnippet(text: subtitle, query: query),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-to-two line snippet with the first case-insensitive [query] occurrence
/// in bold. Falls back to plain text when [query] is empty.
class _HighlightedSnippet extends StatelessWidget {
  const _HighlightedSnippet({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TpTextStyles.of(context).smColored(cs.onSurfaceVariant);
    final q = query.trim().toLowerCase();
    final lower = text.toLowerCase();
    final idx = q.isEmpty ? -1 : lower.indexOf(q);
    if (idx < 0) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + q.length),
            style: style.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          TextSpan(text: text.substring(idx + q.length)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _FileResultTile extends StatelessWidget {
  const _FileResultTile({required this.match, required this.onTap});

  final WorkspaceFileMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: TpHover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: cs.onSurface.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: context.tpIconSizes.md,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.mdMediumColored(cs.onSurface),
                  ),
                  Text(
                    match.relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.smColored(cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      autofocus: true,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: cs.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: context.tpIconSizes.md,
          color: cs.onSurfaceVariant,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.never,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.primary),
        ),
        suffixIcon: controller.text.isNotEmpty
            ? TpIconButton(
                icon: Icons.clear,
                compact: true,
                size: TpIconButton.kCompactSize,
                onTap: onClear,
              )
            : null,
      ),
      onChanged: onChanged,
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: context.tpIconSizes.lg,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: styles.smColored(cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
