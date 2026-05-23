import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/plugin.dart';
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
  Future<ParsedPlugin> parseDirectory(String pluginDir) async {
    final manifestPath = p.join(pluginDir, '.claude-plugin', 'plugin.json');
    Map<String, Object?>? manifest;
    final manifestFile = File(manifestPath);
    if (manifestFile.existsSync()) {
      try {
        manifest = (jsonDecode(manifestFile.readAsStringSync()) as Map).cast<String, Object?>();
      } catch (e) {
        throw PluginManifestException(manifestPath, cause: e);
      }
    }

    final name = (manifest?['name'] as String?)?.trim().isNotEmpty == true
        ? manifest!['name'] as String
        : p.basename(pluginDir);
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
      commands: _scanMdDir(p.join(dir, 'commands'),
          mapper: (name, fm) => PluginCommand(name: name, description: fm['description'])),
      agents: _scanMdDir(p.join(dir, 'agents'),
          mapper: (name, fm) => PluginAgent(name: name, description: fm['description'])),
      skills: _scanSkillsDir(p.join(dir, 'skills')),
      hooks: _scanHooks(p.join(dir, 'hooks', 'hooks.json')),
      mcpServers: _scanMcp(p.join(dir, '.mcp.json')),
    );
  }

  List<T> _scanMdDir<T>(
    String dir, {
    required T Function(String name, Map<String, String?> frontmatter) mapper,
  }) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final out = <T>[];
    for (final entry in d.listSync()) {
      if (entry is! File || !entry.path.endsWith('.md')) continue;
      final name = p.basenameWithoutExtension(entry.path);
      final fm = _parseFrontmatter(entry.readAsStringSync());
      out.add(mapper(name, fm));
    }
    return out;
  }

  List<PluginSkillRef> _scanSkillsDir(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final out = <PluginSkillRef>[];
    for (final entry in d.listSync()) {
      if (entry is! Directory) continue;
      final skillMd = File(p.join(entry.path, 'SKILL.md'));
      if (!skillMd.existsSync()) continue;
      final fm = _parseFrontmatter(skillMd.readAsStringSync());
      out.add(PluginSkillRef(
        name: fm['name'] ?? p.basename(entry.path),
        description: fm['description'],
      ));
    }
    return out;
  }

  List<PluginHook> _scanHooks(String path) {
    final f = File(path);
    if (!f.existsSync()) return const [];
    try {
      final json = jsonDecode(f.readAsStringSync()) as Map;
      final hooks = (json['hooks'] as Map?)?.cast<String, Object?>() ?? const {};
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

  List<PluginMcpServer> _scanMcp(String path) {
    final f = File(path);
    if (!f.existsSync()) return const [];
    try {
      final json = jsonDecode(f.readAsStringSync()) as Map;
      final servers = (json['mcpServers'] as Map?)?.cast<String, Object?>() ?? const {};
      return servers.entries.map((e) {
        final v = (e.value as Map?)?.cast<String, Object?>() ?? const {};
        return PluginMcpServer(name: e.key, type: (v['type'] as String?) ?? 'stdio');
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
