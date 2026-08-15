import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/skill/skill_fetch_service.dart';
import 'package:teampilot/services/skill/skill_repo_disk_cache_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/utils/async_keyed_coalescer.dart';

import '../../support/post_frame_test_harness.dart';

const _repo = SkillRepo(owner: 'acme', name: 'skills', branch: 'main');

class _CountingFetch extends SkillFetchService {
  int downloads = 0;
  int shaChecks = 0;
  String? remoteSha;
  String commitShaOnDownload = 'abc123';

  @override
  Future<String?> fetchBranchCommitSha(
    String owner,
    String name,
    String branch,
  ) async {
    shaChecks++;
    return remoteSha;
  }

  @override
  Future<({Map<String, Uint8List> entries, String branch, String commitSha})>
  downloadRepoEntries(
    SkillRepo repo, {
    Filesystem? fs,
    String? persistentGitPath,
  }) async {
    downloads++;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return (
      entries: {
        'demo/SKILL.md': Uint8List.fromList(
          utf8.encode('---\nname: demo\ndescription: d\n---\n'),
        ),
      },
      branch: repo.branch,
      commitSha: commitShaOnDownload,
    );
  }
}

Future<void> _plantSnapshot({
  required String commitSha,
  bool includeBin = false,
}) async {
  final fs = AppStorage.fs;
  final dir = fs.pathContext.join(
    AppStorage.paths.skillRepoCacheDir,
    SkillRepoDiskCacheService.repoKey(_repo),
  );
  final filesDir = fs.pathContext.join(dir, 'files');
  await fs.ensureDir(filesDir);
  await fs.ensureDir(fs.pathContext.join(filesDir, 'demo'));
  await fs.writeString(
    fs.pathContext.join(filesDir, 'demo', 'SKILL.md'),
    '---\nname: demo\ndescription: d\n---\n',
  );
  if (includeBin) {
    await fs.ensureDir(fs.pathContext.join(filesDir, 'bin'));
  }
  await fs.writeString(
    fs.pathContext.join(dir, 'skills.json'),
    jsonEncode([
      {
        'key': 'acme/skills:demo',
        'name': 'demo',
        'description': 'd',
        'directory': 'demo',
        'repoOwner': 'acme',
        'repoName': 'skills',
        'repoBranch': 'main',
      },
    ]),
  );
  final meta = SkillRepoCacheMeta(
    configuredBranch: 'main',
    resolvedBranch: 'main',
    commitSha: commitSha,
    syncedAtMs: 1,
  );
  await fs.writeString(
    fs.pathContext.join(dir, 'meta.json'),
    const JsonEncoder.withIndent('  ').convert(meta.toJson()),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('empty commitSha is not trusted when remote SHA unavailable', () async {
    await _plantSnapshot(commitSha: '');
    final fetch = _CountingFetch()..remoteSha = null;
    final cache = SkillRepoDiskCacheService(fetch: fetch);

    await cache.ensureSynced(_repo);

    expect(fetch.downloads, 1);
  });

  test('trusted snapshot reused when remote SHA unavailable', () async {
    await _plantSnapshot(commitSha: 'deadbeef');
    final fetch = _CountingFetch()..remoteSha = null;
    final cache = SkillRepoDiskCacheService(fetch: fetch);

    final result = await cache.ensureSynced(_repo);

    expect(fetch.downloads, 0);
    expect(result.updated, isFalse);
    expect(result.skills, isNotEmpty);
  });

  test('parallel ensureSynced on separate instances coalesces download', () async {
    final fetch = _CountingFetch();
    final coalescer = AsyncKeyedCoalescer();
    final a = SkillRepoDiskCacheService(fetch: fetch, coalescer: coalescer);
    final b = SkillRepoDiskCacheService(fetch: fetch, coalescer: coalescer);

    await Future.wait([a.ensureSynced(_repo), b.ensureSynced(_repo)]);

    expect(fetch.downloads, 1);
  });

  test('missing requiredRelativePaths forces download', () async {
    await _plantSnapshot(commitSha: 'deadbeef', includeBin: false);
    final fetch = _CountingFetch()..remoteSha = null;
    final cache = SkillRepoDiskCacheService(fetch: fetch);

    await cache.ensureSynced(_repo, requiredRelativePaths: const ['bin']);

    expect(fetch.downloads, 1);
  });

  test('maxStaleness skips network when cache is fresh', () async {
    final fs = AppStorage.fs;
    await _plantSnapshot(commitSha: 'deadbeef');
    final metaPath = fs.pathContext.join(
      AppStorage.paths.skillRepoCacheDir,
      SkillRepoDiskCacheService.repoKey(_repo),
      'meta.json',
    );
    final meta = SkillRepoCacheMeta(
      configuredBranch: 'main',
      resolvedBranch: 'main',
      commitSha: 'deadbeef',
      syncedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await fs.writeString(
      metaPath,
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );

    final fetch = _CountingFetch()..remoteSha = 'deadbeef';
    final cache = SkillRepoDiskCacheService(fetch: fetch);

    final result = await cache.ensureSynced(
      _repo,
      maxStaleness: const Duration(hours: 24),
    );

    expect(fetch.downloads, 0);
    expect(fetch.shaChecks, 0);
    expect(result.updated, isFalse);
    expect(result.skills, isNotEmpty);
  });

  test('maxStaleness still checks remote when cache is stale', () async {
    await _plantSnapshot(commitSha: 'deadbeef');
    final fetch = _CountingFetch()..remoteSha = 'deadbeef';
    final cache = SkillRepoDiskCacheService(fetch: fetch);

    final result = await cache.ensureSynced(
      _repo,
      maxStaleness: const Duration(hours: 24),
    );

    expect(fetch.shaChecks, 1);
    expect(fetch.downloads, 0);
    expect(result.updated, isFalse);
  });
}
