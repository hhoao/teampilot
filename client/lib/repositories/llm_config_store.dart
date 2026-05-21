import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/llm_config.dart';
import '../services/app_storage.dart';
import '../services/io/filesystem.dart';
import '../services/remote_file_store.dart';

/// Reads and writes [LlmConfig] from a local file or a remote path over SFTP.
abstract class LlmConfigStore {
  Future<LlmConfig> load();
  Future<void> save(LlmConfig config, {LlmConfig? previous});
}

class FilesystemLlmConfigStore implements LlmConfigStore {
  FilesystemLlmConfigStore({
    required String path,
    Filesystem? fs,
  }) : _path = path,
       _fs = fs ?? AppStorage.fs;

  final String _path;
  final Filesystem _fs;

  @override
  Future<LlmConfig> load() async {
    final content = await _fs.readString(_path);
    if (content == null || content.isEmpty) {
      return const LlmConfig();
    }
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return const LlmConfig();
      }
      return LlmConfig.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const LlmConfig();
    } on TypeError {
      return const LlmConfig();
    }
  }

  @override
  Future<void> save(LlmConfig config, {LlmConfig? previous}) async {
    final parent = _fs.pathContext.dirname(_path);
    if (parent.isNotEmpty && parent != '.' && parent != '/') {
      await _fs.ensureDir(parent);
    }
    await _fs.atomicWrite(
      _path,
      const JsonEncoder.withIndent(
        '  ',
      ).convert(config.toJson(previous: previous)),
    );
  }
}

@Deprecated('Use FilesystemLlmConfigStore')
class LocalLlmConfigStore extends FilesystemLlmConfigStore {
  LocalLlmConfigStore(String path) : super(path: path);
}

class RemoteLlmConfigStore implements LlmConfigStore {
  RemoteLlmConfigStore({
    required String remotePath,
    required RemoteFileStore fileStore,
  }) : _remotePath = remotePath,
       _fileStore = fileStore;

  final String _remotePath;
  final RemoteFileStore _fileStore;

  @override
  Future<LlmConfig> load() async {
    final content = await _fileStore.readFile(_remotePath);
    if (content == null || content.isEmpty) {
      return const LlmConfig();
    }
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return const LlmConfig();
      }
      return LlmConfig.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const LlmConfig();
    } on TypeError {
      return const LlmConfig();
    }
  }

  @override
  Future<void> save(LlmConfig config, {LlmConfig? previous}) async {
    final posix = p.Context(style: p.Style.posix);
    final parent = posix.dirname(_remotePath);
    if (parent.isNotEmpty && parent != '.' && parent != '/') {
      await _fileStore.createDirectory(parent);
    }
    await _fileStore.writeFile(
      _remotePath,
      const JsonEncoder.withIndent(
        '  ',
      ).convert(config.toJson(previous: previous)),
    );
  }
}
