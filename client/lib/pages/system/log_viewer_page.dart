import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../utils/debounce/debounce.dart';
import '../../utils/logger_utils.dart';

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.selectedLevel,
    required this.wrapLines,
    required this.reverseOrder,
    required this.onLevelChanged,
    required this.onWrapLinesChanged,
    required this.onReverseOrderChanged,
  });

  final String selectedLevel;
  final bool wrapLines;
  final bool reverseOrder;
  final ValueChanged<String> onLevelChanged;
  final ValueChanged<bool> onWrapLinesChanged;
  final ValueChanged<bool> onReverseOrderChanged;

  static const _levels = ['ALL', 'DEBUG', 'INFO', 'WARNING', 'ERROR'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('过滤', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('级别'),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: selectedLevel,
                  items: _levels
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onLevelChanged(v);
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动换行'),
            value: wrapLines,
            onChanged: onWrapLinesChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('从最新内容开始'),
            value: reverseOrder,
            onChanged: onReverseOrderChanged,
          ),
        ],
      ),
    );
  }
}

/// In-app viewer for `{appData}/logs/app_*.log` and `errors.jsonl`.
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  static const _pageSize = 500;

  List<String> _logFiles = [];
  List<String> _rawLines = [];
  List<String> _displayedLines = [];
  String? _selectedFile;

  bool _loading = true;
  bool _loadingMore = false;
  bool _wrapLines = true;
  bool _reverseOrder = true;
  String _searchText = '';
  String _selectedLevel = 'ALL';

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadLogFiles();
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
    setState(() => _loading = true);
    try {
      final files = await AppLogger.instance.getLogFiles();
      if (!mounted) return;
      setState(() {
        _logFiles = files;
        _loading = false;
      });
      if (files.isNotEmpty) {
        await _loadLogContent(files.first);
      } else {
        setState(() {
          _rawLines = [];
          _displayedLines = [];
          _selectedFile = null;
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rawLines = ['加载日志列表失败: $e'];
        _displayedLines = _rawLines;
      });
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

    try {
      final lines = await File(filePath).readAsLines();
      if (!mounted) return;
      setState(() {
        _rawLines = _reverseOrder ? lines.reversed.toList() : lines;
        _loading = false;
      });
      _applyFilters();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rawLines = ['读取日志失败: $e'];
        _displayedLines = _rawLines;
      });
    }
  }

  bool _lineMatchesLevel(String line, String level) {
    final upper = line.toUpperCase();
    return switch (level) {
      'DEBUG' => upper.contains('DEBUG'),
      'INFO' => upper.contains('INFO') || upper.contains('[BOOT]'),
      'WARNING' => upper.contains('WARNING') || upper.contains('WARN'),
      'ERROR' => upper.contains('ERROR') || upper.contains('EXCEPTION'),
      _ => true,
    };
  }

  void _applyFilters() {
    var filtered = List<String>.from(_rawLines);

    if (_searchText.isNotEmpty) {
      final q = _searchText.toLowerCase();
      filtered = filtered.where((l) => l.toLowerCase().contains(q)).toList();
    }

    if (_selectedLevel != 'ALL') {
      filtered = filtered
          .where((l) => _lineMatchesLevel(l, _selectedLevel))
          .toList();
    }

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

  List<String> _filteredLines() {
    var filtered = List<String>.from(_rawLines);
    if (_searchText.isNotEmpty) {
      final q = _searchText.toLowerCase();
      filtered = filtered.where((l) => l.toLowerCase().contains(q)).toList();
    }
    if (_selectedLevel != 'ALL') {
      filtered = filtered
          .where((l) => _lineMatchesLevel(l, _selectedLevel))
          .toList();
    }
    return filtered;
  }

  Future<void> _copyLogPath() async {
    final path = _selectedFile ?? AppLogger.instance.currentLogFilePath;
    if (path == null) return;
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制路径: ${p.basename(path)}')),
    );
  }

  Future<void> _clearOldLogs() async {
    try {
      await AppLogger.instance.clearOldLogs();
      await _loadLogFiles();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清理过期日志文件')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清理失败: $e')));
    }
  }

  Widget _buildPendingPanel() {
    final text = AppLogger.instance.getFormattedPendingLogs();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '文件日志尚未就绪，以下为内存中待写入的条目：',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPending =
        _loading && !AppLogger.instance.getFileLoggerInitialized();

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志查看器'),
        actions: [
          IconButton(
            tooltip: '复制当前日志路径',
            icon: const Icon(Icons.copy_outlined),
            onPressed: _copyLogPath,
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogFiles,
          ),
          IconButton(
            tooltip: '清理过期日志',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _clearOldLogs,
          ),
        ],
      ),
      body: showPending
          ? _buildPendingPanel()
          : _logFiles.isEmpty
          ? Center(
              child: Text(
                '暂无日志文件',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedFile ?? _logFiles.first,
                        items: _logFiles
                            .map(
                              (f) => DropdownMenuItem(
                                value: f,
                                child: Text(p.basename(f)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) _loadLogContent(v);
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                hintText: '搜索…',
                                isDense: true,
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (value) {
                                setState(() => _searchText = value);
                                Debounces.debounce(
                                  'log_search',
                                  const Duration(milliseconds: 400),
                                  _applyFilters,
                                );
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.filter_list),
                            onPressed: () {
                              showModalBottomSheet<void>(
                                context: context,
                                showDragHandle: true,
                                builder: (ctx) => _FilterSheet(
                                  selectedLevel: _selectedLevel,
                                  wrapLines: _wrapLines,
                                  reverseOrder: _reverseOrder,
                                  onLevelChanged: (v) {
                                    setState(() => _selectedLevel = v);
                                    _applyFilters();
                                    Navigator.pop(ctx);
                                  },
                                  onWrapLinesChanged: (v) {
                                    setState(() => _wrapLines = v);
                                    Navigator.pop(ctx);
                                  },
                                  onReverseOrderChanged: (v) {
                                    setState(() => _reverseOrder = v);
                                    Navigator.pop(ctx);
                                    final file = _selectedFile;
                                    if (file != null) _loadLogContent(file);
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_loading)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  Expanded(
                    child: _wrapLines
                        ? ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            itemCount:
                                _displayedLines.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _displayedLines.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1),
                                child: SelectableText(
                                  _displayedLines[index],
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            },
                          )
                        : SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: 2400,
                              child: ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _displayedLines.length,
                                itemBuilder: (context, index) {
                                  return SelectableText(
                                    _displayedLines[index],
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
              ],
            ),
    );
  }
}
