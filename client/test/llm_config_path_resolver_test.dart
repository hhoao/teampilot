import 'package:flashskyai_client/services/llm_config_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveLlmConfigPath', () {
    group('user override', () {
      test('absolute override is used as-is', () {
        final r = resolveLlmConfigPath(
          userOverride: '/etc/flashskyai/llm_config.json',
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
          fileExistsSync: (_) => true,
        );
        expect(r.path, '/etc/flashskyai/llm_config.json');
        expect(r.source, LlmConfigPathSource.userOverride);
      });

      test('expands ~/ to home directory', () {
        final r = resolveLlmConfigPath(
          userOverride: '~/llm/llm_config.json',
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: null,
          fileExistsSync: (_) => false,
        );
        expect(r.path, '/home/test/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.userOverride);
      });

      test('relative override resolves against currentDirectory', () {
        final r = resolveLlmConfigPath(
          userOverride: 'cfg/llm.json',
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: null,
          fileExistsSync: (_) => false,
        );
        expect(r.path, '/cwd/cfg/llm.json');
        expect(r.source, LlmConfigPathSource.userOverride);
      });

      test('whitespace override is treated as empty', () {
        final r = resolveLlmConfigPath(
          userOverride: '   ',
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
          fileExistsSync: (path) =>
              path == '/opt/flashskyai/llm/llm_config.json',
        );
        expect(r.source, LlmConfigPathSource.defaultPath);
      });
    });

    group('default path resolution', () {
      test('uses CLI install dir when that file exists', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
          fileExistsSync: (path) =>
              path == '/opt/flashskyai/llm/llm_config.json',
        );
        expect(r.path, '/opt/flashskyai/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });

      test('falls back to ~/.flashskyai when CLI file is missing', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
          fileExistsSync: (path) =>
              path == '/home/test/.flashskyai/llm/llm_config.json',
        );
        expect(r.path, '/home/test/.flashskyai/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });

      test('returns CLI candidate when neither file exists but CLI is known',
          () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
          fileExistsSync: (_) => false,
        );
        // Prefer CLI candidate so saves land where CLI looks first.
        expect(r.path, '/opt/flashskyai/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });

      test('returns home candidate when CLI is unknown and no file exists', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: null,
          fileExistsSync: (_) => false,
        );
        expect(r.path, '/home/test/.flashskyai/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });

      test('matches the user real-world setup (CLI under DingDing/dist)', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/anywhere',
          homeDirectory: '/home/hhoa',
          cliExecutablePath:
              '/home/hhoa/Downloads/DingDing/flashshkyai/dist/flashskyai',
          fileExistsSync: (path) =>
              path ==
              '/home/hhoa/Downloads/DingDing/flashshkyai/llm/llm_config.json',
        );
        expect(r.path,
            '/home/hhoa/Downloads/DingDing/flashshkyai/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });
    });
  });
}
