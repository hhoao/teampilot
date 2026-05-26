import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/plugin_external_source.dart';

void main() {
  test('parses git-subdir source object', () {
    final spec = PluginExternalSource.fromMarketplaceObject({
      'source': 'git-subdir',
      'url': 'https://github.com/42Crunch-AI/claude-plugins.git',
      'path': 'plugins/api-security-testing',
      'ref': 'v1.5.5',
      'sha': 'abc123',
    });
    expect(spec, isNotNull);
    expect(spec!.cloneUrl, contains('42Crunch-AI'));
    expect(spec.subPath, 'plugins/api-security-testing');
    expect(spec.ref, 'v1.5.5');
    expect(spec.sha, 'abc123');
  });

  test('parses github source object', () {
    final spec = PluginExternalSource.fromMarketplaceObject({
      'source': 'github',
      'repo': 'fullstorydev/fullstory-skills',
      'commit': '1ec5865e7ab1449f9a0859d164c4b6a8c53b6e2f',
    });
    expect(spec, isNotNull);
    expect(spec!.cloneUrl, 'https://github.com/fullstorydev/fullstory-skills.git');
    expect(spec.sha, '1ec5865e7ab1449f9a0859d164c4b6a8c53b6e2f');
  });
}
