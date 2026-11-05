import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_worker_protocol.dart';
import 'ssh_worker_storage_types.dart';

/// Worker-local I/O seam. Implementations and file handles never cross ports.
abstract interface class SshWorkerStorageBackend {
  Future<void> connect(SshWorkerRequest request);
  Future<SshWorkerRunResult> run(
    String command, {
    required bool stderr,
    Uint8List? stdin,
  });
  Future<Map<String, Object?>> metadata(
    SshWorkerOperation operation,
    String path, {
    bool directory = false,
  });
  Future<SshWorkerStorageFile> open(
    String path, {
    required bool write,
    required bool append,
  });
  void close();
}

/// One worker-owned file; reads fill [length] unless EOF is reached.
abstract interface class SshWorkerStorageFile {
  Future<Uint8List> read(int offset, int length);
  Future<void> write(Uint8List bytes, int offset);
  Future<void> close();
}

/// dartssh2 ownership for the storage actor, constructed inside the worker.
final class SshWorkerDartStorageBackend implements SshWorkerStorageBackend {
  SshWorkerDartStorageBackend({
    required this.openClient,
    required this.onClosed,
  });

  final Future<SSHClient> Function(SshWorkerRequest request) openClient;
  final void Function() onClosed;
  SSHClient? _client;
  SftpClient? _sftp;
  var _epoch = 0;

  @override
  Future<void> connect(SshWorkerRequest request) async {
    final epoch = _epoch;
    final client = await openClient(request);
    if (epoch != _epoch) {
      client.close();
      throw const SshWorkerTransportException(
        'Connection cancelled',
        code: 'cancelled',
      );
    }
    _client = client;
    unawaited(
      client.done.then(
        (_) {
          if (identical(_client, client)) onClosed();
        },
        onError: (Object _, StackTrace __) {
          if (identical(_client, client)) onClosed();
        },
      ),
    );
    await client.authenticated;
    final sftp = await client.sftp();
    if (epoch != _epoch) {
      sftp.close();
      throw const SshWorkerTransportException(
        'Connection cancelled',
        code: 'cancelled',
      );
    }
    _sftp = sftp;
  }

  @override
  Future<SshWorkerRunResult> run(
    String command, {
    required bool stderr,
    Uint8List? stdin,
  }) async {
    if (stdin != null) {
      final result = await _client!.runWithResult(
        command,
        stderr: stderr,
        stdin: stdin,
      );
      return SshWorkerRunResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
        signalName: result.exitSignal?.signalName,
        maxOutputBytes: sshWorkerMaxStorageExecOutput,
      );
    }
    final session = await _client!.execute(command);
    final stdoutBytes = BytesBuilder(copy: false);
    final stderrBytes = BytesBuilder(copy: false);
    var total = 0;
    Future<void> collect(
      Stream<Uint8List> stream,
      BytesBuilder target,
      bool capture,
    ) async {
      await for (final bytes in stream) {
        if (!capture) continue;
        total += bytes.length;
        if (total > sshWorkerMaxStorageExecOutput) {
          session.close();
          throw const SshWorkerTransportException(
            'Exec output limit exceeded',
            code: 'output_limit',
          );
        }
        target.add(bytes);
      }
    }

    try {
      await Future.wait([
        collect(session.stdout, stdoutBytes, true),
        collect(session.stderr, stderrBytes, stderr),
        session.done,
      ], eagerError: true);
      return SshWorkerRunResult(
        stdout: stdoutBytes.takeBytes(),
        stderr: stderrBytes.takeBytes(),
        exitCode: session.exitCode,
        signalName: session.exitSignal?.signalName,
        maxOutputBytes: sshWorkerMaxStorageExecOutput,
      );
    } finally {
      session.close();
    }
  }

  @override
  Future<Map<String, Object?>> metadata(
    SshWorkerOperation operation,
    String path, {
    bool directory = false,
  }) async {
    final sftp = _sftp!;
    switch (operation) {
      case SshWorkerOperation.statSftp:
        return _stat(await sftp.stat(path)).toWire();
      case SshWorkerOperation.listSftpDirectory:
        return {
          'entries': [
            for (final entry in await sftp.listdir(path))
              SshWorkerDirectoryEntry(
                name: entry.filename,
                stat: _stat(entry.attr),
              ).toWire(),
          ],
        };
      case SshWorkerOperation.readlinkSftp:
        return {'path': await sftp.readlink(path)};
      case SshWorkerOperation.realpathSftp:
        return {'path': await sftp.absolute(path)};
      case SshWorkerOperation.mkdirSftp:
        await sftp.mkdir(path);
      case SshWorkerOperation.removeSftp:
        if (directory) {
          await sftp.rmdir(path);
        } else {
          await sftp.remove(path);
        }
      default:
        throw ArgumentError('Unsupported storage metadata operation');
    }
    return const {};
  }

  @override
  Future<SshWorkerStorageFile> open(
    String path, {
    required bool write,
    required bool append,
  }) async {
    final mode = write
        ? SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              (append ? SftpFileOpenMode.append : SftpFileOpenMode.truncate)
        : SftpFileOpenMode.read;
    return _DartStorageFile(await _sftp!.open(path, mode: mode));
  }

  @override
  void close() {
    _epoch++;
    _client = null;
    _sftp?.close();
    _sftp = null;
    // The SSH client is owned by SshWorkerSharedClient and may still serve
    // member/forward planes; only the storage-local SFTP view is closed here.
  }

  SshWorkerFileStat _stat(SftpFileAttrs attrs) => SshWorkerFileStat(
    size: attrs.size,
    modifyTime: attrs.modifyTime,
    kind: attrs.isDirectory
        ? 'directory'
        : attrs.isSymbolicLink
        ? 'symlink'
        : attrs.mode?.type == SftpFileType.regularFile
        ? 'file'
        : 'unknown',
  );
}

final class _DartStorageFile implements SshWorkerStorageFile {
  _DartStorageFile(this.file);
  final SftpFile file;
  @override
  Future<Uint8List> read(int offset, int length) =>
      file.readBytes(offset: offset, length: length);
  @override
  Future<void> write(Uint8List bytes, int offset) =>
      file.writeBytes(bytes, offset: offset);
  @override
  Future<void> close() => file.close();
}
