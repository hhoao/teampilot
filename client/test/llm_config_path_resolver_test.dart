import 'package:teampilot/services/llm_config_path_resolver.dart';
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
        );
        expect(r.path, '/cwd/cfg/llm.json');
        expect(r.source, LlmConfigPathSource.userOverride);
      });

      test('whitespace override falls through to default', () {
        final r = resolveLlmConfigPath(
          userOverride: '   ',
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
        );
        expect(r.path, '/opt/flashskyai/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });
    });

    group('default path', () {
      test('uses CLI install dir when CLI is known', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
        );
        expect(r.path, '/opt/flashskyai/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });

      test('returns empty path when CLI is unknown', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: null,
        );
        expect(r.path, '');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });

      test('matches the user real-world setup (CLI under DingDing/dist)', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/anywhere',
          homeDirectory: '/home/hhoa',
          cliExecutablePath:
              '/home/hhoa/Downloads/DingDing/flashshkyai/dist/flashskyai',
        );
        expect(r.path,
            '/home/hhoa/Downloads/DingDing/flashshkyai/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });
    });
  });
}
