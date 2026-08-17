import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/app/external_link_opener.dart';
import '../../services/io/filesystem.dart';
import '../../services/preview/html_preview_server.dart';
import '../../services/preview/html_preview_session.dart';
import '../../services/storage/app_storage.dart';

/// Preview surface for one html file.
///
/// Opens the rendered preview in the system default application (browser)
/// through [openExternalUri], which on Linux routes via the XDG Desktop
/// Portal so the browser window jumps to the foreground. The pane itself is
/// a placeholder with quick actions.
class HtmlPreviewPane extends StatefulWidget {
  const HtmlPreviewPane({
    required this.workspaceId,
    required this.path,
    this.fs,
    this.sessionFactory,
    this.externalOpener,
    this.openedPaths,
    super.key,
  });

  final String workspaceId;
  final String path;
  final Filesystem? fs;
  final HtmlPreviewSession Function(String htmlDirectory, String entryFileName)?
  sessionFactory;

  /// Opens the preview uri in the system default app. Injectable for tests.
  final Future<void> Function(Uri uri)? externalOpener;

  /// Tracks paths whose browser was auto-opened; injectable for tests.
  final Set<String>? openedPaths;

  @override
  State<HtmlPreviewPane> createState() => _HtmlPreviewPaneState();
}

class _HtmlPreviewPaneState extends State<HtmlPreviewPane> {
  /// Paths whose browser was auto-opened in this process. Widget-tree
  /// rebuilds (floating panel minimize/restore, mode switches) recreate this
  /// State and would otherwise re-open the browser on every mount.
  static final Set<String> _defaultOpened = <String>{};

  HtmlPreviewSession? _session;
  bool _failed = false;
  bool _starting = false;
  bool _started = false;
  late final Set<String> _opened = widget.openedPaths ?? _defaultOpened;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Dependencies are available here, so context.read<EditorCubit>() is safe.
    if (!_started) {
      _started = true;
      _start();
    }
  }

  /// Work-plane filesystem that opened [widget.path] in [widget.workspaceId],
  /// so SSH/WSL workspaces preview through their remote fs instead of the home
  /// control-plane fs. Null only if the editor cubit itself has no default fs.
  Filesystem? _defaultFs(BuildContext context) =>
      context.read<EditorCubit>().fsFor(widget.workspaceId, widget.path);

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      final old = _session;
      if (old != null) {
        _session = null;
        unawaited(old.dispose());
      }
      final fs = widget.fs ?? _defaultFs(context) ?? AppStorage.fs;
      final dir = fs.pathContext.dirname(widget.path);
      final entry = p.basename(widget.path);
      final factory =
          widget.sessionFactory ??
          (dir, entry) => HtmlPreviewSession(
            htmlDirectory: dir,
            entryFileName: entry,
            server: HtmlPreviewServer(fs: fs),
          );
      final session = factory(dir, entry);
      _session = session;
      try {
        final mount = await session.start();
        if (!mounted) return;
        setState(() => _failed = mount == null);
        if (mount != null && _opened.add(widget.path)) {
          // Auto-open the browser only once per file per process: rebuilds
          // (floating panel minimize/restore, mode switches) remount this
          // State and must not re-open the browser.
          await _openExternal(mount.entryUri);
        }
      } on Object {
        if (!mounted) return;
        setState(() => _failed = true);
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _openExternal([Uri? uri]) async {
    final target = uri ?? _session?.mount?.entryUri;
    if (target == null) return;
    final opener = widget.externalOpener ?? openExternalUri;
    try {
      await opener(target);
    } on Object {
      // The opener never throws by contract; swallow defensively so the
      // fire-and-forget call sites stay quiet.
    }
  }

  @override
  void dispose() {
    unawaited(_session?.dispose());
    _session = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HtmlPreviewToolbar(
            path: widget.path,
            onOpenExternal: () => unawaited(_openExternal()),
          ),
          const Divider(height: 1),
          Expanded(
            child: _failed
                ? _HtmlPreviewError(
                    onOpenBrowser: () => unawaited(_openExternal()),
                    onRetry: () => unawaited(_start()),
                  )
                : _HtmlPreviewPlaceholder(
                    onOpenExternal: () => unawaited(_openExternal()),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HtmlPreviewToolbar extends StatelessWidget {
  const _HtmlPreviewToolbar({
    required this.path,
    required this.onOpenExternal,
  });

  final String path;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final iconColor = Theme.of(context).colorScheme.tpIconMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              p.basename(path),
              style: TpTextStyles.of(context).mdSemibold,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TpIconButton(
            tooltip: l10n.htmlPreviewOpenBrowser,
            icon: Icons.public,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: iconColor,
            onTap: onOpenExternal,
          ),
        ],
      ),
    );
  }
}

class _HtmlPreviewPlaceholder extends StatelessWidget {
  const _HtmlPreviewPlaceholder({required this.onOpenExternal});

  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: 36, color: cs.tpIconMuted),
            const SizedBox(height: 12),
            Text(
              l10n.htmlPreviewOpenedInBrowser,
              style: TpTextStyles.of(context)
                  .sm
                  .copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TpButton(
              onPressed: onOpenExternal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.public, size: 16),
                  const SizedBox(width: 6),
                  Text(l10n.htmlPreviewOpenBrowser),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HtmlPreviewError extends StatelessWidget {
  const _HtmlPreviewError({
    required this.onOpenBrowser,
    required this.onRetry,
  });

  final VoidCallback onOpenBrowser;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: cs.error),
            const SizedBox(height: 12),
            Text(
              l10n.htmlPreviewErrorTitle,
              style: TpTextStyles.of(context).mdSemibold,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.htmlPreviewErrorBody,
              style: TpTextStyles.of(context)
                  .sm
                  .copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TpButton(
                  onPressed: onOpenBrowser,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public, size: 16),
                      const SizedBox(width: 6),
                      Text(l10n.htmlPreviewOpenBrowser),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TpButton(
                  onPressed: onRetry,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 16),
                      const SizedBox(width: 6),
                      Text(l10n.retry),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
