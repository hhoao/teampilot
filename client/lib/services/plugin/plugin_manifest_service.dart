import 'dart:convert';
import '../../models/plugin.dart';
import '../cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'plugin_exceptions.dart';

class ParsedPlugin {
  ParsedPlugin({
    required this.name,
    required this.version,
    required this.description,
    required this.homepageUrl,
    required this.capabilities,
  });
  final String name;
  final String version;
  final String description;
  final String? homepageUrl;
  final PluginCapabilities capabilities;
}

class PluginManifestService {
  PluginManifestService({Filesystem? filesystem})
      : _fs = filesystem ?? LocalFilesystem();

  final Filesystem _fs;

  Future<ParsedPlugin> parseDirectory(String pluginDir) async {
    Map<String, Object?>? manifest;
    for (final rel in neutralPluginManifestPaths.manifestCandidates()) {
      final manifestPath = _fs.pathContext.join(pluginDir, rel);
      if (!(await _fs.stat(manifestPath)).isFile) continue;
      try {
        final content = await _fs.readString(manifestPath);
        if (content != null) {
          manifest = (jsonDecode(content) as Map).cast<String, Object?>();
          break;
        }
      } catch (e) {
        throw PluginManifestException(manifestPath, cause: e);
      }
    }

    final name = (manifest?['name'] as String?)?.trim().isNotEmpty == true
        ? manifest!['name'] as String
        : _fs.pathContext.basename(pluginDir);
    final version = (manifest?['version'] as String?) ??
        (manifest == null ? '0.0.0+local' : '0.0.0');
    final description = (manifest?['description'] as String?) ?? '';
    final homepage = manifest?['homepage'] as String?;

    final capabilities = await _scanCapabilities(pluginDir);
    return ParsedPlugin(
      name: name,
      version: version,
      description: description,
      homepageUrl: homepage,
      capabilities: capabilities,
    );
  }

  Future<PluginCapabilities> _scanCapabilities(String dir) async {
    return PluginCapabilities(
      commands: await _scanMdDir(
        _fs.pathContext.join(dir, 'commands'),
        mapper: (name, fm) =>
            PluginCommand(name: name, description: fm['description']),
      ),
      agents: await _scanMdDir(
        _fs.pathContext.join(dir, 'agents'),
        mapper: (name, fm) =>
            PluginAgent(name: name, description: fm['description']),
      ),
      skills: await _scanSkillsDir(_fs.pathContext.join(dir, 'skills')),
      hooks: await _scanHooks(
          _fs.pathContext.join(dir, 'hooks', 'hooks.json')),
      mcpServers: await _scanMcp(_fs.pathContext.join(dir, '.mcp.json')),
    );
  }

  Future<List<T>> _scanMdDir<T>(
    String dir, {
    required T Function(String name, Map<String, String?> frontmatter)
        mapper,
  }) async {
    if (!(await _fs.stat(dir)).isDirectory) return const [];
    final out = <T>[];
    for (final entry in await _fs.listDir(dir)) {
      if (entry.isDirectory || !entry.name.endsWith('.md')) continue;
      final name =
          _fs.pathContext.basenameWithoutExtension(entry.name);
      final content =
          await _fs.readString(_fs.pathContext.join(dir, entry.name));
      final fm = _parseFrontmatter(content ?? '');
      out.add(mapper(name, fm));
    }
    return out;
  }

  Future<List<PluginSkillRef>> _scanSkillsDir(String dir) async {
    if (!(await _fs.stat(dir)).isDirectory) return const [];
    final out = <PluginSkillRef>[];
    for (final entry in await _fs.listDir(dir)) {
      if (!entry.isDirectory) continue;
      final skillPath =
          _fs.pathContext.join(dir, entry.name, 'SKILL.md');
      if (!(await _fs.stat(skillPath)).isFile) continue;
      final content = await _fs.readString(skillPath);
      final fm = _parseFrontmatter(content ?? '');
      out.add(PluginSkillRef(
        name: fm['name'] ?? entry.name,
        description: fm['description'],
      ));
    }
    return out;
  }

  Future<List<PluginHook>> _scanHooks(String path) async {
    if (!(await _fs.stat(path)).isFile) return const [];
    try {
      final content = await _fs.readString(path);
      if (content == null) return const [];
      final json = jsonDecode(content) as Map;
      final hooks = (json['hooks'] as Map?)
              ?.cast<String, Object?>() ??
          const {};
      final out = <PluginHook>[];
      hooks.forEach((event, value) {
        if (value is List) {
          for (final entry in value) {
            if (entry is Map) {
              out.add(PluginHook(
                event: event,
                matcher: (entry['matcher'] as String?) ?? '',
              ));
            }
          }
        }
      });
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<PluginMcpServer>> _scanMcp(String path) async {
    if (!(await _fs.stat(path)).isFile) return const [];
    try {
      final content = await _fs.readString(path);
      if (content == null) return const [];
      final json = jsonDecode(content) as Map;
      final servers = (json['mcpServers'] as Map?)
              ?.cast<String, Object?>() ??
          const {};
      return servers.entries.map((e) {
        final v =
            (e.value as Map?)?.cast<String, Object?>() ?? const {};
        return PluginMcpServer(
            name: e.key, type: (v['type'] as String?) ?? 'stdio');
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, String?> _parseFrontmatter(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return const {};
    final out = <String, String?>{};
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim() == '---') break;
      final idx = line.indexOf(':');
      if (idx < 0) continue;
      final k = line.substring(0, idx).trim();
      final v = line.substring(idx + 1).trim();
      out[k] = v.isEmpty ? null : v;
    }
    return out;
  }
}
