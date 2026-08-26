import 'package:flutter_test/flutter_test.dart';

import 'cli_store_env.dart';

void main() {
  group('sanitizeCliStoreEnvironment', () {
    test('strips every TeamPilot-injected CLI store redirect', () {
      final env = sanitizeCliStoreEnvironment(const {
        'OPENCODE_DB': '/session/runtime/opencode/opencode.db',
        'OPENCODE_CONFIG_DIR': '/session/runtime/opencode',
        'XDG_DATA_HOME': '/session/xdg/data',
        'CLAUDE_CONFIG_DIR': '/session/runtime/claude',
        'TEAMPILOT_CLAUDE_SETTINGS_FILE': '/session/settings.json',
        'CODEX_HOME': '/session/runtime/codex',
        'CURSOR_CONFIG_DIR': '/session/runtime/cursor',
        'FLASHSKYAI_CONFIG_DIR': '/session/runtime/flashskyai',
        'FLASHSKYAI_SESSION_HOME_DIR': '/session/home',
        'LLM_CONFIG_PATH': '/session/llm-config.json',
      });

      expect(env, isEmpty);
    });

    test('keeps unrelated and user-level environment', () {
      const env = {
        'HOME': '/home/dev',
        'PATH': '/usr/bin',
        'TERM': 'xterm-256color',
        'LANG': 'zh_CN.UTF-8',
        'OPENCODE_DB': '/session/runtime/opencode/opencode.db',
        'CODEX_HOME': '/session/runtime/codex',
      };

      final sanitized = sanitizeCliStoreEnvironment(env);

      expect(sanitized, {
        'HOME': '/home/dev',
        'PATH': '/usr/bin',
        'TERM': 'xterm-256color',
        'LANG': 'zh_CN.UTF-8',
      });
    });

    test('does not mutate the input map', () {
      final env = {'HOME': '/home/dev', 'OPENCODE_DB': '/live/opencode.db'};

      sanitizeCliStoreEnvironment(env);

      expect(env.containsKey('OPENCODE_DB'), isTrue);
    });
  });
}
