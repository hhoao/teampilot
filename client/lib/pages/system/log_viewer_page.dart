import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n_extensions.dart';
import '../../services/storage/app_storage.dart';
import '../../services/terminal/terminal_fonts.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/logger_utils.dart';
import '../../widgets/dropdown/flashsky_dropdown_field.dart';
import '../../widgets/dropdown/flashskyai_dropdown_decoration.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';

TextStyle logMonospaceStyle(BuildContext context, {Color? color}) {
  final cs = Theme.of(context).colorScheme;
  final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();
  return base.copyWith(
    fontFamily: kTerminalFontFamily,
    fontFamilyFallback: const [kUbuntuSansMonoFontFamily, 'monospace'],
    height: 1.45,
    color: color ?? cs.onSurface.withValues(alpha: 0.92),
  );
}

bool isLogDecorationLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return true;
  if (t.startsWith('│ #') ||
      t.startsWith('├') ||
      t.startsWith('└') ||
      t.startsWith('┌')) {
    return true;
  }
  return RegExp(r'^[│┌┐└┘├┤─\s#0-9.:]+$').hasMatch(t);
}

Color? logLineColor(BuildContext context, String line) {
  final upper = line.toUpperCase();
  final cs = Theme.of(context).colorScheme;
  if (upper.contains('ERROR') || upper.contains('EXCEPTION')) {
    return cs.error;
  }
  if (upper.contains('WARNING') || upper.contains('WARN')) {
    return cs.tertiary;
  }
  if (upper.contains('DEBUG')) {
    return cs.onSurfaceVariant;
  }
  return null;
}

/// Logs section inside [ConfigWorkspace] (settings split layout + padding).
class LogConfigWorkspace extends StatelessWidget {
  const LogConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          WorkspaceSectionHeading(
            title: l10n.logViewerTitle,
            subtitle: l10n.logViewerSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(child: _LogViewerPanel()),
      ],
    );
  }
}

/// Standalone shell (e.g. startup error flow).
class LogViewerPage extends StatelessWidget {
  const LogViewerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.logViewerTitle)),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: const LogConfigWorkspace(),
      ),
    );
  }
}

class _LogViewerPanel extends StatefulWidget {
  const _LogViewerPanel();

  @override
  State<_LogViewerPanel> createState() => _LogViewerPanelState();
}

class _LogViewerPanelState extends State<_LogViewerPanel> {
  static const _pageSize = 500;
  static const _levels = ['ALL', 'DEBUG', 'INFO', 'WARNING', 'ERROR'];

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

