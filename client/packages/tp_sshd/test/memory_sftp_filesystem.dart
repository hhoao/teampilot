import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart';
import 'package:tp_sshd/tp_sshd.dart';

/// In-memory [SftpFileSystem] for the dual SFTP tests: a tree of nodes keyed
/// by normalized absolute paths, with the root directory always present.
///
/// The node model mirrors what the wire exercises: directories, file bytes,
/// and a modification time that every mutation refreshes. Errors are thrown
/// as the typed exceptions the SFTP server maps onto wire status codes.
class MemorySftpFileSystem implements SftpFileSystem {
  final _nodes = <String, _MemoryNode>{'/': _MemoryNode.directory()};

  /// Lengths of every file read issued through [openFile] handles, in order,
  /// so tests can assert what the server asked the filesystem for — not just
  /// what made it back onto the wire.
  final fileReadLengths = <int>[];

  /// Creates a regular file at [path] (parents must already exist) holding
  /// [bytes], for tests that need file content — or a directory with many
  /// entries — without opening a connection per file.
  void createFile(String path, {List<int> bytes = const []}) {
    final normalized = _normalize(path);
    final parent = _nodes[_parentOf(normalized)]!;
    if (!parent.isDirectory) {
      throw StateError('not a directory: $path');
    }
    _nodes[normalized] = _MemoryNode.file()..bytes = Uint8List.fromList(bytes);
  }

  /// Creates an empty directory at [path] (the parent must already exist).
  void createDirectory(String path) {
    final normalized = _normalize(path);
    final parent = _nodes[_parentOf(normalized)]!;
    if (!parent.isDirectory) {
      throw StateError('not a directory: $path');
    }
    _nodes[normalized] = _MemoryNode.directory();
  }

  @override
  Future<SftpFileAttrs> stat(String path) async {
    final node = _nodes[_normalize(path)];
    if (node == null) throw SftpNoSuchFileException(path);
    return node.toAttrs();
  }

  @override
  Future<SftpDirListing> openDir(String path) async {
    final node = _nodes[_normalize(path)];
    if (node == null) throw SftpNoSuchFileException(path);
    if (!node.isDirectory) {
      throw StateError('not a directory: $path');
    }
    return _MemoryDirListing(_dirEntries(path));
  }

  @override
  Future<SftpHandle> openFile(
    String path,
    SftpFileOpenMode mode,
    SftpFileAttrs? attrs,
  ) async {
    final normalized = _normalize(path);
    final parent = _nodes[_parentOf(normalized)];
    if (parent == null || !parent.isDirectory) {
      throw SftpNoSuchFileException(path);
    }
    final node = _nodes[normalized];
    if (node != null) {
      if (node.isDirectory) {
        throw StateError('is a directory: $path');
      }
      if (_hasFlag(mode, SftpFileOpenMode.exclusive)) {
        throw SftpFileExistsException(path);
      }
      if (_hasFlag(mode, SftpFileOpenMode.truncate)) {
        node.truncate();
      }
    } else {
      if (!_hasFlag(mode, SftpFileOpenMode.create)) {
        throw SftpNoSuchFileException(path);
      }
      _nodes[normalized] = _MemoryNode.file();
    }
    return _MemoryFileHandle(
      _nodes[normalized]!,
      append: _hasFlag(mode, SftpFileOpenMode.append),
      onReadLength: fileReadLengths.add,
    );
  }

  @override
  Future<void> mkdir(String path, SftpFileAttrs attrs) async {
    final normalized = _normalize(path);
    if (normalized == '/') {
      throw SftpFileExistsException(path);
    }
    final parent = _nodes[_parentOf(normalized)];
    if (parent == null || !parent.isDirectory) {
      throw SftpNoSuchFileException(path);
    }
    if (_nodes.containsKey(normalized)) {
      throw SftpFileExistsException(path);
    }
    _nodes[normalized] = _MemoryNode.directory();
  }

  @override
  Future<void> rmdir(String path) async {
    final normalized = _normalize(path);
    final node = _nodes[normalized];
    if (node == null) throw SftpNoSuchFileException(path);
    if (!node.isDirectory) throw StateError('not a directory: $path');
    if (normalized == '/') throw StateError('cannot remove the root');
    if (_childrenOf(normalized).isNotEmpty) {
      throw StateError('directory not empty: $path');
    }
    _nodes.remove(normalized);
  }

  @override
  Future<void> unlink(String path) async {
    final normalized = _normalize(path);
    final node = _nodes[normalized];
    if (node == null) throw SftpNoSuchFileException(path);
    if (node.isDirectory) throw StateError('is a directory: $path');
    _nodes.remove(normalized);
  }

  @override
  Future<void> rename(String from, String to) async {
    final fromPath = _normalize(from);
    final toPath = _normalize(to);
    final node = _nodes[fromPath];
    if (node == null) throw SftpNoSuchFileException(from);
    final parent = _nodes[_parentOf(toPath)];
    if (parent == null || !parent.isDirectory) {
      throw SftpNoSuchFileException(to);
    }
    final existing = _nodes[toPath];
    if (existing != null && existing.isDirectory) {
      throw StateError('cannot replace a directory: $to');
    }
    _nodes.remove(fromPath);
    _nodes[toPath] = node;
  }

