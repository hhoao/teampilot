import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/editor_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../models/app_session.dart';
import '../../../services/file_tree/workspace_file_search.dart';
import '../../../services/storage/app_storage.dart';
import '../../../theme/app_icon_sizes.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/workspace_sessions.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_session_actions.dart';

/// Opens the workspace search dialog, which searches both conversation sessions
/// and workspace files by name. Reads the current session list and CLI fallback
/// title from [context] up front; selecting a result pops the dialog and
/// performs the action against the still-mounted [context].
Future<void> showWorkspaceSearchDialog(
  BuildContext context, {
  required Workspace workspace,
  required bool isPersonal,
  String sessionTeamFilter = '',
  bool personalLaunchBlocked = false,
}) {
  final chatCubit = context.read<ChatCubit>();
  final editorCubit = context.read<EditorCubit>();
  final fallback = context.l10n.defaultNewChatSessionTitle;
  final sessions = sessionsForWorkspace(workspace, chatCubit.state.sessions)
      .where((s) => s.sessionTeam.trim() == sessionTeamFilter)
      .toList();

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => WorkspaceSearchDialog(
      workspace: workspace,
      sessions: sessions,
      emptyTitleFallback: fallback,
      onOpenSession: (session) {
        Navigator.of(dialogContext).pop();
        if (!context.mounted) return;
        if (personalLaunchBlocked) {
          showPersonalLaunchBlockedToast(context);
          return;
        }
        unawaited(
          openWorkspaceSessionTab(
            context,
            workspace,
            session,
            isPersonal: isPersonal,
          ),
        );
      },
      onOpenFile: (path) {
        Navigator.of(dialogContext).pop();
        unawaited(editorCubit.openFile(path));
      },
    ),
  );
}

/// Centered modal that filters sessions and walks the workspace tree for file
/// name matches. Pure UI: result actions are delegated to callbacks so the
/// dialog needs no cubit/navigator wiring of its own.
class WorkspaceSearchDialog extends StatefulWidget {
  const WorkspaceSearchDialog({
    required this.workspace,
    required this.sessions,
    required this.emptyTitleFallback,
    required this.onOpenSession,
    required this.onOpenFile,
    super.key,
  });

  final Workspace workspace;
  final List<AppSession> sessions;
  final String emptyTitleFallback;
  final ValueChanged<AppSession> onOpenSession;
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
  List<WorkspaceFileMatch> _fileMatches = const [];

  /// Bumped per file search; stale async results are discarded.
  var _fileSearchSeq = 0;

  @override
  void dispose() {
    Debounces.cancel(_debounceTag);
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    Debounces.debounce(
      _debounceTag,
      const Duration(milliseconds: 220),
      () => unawaited(_runFileSearch(value)),
    );
  }

  Future<void> _runFileSearch(String value) async {
    final seq = ++_fileSearchSeq;
    final query = value.trim();
    final root = widget.workspace.firstFolderPath;
    if (query.isEmpty || root.isEmpty) {
      if (!mounted) return;
      setState(() {
        _searchingFiles = false;
        _fileMatches = const [];
        _fileResultsTruncated = false;
      });
      return;
    }

    setState(() => _searchingFiles = true);
    final result = await searchWorkspaceFiles(
      fs: AppStorage.fs,
      root: root,
      query: query,
    );
    if (!mounted || seq != _fileSearchSeq) return;
    setState(() {
      _searchingFiles = false;
      _fileMatches = result.matches;
      _fileResultsTruncated = result.truncated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filteredSessions = filterSessionsByQuery(
      widget.sessions,
      query: _query,
      emptyTitleFallback: widget.emptyTitleFallback,
    );
    final hasQuery = _query.trim().isNotEmpty;
    final hasResults = filteredSessions.isNotEmpty || _fileMatches.isNotEmpty;

    return AppDialog(
      maxWidth: 560,
      maxHeight: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.workspaceSearchTitle),
          const SizedBox(height: 12),
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
          Flexible(
            child: !hasQuery
                ? const SizedBox.shrink()
                : (!hasResults && !_searchingFiles)
                ? _EmptyResults(label: l10n.workspaceSearchNoResults)
                : _Results(
                    sessions: filteredSessions,
                    fileMatches: _fileMatches,
                    searchingFiles: _searchingFiles,
                    fileResultsTruncated: _fileResultsTruncated,
                    sessionsHeader: l10n.homeWorkspaceConversationsSection,
                    filesHeader: l10n.workspaceSearchFilesSection,
                    searchingLabel: l10n.workspaceSearchSearching,
                    truncatedLabel: l10n.workspaceSearchFilesTruncated,
                    onOpenSession: widget.onOpenSession,
                    onOpenFile: widget.onOpenFile,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.sessions,
    required this.fileMatches,
    required this.searchingFiles,
    required this.fileResultsTruncated,
    required this.sessionsHeader,
    required this.filesHeader,
    required this.searchingLabel,
    required this.truncatedLabel,
    required this.onOpenSession,
    required this.onOpenFile,
  });

  final List<AppSession> sessions;
  final List<WorkspaceFileMatch> fileMatches;
  final bool searchingFiles;
  final bool fileResultsTruncated;
  final String sessionsHeader;
  final String filesHeader;
  final String searchingLabel;
  final String truncatedLabel;
  final ValueChanged<AppSession> onOpenSession;
  final ValueChanged<String> onOpenFile;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sessions.isNotEmpty) ...[
            _SectionHeader(label: sessionsHeader),
            for (final session in sessions)
              SidebarSessionTile(
                session: session,
                tapThrottleKeyPrefix: 'workspace_search_session',
                onTap: () => onOpenSession(session),
              ),
            const SizedBox(height: 8),
          ],
          _SectionHeader(label: filesHeader),
          if (searchingFiles)
            _StatusRow(label: searchingLabel)
          else ...[
            for (final match in fileMatches)
              _FileResultTile(
                match: match,
                onTap: () => onOpenFile(match.path),
              ),
            if (fileResultsTruncated) _StatusRow(label: truncatedLabel),
          ],
        ],
      ),
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
        style: AppTextStyles.of(context).bodySmall.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
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
        style: AppTextStyles.of(
          context,
        ).bodySmall.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _FileResultTile extends StatefulWidget {
  const _FileResultTile({required this.match, required this.onTap});

  final WorkspaceFileMatch match;
  final VoidCallback onTap;

  @override
  State<_FileResultTile> createState() => _FileResultTileState();
}

class _FileResultTileState extends State<_FileResultTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final background = _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: context.appIconSizes.md,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.match.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.body.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        widget.match.relativePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: styles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
          size: context.appIconSizes.md,
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
            ? AppIconButton(
                icon: Icons.clear,
                compact: true, size: AppIconButton.kCompactSize,
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
    final styles = AppTextStyles.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: context.appIconSizes.lg,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
