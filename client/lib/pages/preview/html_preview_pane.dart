import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../cubits/editor_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/io/filesystem.dart';
import '../../services/preview/html_preview_server.dart';
import '../../services/preview/html_preview_session.dart';
import '../../services/preview/zikzak_html_controller.dart';
import '../../services/storage/app_storage.dart';

/// Embedded rendered preview for one html file.
///
/// Hosts a platform webview (webview_flutter official API) loading the file
/// through [HtmlPreviewServer]. Reloads after the file is saved (dirty→clean).
class HtmlPreviewPane extends StatefulWidget {
  const HtmlPreviewPane({
    required this.workspaceId,
    required this.path,
    this.fs,
    this.sessionFactory,
    super.key,
  });

  final String workspaceId;
  final String path;
  final Filesystem? fs;
  final HtmlPreviewSession Function(String htmlDirectory, String entryFileName)?
  sessionFactory;

  @override
  State<HtmlPreviewPane> createState() => _HtmlPreviewPaneState();
}

class _HtmlPreviewPaneState extends State<HtmlPreviewPane> {
  HtmlPreviewSession? _session;
  bool _failed = false;
  bool _starting = false;
  bool _started = false;

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
            controllerFactory: (_) => createHtmlPreviewController(),
          );
      final session = factory(dir, entry);
      _session = session;
      try {
        final mount = await session.start();
        if (!mounted) return;
        setState(() => _failed = mount == null);
      } on Object {
        if (!mounted) return;
        setState(() => _failed = true);
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _reload() async {
    setState(() => _failed = false);
    try {
      await _session?.reload();
    } on Object {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_session?.dispose());
    _session = null;
    super.dispose();
  }

  bool _wasDirty(EditorState state) =>
      state.bucket(widget.workspaceId).isDirty(widget.path);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<EditorCubit, EditorState>(
      listenWhen: (prev, next) => _wasDirty(prev) && !_wasDirty(next),
      listener: (context, state) {
        if (!_failed) unawaited(_reload());
      },
      child: ColoredBox(
        color: cs.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HtmlPreviewToolbar(
              path: widget.path,
              onRefresh: () => unawaited(_reload()),
              onOpenWindow: () => unawaited(_openExternalWindow()),
              onOpenBrowser: () => unawaited(_openSystemBrowser()),
              failed: _failed,
            ),
            const Divider(height: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final session = _session;
    if (session == null || _failed) {
      return _HtmlPreviewError(
        onOpenBrowser: () => unawaited(_openSystemBrowser()),
        onRetry: () => unawaited(_start()),
      );
    }
    final controller = session.controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return controller.buildWidget(context);
  }

  Future<void> _openExternalWindow() async {
    final uri = _session?.mount?.entryUri;
    if (uri == null) return;
    try {
      final webview = await _createDesktopWindow();
      if (webview == null) {
        await _openSystemBrowser();
        return;
      }
      webview.launch(uri.toString());
    } on Object {
      await _openSystemBrowser();
    }
  }

  Future<void> _openSystemBrowser() async {
    final uri = _session?.mount?.entryUri;
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      // launchUrl can throw when no handler is installed; swallow so the
      // fire-and-forget call sites never surface unhandled async errors.
    }
  }
}

/// Desktop "Open in Window" uses desktop_webview_window when available;
/// non-desktop platforms fall back to the system browser (handled by caller).
Future<dynamic> _createDesktopWindow() async {
  if (kIsWeb) return null;
  if (!isDesktopPlatform()) return null;
  return _tryDesktopWebviewWindow();
}

Future<dynamic> _tryDesktopWebviewWindow() async {
  final webview = await WebviewWindow.create(
    configuration: CreateConfiguration(
      title: 'Preview',
      windowWidth: 960,
      windowHeight: 720,
    ),
  );
  return webview;
}

bool isDesktopPlatform() =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;

/// Platform-appropriate embedded controller for the preview pane.
///
/// Linux uses zikzak_inappwebview: its WebKitGTK implementation renders into
/// an offscreen view presented as a Flutter texture, which neither reparents
/// the main GTK window tree (webview_win_floating re-realizes the Flutter
/// view and restarts the engine) nor relies on the DMA-BUF paths that render
/// black on NVIDIA/Wayland. Other platforms keep webview_flutter.
HtmlWebViewController createHtmlPreviewController() {
  if (Platform.isLinux) return ZikzakHtmlController();
  return WebviewHtmlController();
}

class _HtmlPreviewToolbar extends StatelessWidget {
  const _HtmlPreviewToolbar({
    required this.path,
    required this.onRefresh,
    required this.onOpenWindow,
    required this.onOpenBrowser,
    required this.failed,
  });

  final String path;
  final VoidCallback onRefresh;
  final VoidCallback onOpenWindow;
  final VoidCallback onOpenBrowser;
  final bool failed;

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
            tooltip: l10n.htmlPreviewRefresh,
            icon: Icons.refresh,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: iconColor,
            onTap: onRefresh,
          ),
          const SizedBox(width: 4),
          TpIconButton(
            tooltip: l10n.htmlPreviewOpenWindow,
            icon: Icons.open_in_new,
            size: TpIconButton.kCompactSize,
            compact: true,
            color: iconColor,
            onTap: onOpenWindow,
          ),
          if (failed) ...[
            const SizedBox(width: 4),
            TpIconButton(
              tooltip: l10n.htmlPreviewOpenBrowser,
              icon: Icons.public,
              size: TpIconButton.kCompactSize,
              compact: true,
              color: iconColor,
              onTap: onOpenBrowser,
            ),
          ],
        ],
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
