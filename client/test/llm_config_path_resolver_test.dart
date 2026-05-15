import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/llm_config_path_resolver.dart';

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
        expect(r.path, p.normalize('/etc/flashskyai/llm_config.json'));
        expect(r.source, LlmConfigPathSource.userOverride);
      });

      test('expands ~/ to home directory', () {
        final r = resolveLlmConfigPath(
          userOverride: '~/llm/llm_config.json',
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: null,
        );
        expect(r.path, p.normalize(p.join('/home/test', 'llm/llm_config.json')));
        expect(r.source, LlmConfigPathSource.userOverride);
      });

      test('relative override resolves against currentDirectory', () {
        final r = resolveLlmConfigPath(
          userOverride: 'cfg/llm.json',
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: null,
        );
        expect(r.path, p.normalize(p.absolute(p.join('/cwd', 'cfg/llm.json'))));
        expect(r.source, LlmConfigPathSource.userOverride);
      });

      test('whitespace override falls through to default', () {
        final r = resolveLlmConfigPath(
          userOverride: '   ',
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: '/opt/flashskyai/dist/flashskyai',
        );
        final cli = '/opt/flashskyai/dist/flashskyai';
        expect(
          r.path,
          p.normalize(
            p.join(
              p.dirname(p.absolute(cli)),
              '..',
              'llm',
              'llm_config.json',
            ),
          ),
        );
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
        final cli = '/opt/flashskyai/dist/flashskyai';
        expect(
          r.path,
          p.normalize(
            p.join(
              p.dirname(p.absolute(cli)),
              '..',
              'llm',
              'llm_config.json',
            ),
          ),
        );
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
        const cli =
            '/home/hhoa/Downloads/DingDing/flashshkyai/dist/flashskyai';
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/anywhere',
          homeDirectory: '/home/hhoa',
          cliExecutablePath: cli,
        );
        expect(
          r.path,
          p.normalize(
            p.join(
              p.dirname(p.absolute(cli)),
              '..',
              'llm',
              'llm_config.json',
            ),
          ),
        );
        expect(r.source, LlmConfigPathSource.defaultPath);
      });

      test('WSL launch string uses Linux sidecar layout (POSIX path)', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: r'C:\proj',
          homeDirectory: r'C:\Users\x',
          cliExecutablePath:
              r'wsl.exe /home/hhoa/flashskai-ubuntu-wsl/dist/flashskyai',
        );
        expect(
          r.path,
          '/home/hhoa/flashskai-ubuntu-wsl/llm/llm_config.json',
        );
        expect(r.source, LlmConfigPathSource.defaultPath);
      });

      test('wsl without .exe prefix', () {
        final r = resolveLlmConfigPath(
          userOverride: null,
          currentDirectory: '/cwd',
          homeDirectory: '/home/test',
          cliExecutablePath: 'wsl /opt/foo/dist/flashskyai',
        );
        expect(r.path, '/opt/foo/llm/llm_config.json');
        expect(r.source, LlmConfigPathSource.defaultPath);
      });
    });
  });
}
