import 'dart:io';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/plugin_exceptions.dart';
import 'package:teampilot/services/plugin_manifest_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('plugin-manifest-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('parses plugin.json with version and description', () async {
    final dir = Directory(p.join(tmp.path, 'my-plugin'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'plugin.json'))
        .writeAsStringSync('{"name":"my-plugin","version":"1.2.3","description":"hi"}');

    final svc = PluginManifestService();
    final result = await svc.parseDirectory(dir.path);
    expect(result.name, 'my-plugin');
    expect(result.version, '1.2.3');
    expect(result.description, 'hi');
  });

  test('falls back to directory name when plugin.json missing', () async {
    final dir = Directory(p.join(tmp.path, 'no-manifest'))..createSync();
    Directory(p.join(dir.path, 'commands')).createSync();
    File(p.join(dir.path, 'commands', 'deploy.md'))
        .writeAsStringSync('---\ndescription: Deploy current branch\n---\n# Deploy');

    final svc = PluginManifestService();
    final result = await svc.parseDirectory(dir.path);
    expect(result.name, 'no-manifest');
    expect(result.capabilities.commands.first.name, 'deploy');
    expect(result.capabilities.commands.first.description, 'Deploy current branch');
  });

  test('parses hooks.json and .mcp.json', () async {
    final dir = Directory(p.join(tmp.path, 'p'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'plugin.json'))
        .writeAsStringSync('{"name":"p","version":"1.0.0"}');
    Directory(p.join(dir.path, 'hooks')).createSync();
    File(p.join(dir.path, 'hooks', 'hooks.json')).writeAsStringSync(
      '{"hooks":{"PreCommit":[{"matcher":"*.dart"}]}}');
    File(p.join(dir.path, '.mcp.json')).writeAsStringSync(
      '{"mcpServers":{"github":{"type":"stdio","command":"gh"}}}');

    final svc = PluginManifestService();
    final result = await svc.parseDirectory(dir.path);
    expect(result.capabilities.hooks.first.event, 'PreCommit');
    expect(result.capabilities.hooks.first.matcher, '*.dart');
    expect(result.capabilities.mcpServers.first.name, 'github');
    expect(result.capabilities.mcpServers.first.type, 'stdio');
  });

  test('throws PluginManifestException for invalid JSON', () async {
    final dir = Directory(p.join(tmp.path, 'bad'))..createSync();
    Directory(p.join(dir.path, '.claude-plugin')).createSync();
    File(p.join(dir.path, '.claude-plugin', 'plugin.json'))
        .writeAsStringSync('{not json');
    final svc = PluginManifestService();
    expect(() => svc.parseDirectory(dir.path), throwsA(isA<PluginManifestException>()));
  });
}
