import 'dart:typed_data';

import 'package:dartssh2/protocol.dart'
    show SftpFileAttrs, SftpFileOpenMode, SftpName;

/// Injected filesystem the SFTP subsystem runs on. The app implements this
/// over its storage layer; tests over an in-memory tree.
///
/// Paths are absolute and use `/` separators; [realpath] is the authority on
/// normalization. Implementations report failures by throwing the typed
/// [SftpFileSystemException] subclasses (mapped onto wire status codes) —
/// anything else surfaces to the client as a generic `SSH_FX_FAILURE`.
///
/// ## Concurrency
///
/// The SFTP session dispatches requests as it parses them, without waiting
/// for earlier ones to finish: the fork's client pipelines reads and writes
/// (dozens of requests in flight at once), so any of these methods may run
/// concurrently with any other — including several operations on the same
/// path or the same handle. Implementations must not assume sequential or
/// ordered invocation; one that needs serialization (for example a
/// transactional store) has to do its own locking.
abstract class SftpFileSystem {
  /// Attributes of the file or directory at [path].
  Future<SftpFileAttrs> stat(String path);

  /// Opens [path] for reading. An empty batch from [SftpDirListing.read]
  /// later signals end-of-directory.
  Future<SftpDirListing> openDir(String path);

  /// Opens [path] as a file in [mode] (read/write/append, with
  /// create/truncate/exclusive flags), optionally seeded with [attrs].
  Future<SftpHandle> openFile(
    String path,
    SftpFileOpenMode mode,
    SftpFileAttrs? attrs,
  );

  /// Creates a directory at [path] (parents are not created).
  Future<void> mkdir(String path, SftpFileAttrs attrs);

  /// Removes the (empty, non-root) directory at [path].
  Future<void> rmdir(String path);

  /// Removes the file at [path].
  Future<void> unlink(String path);

  /// Moves the file or directory at [from] to [to].
  Future<void> rename(String from, String to);

  /// The canonical absolute path [path] refers to.
  Future<String> realpath(String path);
}

/// Opaque per-open handle. `read`/`write` take the offset: SFTPv3 is
/// stateless-offset with a handle for lifetime bookkeeping only.
abstract class SftpHandle {
  /// Reads up to [length] bytes at [offset]. An empty result means
  /// end-of-file; the result must never be longer than [length].
  Future<Uint8List> read(int offset, int length);

  /// Writes [data] at [offset].
  Future<void> write(int offset, Uint8List data);

  /// Releases the handle. Called exactly once, when the client closes it or
  /// the channel ends.
  Future<void> close();
}

/// One open directory. [read] hands out entries batch by batch; an empty
/// batch marks the end of the directory.
abstract class SftpDirListing {
  /// The next batch of entries, or an empty list once exhausted.
  ///
  /// A batch may be of any size: the SFTP server re-batches whatever [read]
  /// returns so every NAME packet it sends stays under the 256 KiB SFTP
  /// packet limit (the client's READDIR-until-EOF loop is the protocol's own
  /// paging). An implementation may therefore return a whole directory in
  /// one batch and still be fully served.
  Future<List<SftpName>> read();

  /// Releases the listing. Called exactly once, like [SftpHandle.close].
  Future<void> close();
}

/// Base of the typed errors an [SftpFileSystem] throws to pick the wire
/// status code its failure is reported with.
class SftpFileSystemException implements Exception {
  const SftpFileSystemException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The path refers to a file that should exist but does not —
/// `SSH_FX_NO_SUCH_FILE` (2).
class SftpNoSuchFileException extends SftpFileSystemException {
  const SftpNoSuchFileException(super.message);
}

/// The operation is not permitted for the caller —
/// `SSH_FX_PERMISSION_DENIED` (3).
class SftpPermissionDeniedException extends SftpFileSystemException {
  const SftpPermissionDeniedException(super.message);
}

/// The path already exists where it must not —
/// `SSH_FX_FILE_ALREADY_EXISTS` (11).
class SftpFileExistsException extends SftpFileSystemException {
  const SftpFileExistsException(super.message);
}
