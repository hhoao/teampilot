import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  late Directory tmp; // from dart:io
  late AppPaths paths;
  late SkillRegistryConfigService service;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('skill-registry-cfg-');
    paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    service = SkillRegistryConfigService(
      teampilotRoot: paths.basePath,
      legacySkillsMpKeyReader: () async => 'legacy-token',
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('load returns defaults when no files exist', () async {
    final cfg = await service.load();
    expect(cfg.byId('skillsSh'), isNotNull);
    expect(cfg.byId('skillsMp'), isNotNull);
    expect(cfg.byId('skillsMp')!.apiToken, isNull);
  });

  test('migrates legacy repos.json git repos + skillsMp key once', () async {
    final oldPath = AppPaths.skillReposConfigPathForTeampilotRoot(paths.basePath);
    await AppStorage.fs.writeString(oldPath, const JsonEncoder.withIndent('  ').convert({
      'repos': [
        {'owner': 'vercel', 'name': 'ai', 'branch': 'main', 'enabled': true},
      ],
    }));

    final cfg = await service.load();
    final git = cfg.sources.where((s) => s.kind == SkillRegistryKind.gitRepo);
    expect(git.length, 1);
    expect(git.first.gitOwner, 'vercel');
    expect(cfg.byId('skillsMp')!.apiToken, 'legacy-token');

    // second load reads registries.json; migration not repeated
    final again = await service.load();
    expect(again.sources.length, cfg.sources.length);
  });

  test('save + load round-trip', () async {
    final cfg = SkillRegistriesConfig.defaults().toJson();
    final config = SkillRegistriesConfig.fromJson(cfg);
    await service.save(config);
    final loaded = await service.load();
    expect(loaded.sources.length, config.sources.length);
  });

  test('corrupt registries.json falls back to defaults', () async {
    final path = AppPaths.skillRegistriesConfigPathForTeampilotRoot(paths.basePath);
    await AppStorage.fs.writeString(path, '{not json');
    final cfg = await service.load();
    expect(cfg.byId('skillsSh'), isNotNull);
  });
}
