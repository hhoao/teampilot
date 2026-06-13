import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/storage/app_storage.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/logger_utils.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'log_viewer_content.dart';
import 'log_viewer_filter.dart';
import 'log_viewer_toolbar.dart';

class LogViewerPanel extends StatefulWidget {
  const LogViewerPanel({super.key});

  @override
  State<LogViewerPanel> createState() => LogViewerPanelState();
}

class LogViewerPanelState extends State<LogViewerPanel> {
  static const _pageSize = 500;

  List<String> _logFiles = [];
  List<String> _rawLines = [];
  List<String> _displayedLines = [];
  String? _selectedFile;

  bool _loading = true;
  bool _loadingMore = false;
  bool _wrapLines = true;
  bool _reverseOrder = true;
  bool _compactView = true;
  String _searchText = '';
  String _selectedLevel = 'ALL';

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final root = AppPathsBootstrapper.current.basePath;
      await AppLogger.instance.ensureFileLogging(root);
    } on Object {
      // Still try listing any files already on disk.
    }
    if (!mounted) return;
    await _loadLogFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.85) {
      _loadMoreLines();
    }
  }

  Future<void> _loadLogFiles() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final l10n = context.l10n;
    try {
      final root = AppPathsBootstrapper.current.basePath;
      final files = await AppLogger.instance.getLogFiles(appDataRoot: root);
      if (!mounted) return;
      setState(() {
        _logFiles = files;
      });
      if (files.isNotEmpty) {
        await _loadLogContent(files.first);
      } else if (mounted) {
        setState(() {
          _rawLines = [];
          _displayedLines = [];
          _selectedFile = null;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rawLines = [l10n.logViewerLoadFilesFailed('$e')];
        _displayedLines = _rawLines;
      });
    } finally {
      if (mounted && _logFiles.isEmpty) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadLogContent(String filePath) async {
    setState(() {
      _loading = true;
      _selectedFile = filePath;
      _currentPage = 0;
      _rawLines = [];
      _displayedLines = [];
    });

    final l10n = context.l10n;
    try {
      final lines = await AppLogger.instance.readLogFileLines(filePath);
      if (!mounted) return;
      setState(() {
        _rawLines = _reverseOrder ? lines.reversed.toList() : lines;
      });
      _applyFilters();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _rawLines = [l10n.logViewerReadFailed('$e')];
        _displayedLines = _rawLines;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<String> _filteredLines() {
    return filterLogLines(
      rawLines: _rawLines,
      compactView: _compactView,
      searchText: _searchText,
      selectedLevel: _selectedLevel,
    );
  }

  void _applyFilters() {
    final filtered = _filteredLines();
    setState(() {
      _currentPage = 0;
      _displayedLines = filtered.take(_pageSize).toList();
    });
  }

  void _loadMoreLines() {
    final filtered = _filteredLines();
    final nextPage = _currentPage + 1;
    final start = nextPage * _pageSize;
    if (start >= filtered.length) return;

    setState(() => _loadingMore = true);
    final end = (start + _pageSize).clamp(0, filtered.length);
    setState(() {
      _displayedLines.addAll(filtered.sublist(start, end));
      _currentPage = nextPage;
      _loadingMore = false;
    });
  }

  Future<void> _copyLogPath() async {
    final path = _selectedFile ?? AppLogger.instance.currentLogFilePath;
    if (path == null) return;
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    AppToast.show(
      context,
      message: context.l10n.logViewerPathCopied(p.basename(path)),
      variant: AppToastVariant.success,
    );
  }

  Future<void> _clearOldLogs() async {
    final l10n = context.l10n;
    try {
      await AppLogger.instance.clearOldLogs();
      await _loadLogFiles();
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.logViewerClearDone,
        variant: AppToastVariant.success,
      );
    } on Object catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.logViewerClearFailed('$e'),
        variant: AppToastVariant.error,
      );
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchText = value);
    Debounces.debounce(
      'log_search',
      const Duration(milliseconds: 400),
      _applyFilters,
    );
  }

  Future<void> _onReverseOrderChanged(bool reverseOrder) async {
    setState(() => _reverseOrder = reverseOrder);
    final file = _selectedFile;
    if (file != null) await _loadLogContent(file);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showPending =
        !AppLogger.instance.getFileLoggerInitialized() && _logFiles.isEmpty;
    final showToolbar = !showPending && _logFiles.isNotEmpty;
    final filteredCount = _filteredLines().length;

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showToolbar) ...[
            LogViewerToolbar(
              logFiles: _logFiles,
              selectedFile: _selectedFile,
              searchController: _searchController,
              selectedLevel: _selectedLevel,
              compactView: _compactView,
              wrapLines: _wrapLines,
              reverseOrder: _reverseOrder,
              lineCount: filteredCount,
              onFileSelected: (path) => unawaited(_loadLogContent(path)),
              onSearchChanged: _onSearchChanged,
              onLevelChanged: (level) {
                setState(() => _selectedLevel = level);
                _applyFilters();
              },
              onCompactViewChanged: (value) {
                setState(() => _compactView = value);
                _applyFilters();
              },
              onWrapLinesChanged: (value) => setState(() => _wrapLines = value),
              onRefresh: _loadLogFiles,
              onCopyPath: _copyLogPath,
              onClearOld: _clearOldLogs,
              onReverseOrderChanged: (value) =>
                  unawaited(_onReverseOrderChanged(value)),
            ),
            if (_loading)
              LinearProgressIndicator(
                minHeight: 2,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
              ),
          ],
          Expanded(
            child: LogViewerBody(
              logFiles: _logFiles,
              loading: _loading,
              displayedLines: _displayedLines,
              wrapLines: _wrapLines,
              loadingMore: _loadingMore,
              scrollController: _scrollController,
            ),
          ),
        ],
      ),
    );
  }
}
