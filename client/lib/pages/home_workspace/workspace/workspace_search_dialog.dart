import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../services/file_tree/workspace_file_search.dart';
import '../../../services/io/filesystem.dart';
import '../../../services/search/workspace_search_indexes.dart';
import '../../../services/session/workspace_session_content_index.dart';
import '../../../services/workbench/workbench_editor_opener.dart';
import '../../../services/workspace/workspace_pane_policy.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/session/workspace_sessions.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_search_content_section.dart';
import 'workspace_search_widgets.dart';
import 'workspace_session_actions.dart';

/// Result-count caps shown before the section's "查看更多结果" link appears.
const _maxConversationResults = 20;
const _maxFileResults = 50;
const _maxRecentSessions = 8;

/// Files are queried once with this effectively-unbounded limit so the
/// "查看更多结果" link can reveal every match without a second pass. The fuzzy
/// index scores every entry regardless of the limit, so this is free.
const _maxFileResultsExpanded = 100000;

/// Opens the workspace search dialog, which searches conversation sessions
/// (by title and by transcript content), workspace files by name, and — on the
/// `content` filter — file contents via the content-search engine. Reads the
/// current session list, CLI fallback title, and shared search indexes from
/// [context] up front; selecting a result pops the dialog and performs the
/// action against the still-mounted [context].
///
/// [fs] backs the content filter and is resolved by the caller from the
/// entry point's workspace tools scope — never derived here, so a shortcut
/// host above the scope cannot silently fall back to a local filesystem.
///
/// No-ops if a search dialog is already open (e.g. repeated shortcut presses).
Future<void> showWorkspaceSearchDialog(
  BuildContext context, {
  required Workspace workspace,
  required Filesystem fs,
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
      maxWidth: 680,
      maxHeight: 640,
      builder: (dialogContext) => WorkspaceSearchDialog(
        workspace: workspace,
        sessions: sessions,
        indexes: indexes,
        fs: fs,
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

/// Centered modal that filters sessions (title + transcript content), workspace
/// files for name matches, and — on the `content` filter — file contents,
/// styled after the search-panel mockup: a headerless rounded search field,
/// single-select filter chips (全部 / 任务 / 文件 / 内容), a merged 对话 group (title
/// hits + content hits deduped by session), a 文件 group, and per-section
/// "查看更多结果" links that expand the section to all matches. Pure UI: result
/// actions are delegated to callbacks, and searches hit the shared
/// [WorkspaceSearchIndexes] so files and transcripts are indexed once per
/// workspace instead of re-walking on every keystroke. The `content` filter is
/// an exclusive mode rendered by [WorkspaceSearchContentSection] and never
/// merges into the `all` view.
class WorkspaceSearchDialog extends StatefulWidget {
  const WorkspaceSearchDialog({
    required this.workspace,
    required this.sessions,
    required this.indexes,
    required this.fs,
    required this.emptyTitleFallback,
    required this.onOpenSession,
    required this.onOpenFile,
    super.key,
  });

  final Workspace workspace;
  final List<AppSession> sessions;
  final WorkspaceSearchIndexes indexes;
  final Filesystem fs;
  final String emptyTitleFallback;
  final FutureOr<void> Function(AppSession session) onOpenSession;
  final ValueChanged<String> onOpenFile;

  @override
  State<WorkspaceSearchDialog> createState() => _WorkspaceSearchDialogState();
}

enum _SearchFilter { all, conversations, files, content }

/// One merged conversation result: a session plus, when it also matched by
/// transcript content, the snippet and member label to show under the title.
class _ConversationHit {
  const _ConversationHit({
    required this.session,
    this.snippet,
    this.source,
  });

  final AppSession session;
  final String? snippet;

  /// Right-meta source label: the roster member type for team seats, the team
  /// name otherwise. Null when the session is unteamed and unmixed.
  final String? source;

  int get activityTimestampMs =>
      session.updatedAt != 0 ? session.updatedAt : session.createdAt;
}

class _WorkspaceSearchDialogState extends State<WorkspaceSearchDialog> {
  final _controller = TextEditingController();
  late final String _debounceTag =
      'workspace_search_${widget.workspace.workspaceId}_${identityHashCode(this)}';

  var _query = '';
  var _searchingFiles = false;
  var _activeFilter = _SearchFilter.all;
  var _conversationsExpanded = false;
  var _filesExpanded = false;

  /// All matching files (queried with an effectively-unbounded limit) and all
  /// content matches; display slices them by the per-section caps unless the
  /// user expanded the section.
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
    setState(() {
      _query = value;
      // A new query restarts the section expansion state.
      _conversationsExpanded = false;
      _filesExpanded = false;
    });
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
        _contentMatches = const [];
      });
      return;
    }

    // Transcript content: synchronous over the warmed docs. The background
    // warm fills in seats progressively, so partial results appear early.
    final content = widget.indexes
        .contentIndexFor(widget.workspace.workspaceId)
        .search(query, sessions: widget.sessions);
    if (mounted) setState(() => _contentMatches = content);

    // Files: cached index, synchronous after the first build.
    final root = widget.workspace.firstFolderPath;
    if (root.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchingFiles = false;
        _fileMatches = const [];
      });
      return;
    }
    final fileIndex = widget.indexes.fileIndexFor(root);
    if (!fileIndex.isReady && mounted) setState(() => _searchingFiles = true);
    await fileIndex.ensureFresh();
    if (!mounted || seq != _searchSeq) return;
    final fileQuery = fileIndex.query(query, limit: _maxFileResultsExpanded);
    setState(() {
      _searchingFiles = false;
      _fileMatches = fileQuery;
    });
  }

  /// Merged conversation hits for the active query: title-matched sessions
  /// first (in session order), then content-only matches, deduped by session id.
  /// A title hit that also has a content hit carries that snippet + source.
  List<_ConversationHit> _conversationHits() {
    final titleHits = filterSessionsByQuery(
      widget.sessions,
      query: _query,
      emptyTitleFallback: widget.emptyTitleFallback,
    );
    final contentById = <String, WorkspaceSessionContentMatch>{};
    for (final match in _contentMatches) {
      contentById[match.session.sessionId] = match;
    }
    final out = <_ConversationHit>[];
    final seen = <String>{};
    for (final session in titleHits) {
      out.add(_hitFor(session, contentById[session.sessionId]));
      seen.add(session.sessionId);
    }
    for (final match in _contentMatches) {
      if (seen.contains(match.session.sessionId)) continue;
      out.add(_hitFor(match.session, match));
      seen.add(match.session.sessionId);
    }
    return out;
  }

  _ConversationHit _hitFor(
    AppSession session,
    WorkspaceSessionContentMatch? content,
  ) {
    final member = content?.memberLabel.trim() ?? '';
    final source = member.isNotEmpty
        ? member
        : (session.sessionTeam.trim().isNotEmpty
              ? session.sessionTeam.trim()
              : null);
    return _ConversationHit(
      session: session,
      snippet: content?.snippet,
      source: source,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isNarrow =
        MediaQuery.sizeOf(context).width <
        WorkspacePanePolicy.narrowBreakpointWidth;

    // The content filter owns its query input (WorkspaceSearchContentSection),
    // so the dialog's own field is hidden in that mode.
    final Widget field = _activeFilter == _SearchFilter.content
        ? const SizedBox.shrink()
        : WorkspaceSearchField(
            controller: _controller,
            hint: l10n.workspaceSearchHint,
            onChanged: _onQueryChanged,
            onClear: () {
              _controller.clear();
              _onQueryChanged('');
            },
          );
    final Widget chips = _FilterChips(
      active: _activeFilter,
      onChanged: (filter) => setState(() => _activeFilter = filter),
    );

    if (isNarrow) {
      // Fullscreen page: search + chips pinned, results fill and scroll.
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const SizedBox(height: 12),
          chips,
          const SizedBox(height: 10),
          Expanded(child: _buildResults(shrinkWrap: false)),
        ],
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogMobileNavBar(
            title: l10n.workspaceSearchTitle,
            onLeading: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: SafeArea(top: false, child: body),
          ),
        ],
      );
    }

    // Wide: the dialog height adapts to its content and only grows to the
    // showTpDialog maxHeight. The results area shrink-wraps (loose flex) so a
    // few matches yield a compact panel while a full list caps and scrolls.
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        const SizedBox(height: 12),
        chips,
        const SizedBox(height: 10),
        Flexible(fit: FlexFit.loose, child: _buildResults(shrinkWrap: true)),
      ],
    );
    return SafeArea(
      child: Padding(padding: const EdgeInsets.all(16), child: body),
    );
  }

  /// Results body: recent sessions before any query, grouped search results after.
  /// [shrinkWrap] sizes the list to its content (wide adaptive height); when
  /// false the list fills its box and scrolls (narrow fullscreen).
  Widget _buildResults({bool shrinkWrap = false}) {
    return _query.trim().isEmpty
        ? _buildRecentResults(shrinkWrap: shrinkWrap)
        : _buildSearchResults(shrinkWrap: shrinkWrap);
  }

  /// No query: recent conversations (expandable to all sessions), a files
  /// hint when the 文件 filter is active, or the content section (which owns
  /// its own query input) when the 内容 filter is active.
  Widget _buildRecentResults({required bool shrinkWrap}) {
    final l10n = context.l10n;
    if (_activeFilter == _SearchFilter.content) {
      return _buildContentSection();
    }
    if (_activeFilter == _SearchFilter.files) {
      return ListView(
        shrinkWrap: shrinkWrap,
        children: [
          WorkspaceSearchSectionHeader(label: l10n.workspaceSearchFilesSection),
          WorkspaceSearchStatusRow(label: l10n.workspaceSearchFilesEmptyHint),
        ],
      );
    }
    final all = _recentSessions(widget.sessions);
    final shown = _conversationsExpanded
        ? all
        : all.take(_maxRecentSessions).toList();
    return ListView(
      shrinkWrap: shrinkWrap,
      children: [
        WorkspaceSearchSectionHeader(
          label: l10n.workspaceSearchRecentSessions,
        ),
        for (final session in shown)
          SidebarSessionTile(
            session: session,
            tapThrottleKeyPrefix: 'workspace_search_recent',
            onTap: () => widget.onOpenSession(session),
          ),
        if (!_conversationsExpanded && all.length > _maxRecentSessions)
          WorkspaceSearchShowMore(
            label: l10n.workspaceSearchShowMore,
            onTap: () => setState(() => _conversationsExpanded = true),
          ),
      ],
    );
  }

  /// Query results: 对话 (merged title + content) and 文件 sections, filtered by
  /// the active chip and expandable past their initial caps. The `content`
  /// filter is exclusive — it renders only [WorkspaceSearchContentSection] and
  /// never merges into the `all` view. Sections with no content are skipped so
  /// a truly empty query falls through to the empty state.
  Widget _buildSearchResults({required bool shrinkWrap}) {
    final l10n = context.l10n;
    if (_activeFilter == _SearchFilter.content) {
      return _buildContentSection();
    }
    final children = <Widget>[];

    if (_activeFilter != _SearchFilter.files) {
      children.addAll(_buildConversationsSection(l10n));
    }
    if (_activeFilter != _SearchFilter.conversations) {
      children.addAll(_buildFilesSection(l10n));
    }

    if (children.isEmpty) {
      return _EmptyResults(label: l10n.workspaceSearchNoResults);
    }
    return ListView(shrinkWrap: shrinkWrap, children: children);
  }

  /// 对话 section: title-matched + content-matched sessions, merged and deduped.
  List<Widget> _buildConversationsSection(AppLocalizations l10n) {
    final out = <Widget>[];
    final hits = _conversationHits();
    if (hits.isEmpty && _contentIndexing) {
      out.add(
        WorkspaceSearchSectionHeader(
          label: l10n.homeWorkspaceConversationsSection,
        ),
      );
      out.add(WorkspaceSearchStatusRow(label: l10n.workspaceSearchIndexing));
      return out;
    }
    if (hits.isEmpty) return out;
    out.add(
      WorkspaceSearchSectionHeader(label: l10n.homeWorkspaceConversationsSection),
    );
    final shown = _conversationsExpanded
        ? hits
        : hits.take(_maxConversationResults).toList();
    for (final hit in shown) {
      out.add(
        WorkspaceSearchConversationRow(
          title: hit.session.resolveDisplayTitle(widget.emptyTitleFallback),
          query: _query,
          snippet: hit.snippet,
          source: hit.source,
          activityTimestampMs: hit.activityTimestampMs,
          onTap: () => widget.onOpenSession(hit.session),
        ),
      );
    }
    if (!_conversationsExpanded && hits.length > _maxConversationResults) {
      out.add(
        WorkspaceSearchShowMore(
          label: l10n.workspaceSearchShowMore,
          onTap: () => setState(() => _conversationsExpanded = true),
        ),
      );
    }
    return out;
  }

  /// 文件 section: file-name matches, expandable past [_maxFileResults].
  List<Widget> _buildFilesSection(AppLocalizations l10n) {
    final out = <Widget>[];
    if (_searchingFiles) {
      out.add(WorkspaceSearchSectionHeader(label: l10n.workspaceSearchFilesSection));
      out.add(WorkspaceSearchStatusRow(label: l10n.workspaceSearchSearching));
      return out;
    }
    if (_fileMatches.isEmpty) return out;
    out.add(WorkspaceSearchSectionHeader(label: l10n.workspaceSearchFilesSection));
    final shown = _filesExpanded
        ? _fileMatches
        : _fileMatches.take(_maxFileResults).toList();
    for (final match in shown) {
      out.add(
        WorkspaceSearchFileRow(
          name: match.name,
          query: _query,
          relativePath: match.relativePath,
          onTap: () => widget.onOpenFile(match.path),
        ),
      );
    }
    if (!_filesExpanded && _fileMatches.length > _maxFileResults) {
      out.add(
        WorkspaceSearchShowMore(
          label: l10n.workspaceSearchShowMore,
          onTap: () => setState(() => _filesExpanded = true),
        ),
      );
    }
    return out;
  }

  /// 内容 section: the exclusive content-search mode with its own query input,
  /// regex/case chips, and streaming file:line results. Searching roots the
  /// first workspace folder on the dialog's injected [Filesystem].
  Widget _buildContentSection() {
    return WorkspaceSearchContentSection(
      root: widget.workspace.firstFolderPath,
      fs: widget.fs,
      onOpenFile: widget.onOpenFile,
    );
  }
}