  @override
  Future<String> realpath(String path) async => _normalize(path);

  /// Resolves [path] the way a POSIX realpath would: collapses duplicate
  /// slashes and `.` segments, resolves `..` against the parent (stopping at
  /// the root), and drops trailing slashes.
  String _normalize(String path) {
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    if (segments.isEmpty) return '/';
    return '/${segments.join('/')}';
  }

  String _parentOf(String normalizedPath) {
    final index = normalizedPath.lastIndexOf('/');
    return index <= 0 ? '/' : normalizedPath.substring(0, index);
  }

  List<String> _childrenOf(String normalizedPath) => _nodes.keys
      .where(
          (key) => key.startsWith('$normalizedPath/') && key != normalizedPath)
      .toList();

  List<SftpName> _dirEntries(String path) {
    final normalized = _normalize(path);
    final entries = <SftpName>[
      SftpName(
        filename: '.',
        longname: '.',
        attr: _nodes[normalized]!.toAttrs(),
      ),
      SftpName(
        filename: '..',
        longname: '..',
        attr: _nodes[_parentOf(normalized)]!.toAttrs(),
      ),
    ];
    for (final child in _childrenOf(normalized)..sort()) {
      final node = _nodes[child]!;
      final name = child.substring(child.lastIndexOf('/') + 1);
      entries.add(SftpName(
        filename: name,
        longname: name,
        attr: node.toAttrs(),
      ));
    }
    return entries;
  }

  static bool _hasFlag(SftpFileOpenMode mode, SftpFileOpenMode flag) =>
      (mode.flag & flag.flag) != 0;
}

/// One file or directory in the [MemorySftpFileSystem] tree.
class _MemoryNode {
  _MemoryNode.directory()
      : isDirectory = true,
        bytes = null;

  _MemoryNode.file()
      : isDirectory = false,
        bytes = Uint8List(0);

  final bool isDirectory;

  /// The file's bytes; always `null` for directories.
  Uint8List? bytes;

  var _modifyTime = 1700000000;

  void truncate() {
    bytes = Uint8List(0);
    _touch();
  }

  void _touch() => _modifyTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  SftpFileAttrs toAttrs() => SftpFileAttrs(
        size: isDirectory ? null : bytes!.length,
        mode: SftpFileMode.value(
          isDirectory ? 0x41ED : 0x81A4, // drwxr-xr-x / -rw-r--r--
        ),
        accessTime: _modifyTime,
        modifyTime: _modifyTime,
      );
}

/// Open file handle over a [_MemoryNode]: explicit-offset reads and writes
/// against the node's byte buffer, with appends always landing at the end.
class _MemoryFileHandle extends SftpHandle {
  _MemoryFileHandle(
    this._node, {
    required bool append,
    void Function(int length)? onReadLength,
  })  : _append = append,
        _onReadLength = onReadLength;

  final _MemoryNode _node;
  final bool _append;
  final void Function(int length)? _onReadLength;

  @override
  Future<Uint8List> read(int offset, int length) async {
    _onReadLength?.call(length);
    final bytes = _node.bytes!;
    if (offset < 0 || length < 0) {
      throw StateError('negative read: offset=$offset length=$length');
    }
    if (offset >= bytes.length) return Uint8List(0);
    final end = math.min(offset + length, bytes.length);
    // Copy: the caller must not observe later writes through this buffer.
    return Uint8List.fromList(bytes.sublist(offset, end));
  }

  @override
  Future<void> write(int offset, Uint8List data) async {
    if (data.isEmpty) return;
    if (_append) offset = _node.bytes!.length;
    if (offset < 0) throw StateError('negative write offset: $offset');
    var bytes = _node.bytes!;
    if (offset > bytes.length) {
      // A write past EOF zero-fills the gap, like a POSIX pwrite.
      final padded = Uint8List(offset + data.length);
      padded.setRange(0, bytes.length, bytes);
      bytes = padded;
    } else if (offset + data.length != bytes.length) {
      final grown = Uint8List(math.max(bytes.length, offset + data.length));
      grown.setRange(0, bytes.length, bytes);
      bytes = grown;
    }
    bytes.setRange(offset, offset + data.length, data);
    _node.bytes = bytes;
  }

  @override
  Future<void> close() async {
    // The node outlives the handle; nothing to release.
  }
}

/// One-shot directory listing: the first [read] returns every entry, the
/// next returns none (the SFTP server turns that into end-of-directory).
class _MemoryDirListing extends SftpDirListing {
  _MemoryDirListing(this._entries);

  final List<SftpName> _entries;
  var _read = false;

  @override
  Future<List<SftpName>> read() async {
    if (_read) return const [];
    _read = true;
    return _entries;
  }

  @override
  Future<void> close() async {
    // The listing is a snapshot; nothing to release.
  }
}
