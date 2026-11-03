import 'dart:io';

import 'package:teampilot_search/teampilot_search.dart';

import '../io/filesystem.dart';
import 'filesystem_search_reader.dart';

/// Content search facade over the workspace filesystem backend.
///
/// - Local filesystem (and Windows `\\wsl$` UNC paths): Rust engine.
/// - Everything else (SSH/SFTP): callers pass a [Filesystem] adapter
///   via [searchFilesystem] and the pure-Dart fallback engine is used.
///
/// The service is stateless: each [search] call starts its own worker isolate
/// via [IsolatedContentSearch], so concurrent searches (multiple editor panels)
/// each own their cancel handle and cannot cross-cancel one another.
class WorkspaceContentSearchService {
  WorkspaceContentSearchService();

  /// Searches [root] with the Rust engine on a worker isolate. Throws
  /// [StateError] when [root] is not locally readable — use [searchFilesystem]
  /// for remote paths.
  Stream<TpSearchMatch> search(
    String root,
    String pattern, {
    bool isRegex = true,
    bool caseSensitive = false,
    bool smartCase = false,
    bool useGitignore = true,
    List<String> filesToInclude = const [],
    List<String> filesToExclude = const [],
    int? maxResults,
  }) {
    if (!_supportsPath(root)) {
      throw StateError('path not locally readable: $root');
    }
    return IsolatedContentSearch().run(
      root,
      TpSearchOptions(
        pattern: pattern,
        isRegex: isRegex,
        caseSensitive: caseSensitive,
        smartCase: smartCase,
        useGitignore: useGitignore,
        filesToInclude: filesToInclude,
        filesToExclude: filesToExclude,
        maxResults: maxResults,
      ),
    );
  }

  /// Searches a remote/abstract filesystem through [reader].
  Stream<TpSearchMatch> searchWithReader(
    SearchFileReader reader,
    String root,
    String pattern, {
    bool isRegex = true,
    bool caseSensitive = false,
    bool smartCase = false,
    bool useGitignore = true,
    List<String> filesToInclude = const [],
    List<String> filesToExclude = const [],
    int? maxResults,
  }) {
    return fallbackSearch(
      reader,
      root,
      TpSearchOptions(
        pattern: pattern,
        isRegex: isRegex,
        caseSensitive: caseSensitive,
        smartCase: smartCase,
        useGitignore: useGitignore,
        filesToInclude: filesToInclude,
        filesToExclude: filesToExclude,
        maxResults: maxResults,
      ),
    );
  }

  /// Convenience for app filesystem backends (e.g. [SftpFilesystem]):
  /// adapts [fs] to [SearchFileReader] and uses the fallback engine.
  Stream<TpSearchMatch> searchFilesystem(
    Filesystem fs,
    String root,
    String pattern, {
    bool isRegex = true,
    bool caseSensitive = false,
    bool smartCase = false,
    bool useGitignore = true,
    List<String> filesToInclude = const [],
    List<String> filesToExclude = const [],
    int? maxResults,
  }) {
    return searchWithReader(
      FilesystemSearchReader(fs),
      root,
      pattern,
      isRegex: isRegex,
      caseSensitive: caseSensitive,
      smartCase: smartCase,
      useGitignore: useGitignore,
      filesToInclude: filesToInclude,
      filesToExclude: filesToExclude,
      maxResults: maxResults,
    );
  }

  bool _supportsPath(String root) {
    try {
      return FileSystemEntity.typeSync(root) != FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }
}
