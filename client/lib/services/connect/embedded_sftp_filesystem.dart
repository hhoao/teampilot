/// SFTP filesystem for the embedded SSH server, backed by dart:io native
/// paths.
///
/// There is no sandbox: the SFTP client sees the machine's real filesystem.
/// On POSIX, an SFTP path maps to itself — `/home/u/x` is that directory.
/// On Windows the SFTP protocol's `/`-rooted paths have no native meaning,
/// so a leading-`/` path resolves under [EmbeddedSftpFilesystem.homePath]
/// (the user's home) and a drive path (`C:/x`, `C:\x`) resolves as-is. The
/// path context is injected so the Windows mapping can be exercised on any
/// host.
library;

import 'dart:io';

import 'package:dartssh2/protocol.dart'
    show SftpFileAttrs, SftpFileMode, SftpFileOpenMode, SftpName;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:tp_sshd/tp_sshd.dart';

/// [SftpFileSystem] over dart:io.
///
/// Requests on one handle are serialized with a lock chain — the package
/// dispatches SFTP requests concurrently and dart:io position+read/write
/// pairs are not atomic.
class EmbeddedSftpFilesystem implements SftpFileSystem {
  EmbeddedSftpFilesystem({
    required p.Context pathContext,
    required this.homePath,
  }) : _pathContext = pathContext;

  final p.Context _pathContext;

  /// The native user home; the anchor for windows-context rooted paths.
  final String homePath;

  @override
  Future<SftpFileAttrs> stat(String path) async {
    final fsPath = _resolve(path);
    final stat = FileStat.statSync(fsPath);
    if (stat.type == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(path);
    }
    return _attrsOf(stat);
  }

  @override
  Future<SftpDirListing> openDir(String path) async {
    final fsPath = _resolve(path);
    final type = FileSystemEntity.typeSync(fsPath);
    if (type == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(path);
    }
    if (type != FileSystemEntityType.directory) {
      throw SftpFileSystemException('not a directory: $path');
    }
    return _IoDirListing(Directory(fsPath));
  }

  @override
  Future<SftpHandle> openFile(
    String path,
    SftpFileOpenMode mode,
    SftpFileAttrs? attrs,
  ) async {
    final fsPath = _resolve(path);
    final type = FileSystemEntity.typeSync(fsPath);
    if (type == FileSystemEntityType.directory) {
      throw SftpFileSystemException('is a directory: $path');
    }
    if (type != FileSystemEntityType.notFound) {
      if (mode.flag & SftpFileOpenMode.exclusive.flag != 0) {
        throw SftpFileExistsException(path);
      }
    } else {
      if (mode.flag & SftpFileOpenMode.create.flag == 0) {
        throw SftpNoSuchFileException(path);
      }
      final parent = File(fsPath).parent;
      if (!parent.existsSync()) {
        throw SftpNoSuchFileException(path);
      }
    }
    final wantWrite = mode.flag & SftpFileOpenMode.write.flag != 0;
    final wantTruncate = mode.flag & SftpFileOpenMode.truncate.flag != 0;
    // dart:io has no O_RDWR-without-trunc FileMode, but [FileMode.append] is
    // exactly that on every supported platform: `O_RDWR | O_CREAT` plus a
    // one-time seek to end (the SDK's runtime/bin/file_linux.cc and
    // file_win.cc both implement it this way — no O_APPEND / FILE_APPEND_DATA
    // forced-to-end writes). Positioned writes therefore work, so it is the
    // correct open for WRITE-without-TRUNC (random-access in-place writes,
    // resume uploads) as well as for APPEND, and never destroys existing
    // content. [FileMode.write] is only used when the client explicitly
    // asked for TRUNC.
    final file = File(fsPath).openSync(
      mode: _openMode(wantWrite: wantWrite, wantTruncate: wantTruncate),
    );
    return _IoSftpHandle(
      file,
      append: mode.flag & SftpFileOpenMode.append.flag != 0,
    );
  }

  @override
  Future<void> mkdir(String path, SftpFileAttrs attrs) async {
    final fsPath = _resolve(path);
    if (FileSystemEntity.typeSync(fsPath) != FileSystemEntityType.notFound) {
      throw SftpFileExistsException(path);
    }
    try {
      Directory(fsPath).createSync();
    } on FileSystemException catch (error) {
      _throwMapped(error, path);
    }
  }

  @override
  Future<void> rmdir(String path) async {
    final fsPath = _resolve(path);
    if (FileSystemEntity.typeSync(fsPath) == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(path);
    }
    try {
      Directory(fsPath).deleteSync();
    } on FileSystemException catch (error) {
      _throwMapped(error, path);
    }
  }