  List<String> _filteredLines() {
    var filtered = List<String>.from(_rawLines);
    if (_compactView) {
      filtered = filtered.where((l) => !isLogDecorationLine(l)).toList();
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.logViewerPathCopied(p.basename(path)))),
    );
  }

  Future<void> _clearOldLogs() async {
    final l10n = context.l10n;
    try {
      await AppLogger.instance.clearOldLogs();
      await _loadLogFiles();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.logViewerClearDone)));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.logViewerClearFailed('$e'))),
      );
    }
  }

  InputDecoration _toolbarFieldDecoration(
    BuildContext context, {
    String? hintText,
    Widget? prefixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTextStyles.of(context).body.copyWith(
        color: cs.onSurfaceVariant,
      ),
      prefixIcon: prefixIcon,
      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      filled: true,
      fillColor: cs.workspaceInset,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.65)),
      ),
    );
  }

  Widget _toolbarIconToggle({
    required BuildContext context,
    required String tooltip,
    required IconData onIcon,
    required IconData offIcon,
    required bool value,
    required VoidCallback onPressed,
  }) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      style: IconButton.styleFrom(
        backgroundColor: value
            ? cs.primaryContainer.withValues(alpha: 0.7)
            : cs.workspaceInset,
        foregroundColor: value ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      ),
      icon: Icon(value ? onIcon : offIcon, size: 20),
      onPressed: onPressed,
    );
  }

  static const _toolbarControlHeight = 36.0;
  static const _toolbarVerticalPadding = 10.0;
  static const _toolbarDropdownPadding = EdgeInsets.symmetric(
    vertical: 4,
    horizontal: 10,
  );

  Widget _toolbarFlashskyDropdown<T extends Object>({
    required BuildContext context,
    required double width,
    required List<T> items,
    required T value,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: width,
      height: _toolbarControlHeight,
      child: FlashskyDropdownField<T>(
        key: ValueKey<T>(value),
        items: items,
        initialItem: value,
        decoration: FlashskyDropdownDecorations.settingsCompact(context),
        closedHeaderPadding: _toolbarDropdownPadding,
        expandedHeaderPadding: _toolbarDropdownPadding,
        itemLabel: itemLabel,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildLogToolbar(BuildContext context, int lineCount) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final fileValue = _selectedFile ?? (_logFiles.isNotEmpty ? _logFiles.first : null);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, _toolbarVerticalPadding, 8, _toolbarVerticalPadding),
      decoration: BoxDecoration(
        color: cs.workspaceInset,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SizedBox(
        height: _toolbarControlHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (fileValue != null) ...[
              _toolbarFlashskyDropdown<String>(
                context: context,
                width: 168,
                items: _logFiles,
                value: fileValue,
                itemLabel: p.basename,
                onChanged: (v) {
                  if (v != null) unawaited(_loadLogContent(v));
                },
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: TextField(
                controller: _searchController,
                style: AppTextStyles.of(context).body,
                decoration: _toolbarFieldDecoration(
                  context,
                  hintText: l10n.logViewerSearchHint,
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
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
            const SizedBox(width: 8),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _toolbarFlashskyDropdown<String>(
                      context: context,
                      width: 108,
                      items: _levels,
                      value: _selectedLevel,
                      itemLabel: (l) => l,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedLevel = v);
                        _applyFilters();
                      },
                    ),
                    const SizedBox(width: 4),
                    _toolbarIconToggle(
                      context: context,
                      tooltip: l10n.logViewerCompactView,
                      onIcon: Icons.filter_alt,
                      offIcon: Icons.filter_alt_outlined,
                      value: _compactView,
                      onPressed: () {
                        setState(() => _compactView = !_compactView);
                        _applyFilters();
                      },
                    ),
                    _toolbarIconToggle(
                      context: context,
                      tooltip: l10n.logViewerWrapLines,
                      onIcon: Icons.wrap_text,
                      offIcon: Icons.wrap_text_outlined,
                      value: _wrapLines,
                      onPressed: () => setState(() => _wrapLines = !_wrapLines),
                    ),
                    PopupMenuButton<String>(
                      tooltip: l10n.logViewerActionsMenu,
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                      onSelected: (action) async {
                        switch (action) {
                          case 'refresh':
                            await _loadLogFiles();
                          case 'copy':
                            await _copyLogPath();
                          case 'clear':
                            await _clearOldLogs();
                          case 'reverse':
                            setState(() => _reverseOrder = !_reverseOrder);
                            final file = _selectedFile;
                            if (file != null) await _loadLogContent(file);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'refresh',
                          child: _menuRow(Icons.refresh, l10n.logViewerRefresh),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: _menuRow(Icons.copy_outlined, l10n.logViewerCopyPath),
                        ),
                        PopupMenuItem(
                          value: 'clear',
                          child: _menuRow(
                            Icons.cleaning_services_outlined,
                            l10n.logViewerClearOld,
                          ),
                        ),
                        CheckedPopupMenuItem(
                          value: 'reverse',
                          checked: _reverseOrder,
                          child: _menuRow(Icons.swap_vert, l10n.logViewerReverseOrder),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.logViewerLineCount(lineCount),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget lineWidget(int index, String line) {
      final tinted = logLineColor(context, line);
      final bg = index.isEven
          ? Colors.transparent
          : cs.onSurface.withValues(alpha: 0.03);
      return ColoredBox(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: SelectableText(
            line,
            style: logMonospaceStyle(context, color: tinted),
          ),
        ),
      );
    }

    if (_wrapLines) {
      return ListView.builder(
        controller: _scrollController,
        itemCount: _displayedLines.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _displayedLines.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return lineWidget(index, _displayedLines[index]);
        },
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 2000,
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _displayedLines.length,
          itemBuilder: (context, index) =>
              lineWidget(index, _displayedLines[index]),
        ),
      ),
    );
  }

  static Widget _menuRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }

  Widget _buildCenteredMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: cs.primary.withValues(alpha: 0.55)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final showPending =
        !AppLogger.instance.getFileLoggerInitialized() && _logFiles.isEmpty;

    if (showPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              l10n.logViewerPendingTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              l10n.logViewerPendingBody,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: cs.workspaceCode,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  AppLogger.instance.getFormattedPendingLogs(),
                  style: logMonospaceStyle(context),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_logFiles.isEmpty && !_loading) {
      return _buildCenteredMessage(
        context,
        icon: Icons.article_outlined,
        title: l10n.logViewerEmpty,
        subtitle: l10n.logViewerEmptyHint,
      );
    }

    return ColoredBox(
      color: cs.workspaceCode,
      child: _buildLogList(context),
    );
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
            _buildLogToolbar(context, filteredCount),
            if (_loading)
              LinearProgressIndicator(
                minHeight: 2,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
              ),
          ],
          Expanded(child: _buildLogBody(context)),
        ],
      ),
    );
  }
}
