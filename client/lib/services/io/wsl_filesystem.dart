import 'dart:convert';

import 'package:path/path.dart' as p;

import '../remote_file_store.dart';
import 'filesystem.dart';
import 'wsl_shell_session.dart';

class WslFilesystem implements Filesystem {
  WslFilesystem({String? distro, WslShellSession? session})
    : _session = session ?? WslShellSession(distro: distro);

  final WslShellSession _session;

  @override
  p.Context get pathContext => p.Context(style: p.Style.posix);

  WslShellSession get session => _session;

  Future<void> closeSession() => _session.close();

  Future<({int exitCode, String stdout, String stderr})> _run(
    String script,
  ) async {
    final result = await _session.run(script);
    if (result.exitCode != 0) {
      throw StateError(
        'wsl script failed (${result.exitCode}): ${result.stderr}',
      );
    }
    return result;
  }

  Future<({int exitCode, String stdout, String stderr})> _runAllowFail(
    String script,
  ) => _session.run(script);

  @override
  Future<FsStat> stat(String path) async {
    final quoted = RemoteFileStore.shellSingleQuote(path);
    final result = await _runAllowFail('''
if [ -L $quoted ]; then echo symlink
elif [ -d $quoted ]; then echo directory
elif [ -f $quoted ]; then echo file
else echo missing
fi
''');
    if (result.exitCode != 0) return const FsStat(kind: FsEntityKind.notFound);
    return switch (result.stdout.trim()) {
      'directory' => const FsStat(kind: FsEntityKind.directory),
      'file' => const FsStat(kind: FsEntityKind.file),
      'symlink' => const FsStat(kind: FsEntityKind.symlink),
      _ => const FsStat(kind: FsEntityKind.notFound),
    };
  }

  @override
  Future<void> ensureDir(String path) async {
    await _run('mkdir -p -- ${RemoteFileStore.shellSingleQuote(path)}');
  }

  @override
  Future<void> removeRecursive(String path) async {
    await _run('rm -rf -- ${RemoteFileStore.shellSingleQuote(path)}');
  }

  @override
  Future<void> rename(String from, String to) async {
    await ensureDir(pathContext.dirname(to));
    await removeRecursive(to);
    await _run(
      'mv -- ${RemoteFileStore.shellSingleQuote(from)} ${RemoteFileStore.shellSingleQuote(to)}',
    );
  }

  @override
  Future<String?> readString(String path) async {
    final result = await _runAllowFail(
      'cat -- ${RemoteFileStore.shellSingleQuote(path)}',
    );
    if (result.exitCode != 0) return null;
    return result.stdout;
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final quoted = RemoteFileStore.shellSingleQuote(path);
    final result = await _runAllowFail(
      'base64 -w0 $quoted 2>/dev/null || base64 $quoted',
    );
    if (result.exitCode != 0) return null;
    final encoded = result.stdout.replaceAll(RegExp(r'\s+'), '');
    if (encoded.isEmpty) return null;
    try {
      return base64.decode(encoded);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeString(String path, String content) async {
    await ensureDir(pathContext.dirname(path));
    final encoded = base64.encode(utf8.encode(content));
    final quotedPath = RemoteFileStore.shellSingleQuote(path);
    await _run(
      'printf %s ${RemoteFileStore.shellSingleQuote(encoded)} | base64 -d > $quotedPath',
    );
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await ensureDir(pathContext.dirname(path));
    final encoded = base64.encode(bytes);
    final quotedPath = RemoteFileStore.shellSingleQuote(path);
    await _run(
      'printf %s ${RemoteFileStore.shellSingleQuote(encoded)} | base64 -d > $quotedPath',
    );
  }

  @override
  Future<void> atomicWrite(String path, String content) async {
    final tmp = '$path.tmp.${DateTime.now().microsecondsSinceEpoch}';
    await writeString(tmp, content);
    await rename(tmp, path);
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    final quoted = RemoteFileStore.shellSingleQuote(path);
    final result = await _runAllowFail(
      'find $quoted -mindepth 1 -maxdepth 1 -printf "%f\\t%y\\n"',
    );
    if (result.exitCode != 0) return const [];
    return [
      for (final line in result.stdout.split('\n'))
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
    await _run(
      'ln -sf -- ${RemoteFileStore.shellSingleQuote(target)} ${RemoteFileStore.shellSingleQuote(linkPath)}',
    );
    return true;
  }

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    await ensureDir(pathContext.dirname(destination));
    await removeRecursive(destination);
    await ensureDir(destination);
    await _run(
      'cp -R -- ${RemoteFileStore.shellSingleQuote('$source/.')} ${RemoteFileStore.shellSingleQuote(destination)}',
    );
  }
}
