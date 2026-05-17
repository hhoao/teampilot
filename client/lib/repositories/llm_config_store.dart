import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/llm_config.dart';
import '../services/remote_file_store.dart';
import 'llm_config_repository.dart';

/// Reads and writes [LlmConfig] from a local file or a remote path over SFTP.
abstract class LlmConfigStore {
  Future<LlmConfig> load();
  Future<void> save(LlmConfig config, {LlmConfig? previous});
}

class LocalLlmConfigStore implements LlmConfigStore {
  LocalLlmConfigStore(String path) : _inner = LlmConfigRepository(File(path));

  final LlmConfigRepository _inner;

  @override
  Future<LlmConfig> load() => _inner.load();

  @override
  Future<void> save(LlmConfig config, {LlmConfig? previous}) =>
      _inner.save(config, previous: previous);
}

class RemoteLlmConfigStore implements LlmConfigStore {
  RemoteLlmConfigStore({
    required String remotePath,
    required RemoteFileStore fileStore,
  })  : _remotePath = remotePath,
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
      const JsonEncoder.withIndent('  ').convert(
        config.toJson(previous: previous),
      ),
    );
  }
}
