import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot_search/teampilot_search.dart';

import '../../services/search/content_replacer.dart';

/// One matching line inside a file group.
class ContentSearchLineMatch {
  ContentSearchLineMatch({
    required this.lineNumber,
    required this.lineText,
    required this.matchStart,
    required this.matchEnd,
    this.replaced = false,
  });

  final int lineNumber;
  final String lineText;
  final int matchStart;
  final int matchEnd;

  /// True after a replace action consumed this line.
  bool replaced;
}

/// One file with its matching lines, in match order.
class ContentSearchFileGroup {
  ContentSearchFileGroup({
    required this.path,
    required this.relativePath,
    required this.lines,
  });

  final String path;
  final String relativePath;
  final List<ContentSearchLineMatch> lines;

  int get matchCount => lines.length;
}

class ContentSearchState {
  const ContentSearchState({
    this.query = '',
    this.isRegex = true,
    this.caseSensitive = false,
    this.useGitignore = true,
    this.filesToInclude = const [],
    this.filesToExclude = const [],
    this.replaceQuery = '',
    this.files = const [],
    this.truncated = false,
    this.searching = false,
    this.error,
    this.replacedCount,
  });

  final String query;
  final bool isRegex;
  final bool caseSensitive;
  final bool useGitignore;
  final List<String> filesToInclude;
  final List<String> filesToExclude;
  final String replaceQuery;
  final List<ContentSearchFileGroup> files;
  final bool truncated;
  final bool searching;
  final Object? error;

  /// Set after a replace action (per-file or all); null otherwise.
  final int? replacedCount;

  ContentSearchState copyWith({
    String? query,
    bool? isRegex,
    bool? caseSensitive,
    bool? useGitignore,
    List<String>? filesToInclude,
    List<String>? filesToExclude,
    String? replaceQuery,
    List<ContentSearchFileGroup>? files,
    bool? truncated,
    bool? searching,
    Object? error,
    bool clearError = false,
    int? replacedCount,
    bool clearReplacedCount = false,
  }) {
    return ContentSearchState(
      query: query ?? this.query,
      isRegex: isRegex ?? this.isRegex,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      useGitignore: useGitignore ?? this.useGitignore,
      filesToInclude: filesToInclude ?? this.filesToInclude,
      filesToExclude: filesToExclude ?? this.filesToExclude,
      replaceQuery: replaceQuery ?? this.replaceQuery,
      files: files ?? this.files,
      truncated: truncated ?? this.truncated,
      searching: searching ?? this.searching,
      error: clearError ? null : (error ?? this.error),
      replacedCount: clearReplacedCount ? null : (replacedCount ?? this.replacedCount),
    );
  }
}

/// Drives workspace content search: streams engine matches, aggregates them
/// into file groups (file header appears with its first match), and applies
/// replacements through [ContentReplacer].
class ContentSearchCubit extends Cubit<ContentSearchState> {
  ContentSearchCubit({
    required Stream<TpSearchMatch> Function(TpSearchOptions options) runnerFactory,
    required ContentReplacer Function() replacerFactory,
  })  : _runnerFactory = runnerFactory,
        _replacerFactory = replacerFactory,
        super(const ContentSearchState());

  final Stream<TpSearchMatch> Function(TpSearchOptions options) _runnerFactory;
  final ContentReplacer Function() _replacerFactory;

  StreamSubscription<TpSearchMatch>? _sub;
  int _searchSeq = 0;

  Future<void> search(TpSearchOptions options) async {
    final seq = ++_searchSeq;
    await _sub?.cancel();
    emit(state.copyWith(
      query: options.pattern,
      isRegex: options.isRegex,
      caseSensitive: options.caseSensitive,
      useGitignore: options.useGitignore,
      filesToInclude: options.filesToInclude,
      filesToExclude: options.filesToExclude,
      searching: true,
      error: null,
      clearError: true,
      replacedCount: null,
      clearReplacedCount: true,
    ));
    final groups = <String, ContentSearchFileGroup>{};
    final order = <String>[];

    try {
      await for (final m in _runnerFactory(options)) {
        if (seq != _searchSeq || !isClosed) {
          if (seq != _searchSeq) return;
        }
        final group = groups[m.path];
        if (group == null) {
          groups[m.path] = ContentSearchFileGroup(
            path: m.path,
            relativePath: m.relativePath,
            lines: [ContentSearchLineMatch(
              lineNumber: m.lineNumber,
              lineText: m.lineText,
              matchStart: m.matchStart,
              matchEnd: m.matchEnd,
            )],
          );
          order.add(m.path);
        } else {
          group.lines.add(ContentSearchLineMatch(
            lineNumber: m.lineNumber,
            lineText: m.lineText,
            matchStart: m.matchStart,
            matchEnd: m.matchEnd,
          ));
        }
      }
    } on Object catch (e) {
      if (seq != _searchSeq) return;
      emit(state.copyWith(searching: false, error: e));
      return;
    }
    if (seq != _searchSeq) return;
    emit(state.copyWith(
      files: [for (final p in order) groups[p]!],
      searching: false,
      clearError: true,
    ));
  }

  /// Stops the active search stream; partial results stay visible.
  void cancel() {
    _searchSeq++;
    _sub?.cancel();
    _sub = null;
    emit(state.copyWith(searching: false));
  }

  void clear() {
    _searchSeq++;
    _sub?.cancel();
    _sub = null;
    emit(state.copyWith(
      files: const [],
      searching: false,
      truncated: false,
      clearError: true,
      clearReplacedCount: true,
    ));
  }

  void setReplaceQuery(String q) => emit(state.copyWith(replaceQuery: q));

  /// Replaces every matching line across all files. Returns count applied,
  /// or null when the replace query is empty / nothing to replace.
  Future<int?> replaceAll(String replacement) async {
    if (replacement.isEmpty || state.files.isEmpty) return null;
    var total = 0;
    for (final group in state.files) {
      total += await _replaceGroup(group, replacement);
    }
    emit(state.copyWith(replacedCount: total, clearError: true));
    return total;
  }

  /// Replaces the matching lines of one file. Returns count applied.
  Future<int> replaceSingle(String path, String replacement) async {
    final group = state.files.where((g) => g.path == path).firstOrNull;
    if (group == null) return 0;
    final n = await _replaceGroup(group, replacement);
    emit(state.copyWith(replacedCount: n, clearError: true));
    return n;
  }

  Future<int> _replaceGroup(ContentSearchFileGroup group, String replacement) async {
    final replacer = _replacerFactory();
    final matches = <TpSearchMatch>[
      for (final line in group.lines)
        if (!line.replaced)
          TpSearchMatch(
            path: group.path,
            relativePath: group.relativePath,
            lineNumber: line.lineNumber,
            lineText: line.lineText,
            matchStart: line.matchStart,
            matchEnd: line.matchEnd,
          ),
    ];
    final n = await replacer.replaceAllInFile(
      path: group.path,
      matches: matches,
      replacement: replacement,
    );
    if (n > 0) {
      for (final line in group.lines) {
        line.replaced = true;
      }
    }
    return n;
  }
}
