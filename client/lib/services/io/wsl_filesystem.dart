import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../host/host_wsl_argv.dart';
import '../storage/remote_file_store.dart';
import 'filesystem.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class WslFilesystem implements Filesystem {
  WslFilesystem({String? distro, ProcessRunner? processRunner})
    : _distro = distro?.trim(),
      _processRunner = processRunner ?? Process.run;

  final String? _distro;
  final ProcessRunner _processRunner;

  @override
  p.Context get pathContext => p.Context(style: p.Style.posix);

  List<String> _args(List<String> command) {
    return HostWslArgv.prefixDistro(distro: _distro, command: command);
  }

  Future<ProcessResult> _run(List<String> command) {
    return _processRunner('wsl.exe', _args(command));
  }

  Future<void> _checked(List<String> command) async {
    final result = await _run(command);
    if (result.exitCode != 0) {
      throw StateError(
        'wsl ${command.join(' ')} failed (${result.exitCode}): ${result.stderr}',
      );
    }
  }

  @override
  Future<FsStat> stat(String path) async {
    final result = await _run(['stat', '-c', '%F', '--', path]);
    if (result.exitCode != 0) return const FsStat(kind: FsEntityKind.notFound);
    return switch ((result.stdout as String).trim()) {
      'directory' => const FsStat(kind: FsEntityKind.directory),
      'regular file' ||
      'regular empty file' => const FsStat(kind: FsEntityKind.file),
      'symbolic link' => const FsStat(kind: FsEntityKind.symlink),
      _ => const FsStat(kind: FsEntityKind.notFound),
    };
  }

  @override
  Future<void> ensureDir(String path) => _checked(['mkdir', '-p', '--', path]);

  @override
  Future<void> removeRecursive(String path) =>
      _checked(['rm', '-rf', '--', path]);

  @override
  Future<void> rename(String from, String to) async {
    await ensureDir(pathContext.dirname(to));
    await removeRecursive(to);
    await _checked(['mv', '--', from, to]);
  }

  @override
  Future<String?> readString(String path) async {
    final result = await _run(['cat', path]);
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final quoted = RemoteFileStore.shellSingleQuote(path);
    final result = await _run([
      'sh',
      '-lc',
      'base64 -w0 $quoted 2>/dev/null || base64 $quoted',
    ]);
    if (result.exitCode != 0) return null;
    final encoded = (result.stdout as String).replaceAll(RegExp(r'\s+'), '');
    if (encoded.isEmpty) return null;
    try {
      return base64.decode(encoded);
    } on Object {
      return null;
    }
  }

  Future<String> _collectStreamText(Stream<List<int>> stream) {
    return stream.transform(const Utf8Decoder()).join();
  }

  Future<void> _pipeBase64ToFile(
    String path,
    String encoded, {
    bool append = false,
  }) async {
    await ensureDir(pathContext.dirname(path));
    final quotedPath = RemoteFileStore.shellSingleQuote(path);
    final op = append ? '>>' : '>';
    final process = await Process.start(
      'wsl.exe',
      _args(['sh', '-lc', 'base64 -d $op $quotedPath']),
    );
    final stderrFuture = _collectStreamText(process.stderr);
    unawaited(process.stdout.drain());
    final payload = utf8.encode(encoded);
    const chunkSize = 64 * 1024;
    for (var offset = 0; offset < payload.length; offset += chunkSize) {
      final end = offset + chunkSize < payload.length
          ? offset + chunkSize
          : payload.length;
      process.stdin.add(payload.sublist(offset, end));
    }
    await process.stdin.close();
    final exitCode = await process.exitCode;
    final stderr = await stderrFuture;
    if (exitCode != 0) {
      throw StateError('wsl write failed ($exitCode): $stderr');
    }
  }

  @override
  Future<void> writeString(String path, String content) async {
    final encoded = base64.encode(utf8.encode(content));
    await _pipeBase64ToFile(path, encoded);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final encoded = base64.encode(bytes);
    await _pipeBase64ToFile(path, encoded);
  }

  @override
  Future<void> atomicWrite(String path, String content) async {
    final tmp = '$path.tmp.${DateTime.now().microsecondsSinceEpoch}';
    await writeString(tmp, content);
    await rename(tmp, path);
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    final result = await _run([
      'sh',
      '-lc',
      'find ${RemoteFileStore.shellSingleQuote(path)} -mindepth 1 -maxdepth 1 '
          r'-printf "%f\t%y\n"',
    ]);
    if (result.exitCode != 0) return const [];
    final lines = (result.stdout as String).split('\n');
    return [
      for (final line in lines)
        if (line.trim().isNotEmpty)
          FsDirEntry(
            name: line.split('\t').first,
            isDirectory: line.split('\t').last == 'd',
          ),
    ];
  }

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    await ensureDir(pathContext.dirname(linkPath));
    await removeRecursive(linkPath);
    await _checked(['ln', '-sf', '--', target, linkPath]);
    return true;
  }

  @override
  Future<String?> readSymlinkTarget(String linkPath) async {
    try {
      final result = await _run(['readlink', '--', linkPath]);
      if (result.exitCode != 0) return null;
      final target = result.stdout.toString().trim();
      return target.isEmpty ? null : target;
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> resolveSymlink(String path) async {
    try {
      final result = await _run(['readlink', '-f', '--', path]);
      if (result.exitCode != 0) return null;
      final resolved = result.stdout.toString().trim();
      return resolved.isEmpty ? null : resolved;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    await ensureDir(pathContext.dirname(destination));
    await removeRecursive(destination);
    await ensureDir(destination);
    await _checked([
      'sh',
      '-lc',
      'cp -R -- ${RemoteFileStore.shellSingleQuote('$source/.')} '
          '${RemoteFileStore.shellSingleQuote(destination)}',
    ]);
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    await ensureDir(pathContext.dirname(destination));
    await _checked(['cp', '--', source, destination]);
  }

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async {
    final result = await _run([
      'find',
      path,
      '-mindepth',
      '1',
      '-printf',
      r'%P\t%y\n',
    ]);
    if (result.exitCode != 0) return const [];
    final lines = (result.stdout as String).split('\n');
    return [
      for (final line in lines)
        if (line.trim().isNotEmpty)
          FsDirEntry(
            name: line.split('\t').first,
            isDirectory: line.split('\t').last == 'd',
          ),
    ];
  }

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async {
    final template = '${prefix ?? 'tmp'}XXXXXX';
    final args = <String>['mktemp', '-d'];
    if (parent != null) {
      args.addAll(['-p', parent]);
    }
    args.add(template);
    final result = await _run(args);
    if (result.exitCode != 0) {
      throw StateError('mktemp failed (${result.exitCode}): ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  @override
  Future<void> appendString(String path, String content) async {
    final encoded = base64.encode(utf8.encode(content));
    await _pipeBase64ToFile(path, encoded, append: true);
  }
}