/// Sessions sorted most-recent-first (updatedAt, else createdAt). Uncapped so
/// the recent section can expand past [_maxRecentSessions].
List<AppSession> _recentSessions(List<AppSession> all) {
  final sorted = [...all]
    ..sort((a, b) {
      final at = a.updatedAt != 0 ? a.updatedAt : a.createdAt;
      final bt = b.updatedAt != 0 ? b.updatedAt : b.createdAt;
      return bt.compareTo(at);
    });
  return sorted;
}

/// Single-select filter chips row: 全部 / 任务 / 文件 / 内容.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.active, required this.onChanged});

  final _SearchFilter active;
  final ValueChanged<_SearchFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        WorkspaceSearchFilterChip(
          label: l10n.workspaceSearchFilterAll,
          icon: Icons.format_list_bulleted_rounded,
          active: active == _SearchFilter.all,
          onTap: () => onChanged(_SearchFilter.all),
        ),
        const SizedBox(width: 6),
        WorkspaceSearchFilterChip(
          label: l10n.workspaceSearchFilterConversations,
          icon: Icons.chat_bubble_outline_rounded,
          active: active == _SearchFilter.conversations,
          onTap: () => onChanged(_SearchFilter.conversations),
        ),
        const SizedBox(width: 6),
        WorkspaceSearchFilterChip(
          label: l10n.workspaceSearchFilterFiles,
          icon: Icons.description_outlined,
          active: active == _SearchFilter.files,
          onTap: () => onChanged(_SearchFilter.files),
        ),
        const SizedBox(width: 6),
        WorkspaceSearchFilterChip(
          label: l10n.workspaceSearchContent,
          icon: Icons.find_in_page_outlined,
          active: active == _SearchFilter.content,
          onTap: () => onChanged(_SearchFilter.content),
        ),
      ],
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
              style: styles.mdColored(cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
