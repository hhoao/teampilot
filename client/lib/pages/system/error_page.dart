import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../../utils/logger_utils.dart';
import 'fatal_app_theme.dart';
import 'log_config_workspace.dart';
import 'log_helpers.dart';

/// Fallback UI when startup fails before the main app shell loads.
Future<void> showInitErrorApp({
  required Object error,
  required StackTrace stackTrace,
}) async {
  final theme = await resolveFatalAppTheme();
  runApp(
    _InitErrorApp(
      error: error,
      stackTrace: stackTrace,
      theme: theme,
    ),
  );
}

class _InitErrorApp extends StatefulWidget {
  const _InitErrorApp({
    required this.error,
    required this.stackTrace,
    required this.theme,
  });

  final Object error;
  final StackTrace stackTrace;
  final ThemeData theme;

  @override
  State<_InitErrorApp> createState() => _InitErrorAppState();
}

class _InitErrorAppState extends State<_InitErrorApp> {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  String? _version;
  String? _buildNumber;
  bool _copiedReport = false;
  bool _copiedStack = false;

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    } on Object {
      // Ignore package info errors on the error screen.
    }
  }

  String _formatStackTrace(BuildContext context, StackTrace stackTrace) {
    final text = stackTrace.toString().trim();
    if (text.isNotEmpty) return text;

    final l10n = context.l10n;
    final buffer = StringBuffer('${l10n.initErrorStackEmpty}\n\n');
    buffer.writeln('${widget.error}');
    buffer.writeln(widget.error.runtimeType);
    if (widget.error is PlatformException) {
      final pe = widget.error as PlatformException;
      buffer.writeln('code: ${pe.code}');
      buffer.writeln('message: ${pe.message}');
      buffer.writeln('details: ${pe.details}');
    }
    return buffer.toString();
  }

  String _buildReportText(BuildContext context) {
    final l10n = context.l10n;
    return '''
TeamPilot
${l10n.initErrorVersion(_version ?? '?', _buildNumber ?? '?')}
${widget.error}
${widget.error.runtimeType}
${_formatStackTrace(context, widget.stackTrace)}

${l10n.initErrorPendingLogs}:
${AppLogger.instance.getFormattedPendingLogs()}
''';
  }

  void _copyAll(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _buildReportText(context)));
    setState(() => _copiedReport = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedReport = false);
    });
  }

  void _copyStack(BuildContext context) {
    Clipboard.setData(
      ClipboardData(text: _formatStackTrace(context, widget.stackTrace)),
    );
    setState(() => _copiedStack = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedStack = false);
    });
  }

  void _openLogViewer() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: widget.theme,
          child: const LogViewerPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FatalAppShell(
      theme: widget.theme,
      navigatorKey: navigatorKey,
      home: Builder(builder: _buildHome),
    );
  }

  Widget _buildHome(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.workspacePage,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkspaceHubTitleBar(
              title: l10n.initErrorTitle,
              subtitle: _version != null
                  ? l10n.initErrorVersion(_version!, _buildNumber!)
                  : l10n.logViewerSubtitle,
              compact: true,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SettingsSurfaceCard(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ErrorBlock(
                          title: l10n.initErrorDetails,
                          child: SelectableText(
                            widget.error.toString(),
                            style: logMonospaceStyle(
                              context,
                              color: cs.error,
                            ),
                          ),
                        ),
                        _ErrorBlock(
                          title: l10n.initErrorStackTrace,
                          trailing: TextButton.icon(
                            onPressed: () => _copyStack(context),
                            icon: Icon(
                              _copiedStack ? Icons.check : Icons.copy,
                              size: AppIconSizes.md,
                            ),
                            label: Text(
                              _copiedStack
                                  ? l10n.initErrorCopied
                                  : l10n.initErrorCopy,
                            ),
                          ),
                          child: SelectableText(
                            _formatStackTrace(context, widget.stackTrace),
                            style: logMonospaceStyle(context),
                          ),
                        ),
                        _ErrorBlock(
                          title: l10n.initErrorPendingLogs,
                          showDividerBelow: false,
                          child: SelectableText(
                            AppLogger.instance.getFormattedPendingLogs(),
                            style: logMonospaceStyle(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openLogViewer,
                      icon: const Icon(Icons.article_outlined),
                      label: Text(l10n.initErrorViewLogs),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _copyAll(context),
                      icon: Icon(_copiedReport ? Icons.check : Icons.copy),
                      label: Text(
                        _copiedReport
                            ? l10n.initErrorCopied
                            : l10n.initErrorCopyReport,
                      ),
                    ),
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

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.title,
    required this.child,
    this.trailing,
    this.showDividerBelow = true,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.of(context).bodyStrong.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: workspaceCodeDecoration(cs),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: child,
                ),
              ),
            ],
          ),
        ),
        if (showDividerBelow)
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
    );
  }
}
