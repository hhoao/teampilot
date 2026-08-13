import 'dart:convert';

import '../../models/hook_definition.dart';
import '../io/filesystem.dart';

/// 全局 hook 库 CRUD：`<teampilotRoot>/hooks/{id}/hook.json` + 托管脚本文件。
class HookRepository {
  HookRepository({required Filesystem fs, required String teampilotRoot})
    : _fs = fs,
      _root = fs.pathContext.join(teampilotRoot, 'hooks');

  static const definitionsFileName = 'hook.json';

  final Filesystem _fs;
  final String _root;

  String _hookDir(String id) => _fs.pathContext.join(_root, id);

  String _definitionPath(String id) =>
      _fs.pathContext.join(_hookDir(id), definitionsFileName);

  String _scriptPath(String id, String fileName) =>
      _fs.pathContext.join(_hookDir(id), fileName);

  Future<List<HookDefinition>> loadAll() async {
    if (!(await _fs.stat(_root)).isDirectory) return const [];
    final out = <HookDefinition>[];
    for (final entry in await _fs.listDir(_root)) {
      if (!entry.isDirectory) continue;
      final definition = await load(entry.name);
      if (definition != null) out.add(definition);
    }
    out.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(out);
  }

  Future<HookDefinition?> load(String id) async {
    final text = await _fs.readString(_definitionPath(id));
    if (text == null || text.trim().isEmpty) return null;
    try {
      return HookDefinition.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }

  Future<void> save(HookDefinition definition) async {
    await _fs.ensureDir(_hookDir(definition.id));
    await _fs.atomicWrite(
      _definitionPath(definition.id),
      const JsonEncoder.withIndent('  ').convert(definition.toJson()),
    );
  }

  Future<void> delete(String id) async {
    await _fs.removeRecursive(_hookDir(id));
  }

  Future<void> writeScript(String id, String fileName, String content) async {
    await _fs.ensureDir(_hookDir(id));
    await _fs.atomicWrite(_scriptPath(id, fileName), content);
  }

  Future<void> deleteScript(String id, String fileName) async {
    // Filesystem has no single-file delete primitive; removeRecursive is the
    // established pattern for removing one file (see ssh_profile_repository).
    await _fs.removeRecursive(_scriptPath(id, fileName));
  }

  Future<String?> readScript(String id, String fileName) =>
      _fs.readString(_scriptPath(id, fileName));

  Future<List<String>> scriptFileNames(String id) async {
    if (!(await _fs.stat(_hookDir(id))).isDirectory) return const [];
    final names = <String>[];
    for (final entry in await _fs.listDir(_hookDir(id))) {
      if (!entry.isDirectory && entry.name != definitionsFileName) {
        names.add(entry.name);
      }
    }
    return List.unmodifiable(names);
  }
}
