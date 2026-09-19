import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/remote_cli_path_cache.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  const filePath = '/app-data/remote-cli-paths.json';

  InMemoryFilesystem newFs() => InMemoryFilesystem();

  RemoteCliPathCache newCache(InMemoryFilesystem fs) =>
      RemoteCliPathCache(fs: fs, filePath: filePath);

  test('save then load round-trips per profile', () async {
    final fs = newFs();
    final cache = newCache(fs);

    await cache.save('p1', const {CliTool.claude: '/remote/bin/claude'});
    await cache.save('p2', const {
      CliTool.codex: '/remote/bin/codex',
      CliTool.cursor: '/usr/bin/cu',
    });

    expect(await cache.load('p1'), const {
      CliTool.claude: '/remote/bin/claude',
    });
    expect(await cache.load('p2'), const {
      CliTool.codex: '/remote/bin/codex',
      CliTool.cursor: '/usr/bin/cu',
    });
  });

  test('load for a missing profile returns an empty map', () async {
    final cache = newCache(newFs());

    expect(await cache.load('unknown'), isEmpty);
  });

  test('load on corrupt JSON returns an empty map without throwing', () async {
    final fs = newFs();
    await fs.writeString(filePath, '{not json');
    final cache = newCache(fs);

    expect(await cache.load('p1'), isEmpty);
  });

  test('load skips entries with unknown CLI values', () async {
    final fs = newFs();
    await fs.writeString(
      filePath,
      jsonEncode({
        'p1': {'claude': '/remote/bin/claude', 'made-up-cli': '/x'},
        'p2': 'not-a-map',
      }),
    );
    final cache = newCache(fs);

    expect(await cache.load('p1'), const {
      CliTool.claude: '/remote/bin/claude',
    });
    expect(await cache.load('p2'), isEmpty);
  });

  test('invalidate removes only the target profile entry', () async {
    final fs = newFs();
    final cache = newCache(fs);

    await cache.save('p1', const {CliTool.claude: '/remote/bin/claude'});
    await cache.save('p2', const {CliTool.codex: '/remote/bin/codex'});

    await cache.invalidate('p1');

    expect(await cache.load('p1'), isEmpty);
    expect(await cache.load('p2'), const {CliTool.codex: '/remote/bin/codex'});
  });

  test('save overwrites the previous entry for a profile', () async {
    final fs = newFs();
    final cache = newCache(fs);

    await cache.save('p1', const {CliTool.claude: '/old/claude'});
    await cache.save('p1', const {CliTool.claude: '/new/claude'});

    expect(await cache.load('p1'), const {CliTool.claude: '/new/claude'});
  });

  test('invalidate on a missing file is a no-op', () async {
    final cache = newCache(newFs());

    await cache.invalidate('p1');

    expect(await cache.load('p1'), isEmpty);
  });

  test('save writes JSON keyed by profile id and CLI value', () async {
    final fs = newFs();
    final cache = newCache(fs);

    await cache.save('p1', const {CliTool.claude: '/remote/bin/claude'});

    final raw = await fs.readString(filePath);
    expect(jsonDecode(raw!), {
      'p1': {'claude': '/remote/bin/claude'},
    });
  });
}
