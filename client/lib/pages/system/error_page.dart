import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../utils/logger_utils.dart';
import 'log_viewer_page.dart';

/// Fallback UI when startup fails before the main app shell loads.
void showInitErrorApp({
  required Object error,
  required StackTrace stackTrace,
}) {
  runApp(_InitErrorApp(error: error, stackTrace: stackTrace));
}

class _InitErrorApp extends StatefulWidget {
  const _InitErrorApp({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  State<_InitErrorApp> createState() => _InitErrorAppState();
}

class _InitErrorAppState extends State<_InitErrorApp> {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  String? _version;
  String? _buildNumber;
  bool _copied = false;

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

  String _formatStackTrace(StackTrace stackTrace) {
    final text = stackTrace.toString().trim();
    if (text.isNotEmpty) return text;

    final buffer = StringBuffer('（堆栈为空）\n\n');
    buffer.writeln('错误：${widget.error}');
    buffer.writeln('类型：${widget.error.runtimeType}');
    if (widget.error is PlatformException) {
      final pe = widget.error as PlatformException;
      buffer.writeln('code: ${pe.code}');
      buffer.writeln('message: ${pe.message}');
      buffer.writeln('details: ${pe.details}');
    }
    return buffer.toString();
  }

  String _buildReportText() {
    return '''
TeamPilot
版本: ${_version ?? '?'} (${_buildNumber ?? '?'})
错误: ${widget.error}
类型: ${widget.error.runtimeType}
堆栈:
${_formatStackTrace(widget.stackTrace)}

待写入日志:
${AppLogger.instance.getFormattedPendingLogs()}
''';
  }

  void _copyAll() {
    Clipboard.setData(ClipboardData(text: _buildReportText()));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _copyStack() {
    Clipboard.setData(ClipboardData(text: _formatStackTrace(widget.stackTrace)));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _openLogViewer() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const LogViewerPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeamPilot — 启动失败',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: cs.error, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '应用启动失败',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (_version != null)
                            Text(
                              '版本 $_version ($_buildNumber)',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionCard(
                          title: '错误信息',
                          child: SelectableText(
                            widget.error.toString(),
                            style: TextStyle(color: cs.error),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: '堆栈跟踪',
                          trailing: TextButton.icon(
                            onPressed: _copyStack,
                            icon: Icon(
                              _copied ? Icons.check : Icons.copy,
                              size: 18,
                            ),
                            label: Text(_copied ? '已复制' : '复制'),
                          ),
                          child: SelectableText(
                            _formatStackTrace(widget.stackTrace),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SectionCard(
                          title: '待写入日志',
                          child: SelectableText(
                            AppLogger.instance.getFormattedPendingLogs(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openLogViewer,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('查看日志'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _copyAll,
                        icon: Icon(_copied ? Icons.check : Icons.copy),
                        label: Text(_copied ? '已复制' : '复制报告'),
                      ),
                    ),
                  ],
                ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