  @override
  Future<void> unlink(String path) async {
    final fsPath = _resolve(path);
    final type = FileSystemEntity.typeSync(fsPath);
    if (type == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(path);
    }
    if (type == FileSystemEntityType.directory) {
      throw SftpFileSystemException('is a directory: $path');
    }
    try {
      File(fsPath).deleteSync();
    } on FileSystemException catch (error) {
      _throwMapped(error, path);
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    final fsFrom = _resolve(from);
    final fsTo = _resolve(to);
    if (FileSystemEntity.typeSync(fsFrom) == FileSystemEntityType.notFound) {
      throw SftpNoSuchFileException(from);
    }
    if (FileSystemEntity.typeSync(fsTo) != FileSystemEntityType.notFound) {
      throw SftpFileExistsException(to);
    }
    try {
      if (FileSystemEntity.typeSync(fsFrom) == FileSystemEntityType.directory) {
        Directory(fsFrom).renameSync(fsTo);
      } else {
        File(fsFrom).renameSync(fsTo);
      }
    } on FileSystemException catch (error) {
      _throwMapped(error, from);
    }
  }

  @override
  Future<String> realpath(String path) async => _normalizeLexical(path);

  /// The native on-disk path for an SFTP path.
  ///
  /// POSIX context: the path maps to itself — the SFTP root is the native
  /// root. Windows context: a drive path (`C:/x`, `C:\x`) resolves as-is;
  /// any other path (the leading-`/` form SFTP clients send) resolves under
  /// [homePath].
  String _resolve(String path) {
    if (_pathContext.style == p.Style.windows) {
      if (path.length >= 2 && path[1] == ':') {
        return _pathContext.normalize(path);
      }
      final segments = _normalizeLexical(
        path,
      ).split('/').where((segment) => segment.isNotEmpty).toList();
      return _pathContext.joinAll([homePath, ...segments]);
    }
    return path;
  }

  /// Exposes the SFTP-to-native path mapping for tests.
  String resolveForTest(String path) => _resolve(path);

  /// Exposes the directory-listing base name for tests (the windows-context
  /// mapping cannot be exercised end-to-end off-Windows).
  @visibleForTesting
  static String baseNameForTest(String path) => _baseName(path);

  /// The final path segment after either separator — dart:io uses '/' on
  /// POSIX and '\' on Windows, and SFTP clients expect a bare filename.
  static String _baseName(String path) {
    var index = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    if (backslash > index) index = backslash;
    return index < 0 ? path : path.substring(index + 1);
  }

  /// Lexical `/`-separator normalization: collapses `.` and `..` without
  /// touching the filesystem.
  static String _normalizeLexical(String path) {
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    return '/${segments.join('/')}';
  }

  /// The dart:io open mode for an SFTP open: read when no WRITE flag,
  /// truncating write only on explicit TRUNC, non-truncating read+write
  /// (append-mode open) otherwise so existing content survives.
  static FileMode _openMode({
    required bool wantWrite,
    required bool wantTruncate,
  }) {
    if (!wantWrite) return FileMode.read;
    return wantTruncate ? FileMode.write : FileMode.append;
  }

  static SftpFileAttrs _attrsOf(FileStat stat) => SftpFileAttrs(
    size: stat.size,
    mode: SftpFileMode.value(stat.mode),
    accessTime: stat.accessed.millisecondsSinceEpoch ~/ 1000,
    modifyTime: stat.modified.millisecondsSinceEpoch ~/ 1000,
  );

  static Never _throwMapped(FileSystemException error, String path) {
    switch (error.osError?.errorCode) {
      case 2: // ENOENT
      case 20: // ENOTDIR
        throw SftpNoSuchFileException(path);
      case 13: // EACCES
        throw SftpPermissionDeniedException(path);
      case 17: // EEXIST
        throw SftpFileExistsException(path);
      case 39: // ENOTEMPTY
        throw SftpFileSystemException('directory not empty: $path');
      default:
        throw SftpFileSystemException(error.message);
    }
  }
}

class _IoSftpHandle implements SftpHandle {
  _IoSftpHandle(this._file, {required this.append});

  final RandomAccessFile _file;
  final bool append;

  /// Serialized operations: the SFTP server dispatches concurrently, but a
  /// position+read/write pair on one handle must stay atomic.
  Future<void> _lock = Future.value();

  @override
  Future<Uint8List> read(int offset, int length) {
    return _enqueue(() async {
      await _file.setPosition(offset);
      return _file.read(length);
    });
  }

  @override
  Future<void> write(int offset, Uint8List data) {
    return _enqueue(() async {
      final target = append ? await _file.length() : offset;
      await _file.setPosition(target);
      await _file.writeFrom(data);
    });
  }

  @override
  Future<void> close() => _enqueue(_file.close);

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _lock.then((_) => operation());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }
}

class _IoDirListing implements SftpDirListing {
  _IoDirListing(this._directory);

  final Directory _directory;
  bool _closed = false;

  @override
  Future<List<SftpName>> read() async {
    if (_closed) return const [];
    _closed = true;
    final names = <SftpName>[];
    await for (final entity in _directory.list()) {
      final stat = entity.statSync();
      final baseName = EmbeddedSftpFilesystem._baseName(entity.path);
      names.add(
        SftpName(
          filename: baseName,
          longname: _longName(stat, baseName),
          attr: EmbeddedSftpFilesystem._attrsOf(stat),
        ),
      );
    }
    return names;
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

/// A lazy `ls -l`-style long name; clients only display it.
String _longName(FileStat stat, String name) {
  final mode = stat.modeString();
  final kind = stat.type == FileSystemEntityType.directory ? 'd' : '-';
  final size = stat.size.toString().padLeft(8);
  final mtime = stat.modified
      .toIso8601String()
      .substring(0, 16)
      .replaceAll('T', ' ');
  final owner = Platform.environment['USER'] ?? 'user';
  return '$kind$mode 1 $owner $size $mtime $name';
}
