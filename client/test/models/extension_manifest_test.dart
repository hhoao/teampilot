import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/extension_manifest.dart';

void main() {
  group('ExtensionManifest.fromJson', () {
    test('parses identity, detect, and a settings-hook effect', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'rtk',
        'name': 'RTK (Rust Token Killer)',
        'version': '0.x',
        'homepage': 'https://github.com/rtk-ai/rtk',
        'detect': {
          'executable': 'rtk',
          'versionArgs': ['--version'],
          'minVersion': '0.23.0',
          'requires': ['jq'],
        },
        'effects': [
          {
            'kind': 'settings-hook',
            'appliesTo': ['claude', 'flashskyai'],
            'event': 'PreToolUse',
            'matcher': 'Bash',
            'scriptAsset': 'rtk-rewrite',
            'marker': 'rtk-rewrite',
          },
        ],
      });

      expect(manifest.id, 'rtk');
      expect(manifest.name, 'RTK (Rust Token Killer)');
      expect(manifest.detect.executable, 'rtk');
      expect(manifest.detect.versionArgs, ['--version']);
      expect(manifest.detect.minVersion, '0.23.0');
      expect(manifest.detect.requires, ['jq']);

      expect(manifest.effects, hasLength(1));
      final effect = manifest.effects.single;
      expect(effect.kind, 'settings-hook');
      expect(effect.appliesTo, ['claude', 'flashskyai']);
      expect(effect.hookEvent, 'PreToolUse');
      expect(effect.hookMatcher, 'Bash');
      expect(effect.scriptAsset, 'rtk-rewrite');
      expect(effect.marker, 'rtk-rewrite');
    });

    test('applies defaults when optional fields are missing', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'x',
        'name': 'X',
        'detect': {'executable': 'x'},
      });

      expect(manifest.version, '');
      expect(manifest.detect.versionArgs, ['--version']);
      expect(manifest.detect.minVersion, isNull);
      expect(manifest.detect.requires, isEmpty);
      expect(manifest.effects, isEmpty);
      expect(manifest.acquire, isNull);
    });

    test('parses acquire spec when present', () {
      final manifest = ExtensionManifest.fromJson({
        'id': 'rtk',
        'name': 'RTK',
        'acquire': {
          'kind': 'cargo',
          'package': 'rtk',
          'binary': 'rtk',
          'alternatives': ['brew:rtk'],
        },
        'detect': {'executable': 'rtk'},
      });

      expect(manifest.acquire, isNotNull);
      expect(manifest.acquire!.kind, 'cargo');
      expect(manifest.acquire!.package, 'rtk');
      expect(manifest.acquire!.alternatives, ['brew:rtk']);
    });
  });
}
