# TeamPilot resources submodule Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

Goal: Move Team Hub, Expert Hub, and Skill Pack catalogs into the hhoao/teampilot-resources Git submodule and make runtime acquisition use its indexed Raw registry.

Architecture: resources/ is a source-maintenance-only Git submodule. Team and Expert keep their indexed registry sources; Skill Pack gains an indexed lazy source. The client never scans resources/ at runtime. Built-in client resources remain immediately available and win on ID collision.

Tech Stack: Git submodules, GitHub Raw/Contents APIs, Dart, Flutter, http, injected Filesystem, flutter_test, and existing catalog error/cache conventions.

## Global Constraints

- Do not add backward compatibility: do not resolve, alias, migrate, or fetch old hhoao/teampilot/... remote keys.
- The Flutter application must never read or recursively scan resources/ at runtime.
- Use injected Filesystem and AppStorage paths for catalog cache I/O.
- Preserve built-in teampilot/builtin/* resources; built-ins win over remote entries.
- Keep local experts, cloned teams, provider catalogs, skills.sh, and SkillsMP behavior unchanged.
- Preserve unrelated dirty-worktree changes; stage only feature files in each commit.
- Use appLogger for diagnostics and sanitized catalog failures for UI-facing errors.
- Before claiming completion run:
    cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart

---

### Task 1: Initialize and populate the resources submodule

Files:
- Create/modify .gitmodules
- Create resources/ Git submodule pointing to https://github.com/hhoao/teampilot-resources.git
- Move team-hub/, member-hub/, and skill-packs/ into the submodule
- Delete those three directories from the parent repository

Interfaces:
- Produces the remote catalog tree consumed by Tasks 2–4.
- Produces a parent gitlink at resources/; no Dart code reads this path at runtime.

- [ ] Step 1: Verify the empty remote and preserve the dirty worktree

Run:
    git status --short
    git ls-remote https://github.com/hhoao/teampilot-resources.git HEAD refs/heads/main
    curl -L --fail --silent https://api.github.com/repos/hhoao/teampilot-resources | sed -n '1,80p'

Expected: existing unrelated changes remain untouched; the public repository exists and has no main commit.

- [ ] Step 2: Prepare the resource repository

Clone the empty remote into a temporary directory, copy the three existing catalog directories into its root, and create a root README. The resource repo must contain only catalog trees and documentation:

    resource_tmp="$(mktemp -d /tmp/teampilot-resources.XXXXXX)"
    git clone https://github.com/hhoao/teampilot-resources.git "$resource_tmp"
    cp -R team-hub member-hub skill-packs "$resource_tmp"/

The root README must state that consumers fetch index.json first and then only listed manifests, and list team-hub, member-hub, and skill-packs. Do not copy Flutter source.

- [ ] Step 3: Update migrated manifest references

Replace resource-owned Expert references in the copied team manifests:

    rg -n 'hhoao/teampilot/(team-hub|member-hub)' "$resource_tmp"
    sed -i 's#hhoao/teampilot/member-hub/#hhoao/teampilot-resources/member-hub/#g' \
      "$resource_tmp"/team-hub/teams/*/team.json

Validate every resource JSON file:

    find "$resource_tmp" -name '*.json' -print0 |
      xargs -0 -n1 ruby -e 'require "json"; JSON.parse(File.read(ARGV.fetch(0)))'

Expected: all JSON parses and no old remote prefix remains in resource manifests.

- [ ] Step 4: Commit and push the resource repository

    git -C "$resource_tmp" add README.md team-hub member-hub skill-packs
    git -C "$resource_tmp" commit -m "chore: move TeamPilot resource catalogs"
    git -C "$resource_tmp" branch -M main
    git -C "$resource_tmp" push -u origin main
    git ls-remote https://github.com/hhoao/teampilot-resources.git refs/heads/main

Expected: the pushed main commit exists. If authentication fails, stop before recording an unfetchable parent gitlink and report the exact error.

- [ ] Step 5: Add the populated repository as a submodule

    git submodule add -b main https://github.com/hhoao/teampilot-resources.git resources
    git rm -r team-hub member-hub skill-packs
    git -C resources checkout --detach main
    git submodule status

Expected: resources is a valid gitlink and the parent index has no root-level catalog files.

- [ ] Step 6: Commit the repository-boundary change

    git add .gitmodules resources
    git commit -m "chore: move catalogs to resources submodule"

Expected: this commit contains the submodule pointer and the intentional removal of the three old directories.

### Task 2: Point Team and Expert Hub at the new registry

Files:
- Modify client/lib/services/team_hub/team_hub_source.dart lines 53–59
- Modify client/lib/services/expert_hub/expert_hub_source.dart lines 53–59
- Modify client/lib/cubits/launch_profile_cubit.dart:114-116 comment
- Modify existing Team Hub, Expert Hub, and Hub publish tests containing old expected keys

Interfaces:
- Produces the existing registry contracts with owner hhoao, name teampilot-resources, branch main, and roots team-hub/member-hub.
- Produces only new-prefix public keys.

- [ ] Step 1: Add failing default-registry assertions

Add to the existing source tests:

    test('default registries point to teampilot-resources', () {
      expect(kDefaultTeamHubRegistry.fullName, 'hhoao/teampilot-resources');
      expect(kDefaultTeamHubRegistry.catalogPrefix,
          'hhoao/teampilot-resources/team-hub');
      expect(kDefaultExpertHubRegistry.fullName, 'hhoao/teampilot-resources');
      expect(kDefaultExpertHubRegistry.catalogPrefix,
          'hhoao/teampilot-resources/member-hub');
    });

Run:
    cd client && flutter test test/services/team_hub test/services/expert_hub

Expected: FAIL because the constants still use teampilot.

- [ ] Step 2: Change the two default registry constants

Use these values and update comments to say resources repository:

    const kDefaultTeamHubRegistry = TeamHubRegistry(
      owner: 'hhoao',
      name: 'teampilot-resources',
      branch: 'main',
      rootPath: 'team-hub',
    );

    const kDefaultExpertHubRegistry = ExpertHubRegistry(
      owner: 'hhoao',
      name: 'teampilot-resources',
      branch: 'main',
      rootPath: 'member-hub',
    );

Do not add aliases or fallback registries.

- [ ] Step 3: Update active expected URLs and keys

Replace active test/fixture values with:

    hhoao/teampilot-resources/team-hub/...
    hhoao/teampilot-resources/member-hub/...

The publish service already uses the default constants; verify publish tests expect the new repository fullName and retain team-hub/member-hub Contents paths.

Run:
    rg -n 'hhoao/teampilot/(team-hub|member-hub)' client/lib client/test

Expected: no old remote prefix in executable client code or active tests.

- [ ] Step 4: Run and commit Hub migration

    cd client && flutter test \
      test/services/team_hub \
      test/services/expert_hub \
      test/pages/hub_publish \
      test/services/hub_publish
    cd ..
    git add client/lib/services/team_hub client/lib/services/expert_hub \
      client/lib/cubits/launch_profile_cubit.dart \
      client/test/services/team_hub client/test/services/expert_hub \
      client/test/pages/hub_publish client/test/services/hub_publish
    git commit -m "feat(catalog): use dedicated resources repository for hubs"

Expected: all focused tests pass before commit.

### Task 3: Add indexed remote Skill Pack source and cache path

Files:
- Create client/lib/services/skill/skill_pack_source.dart
- Create client/lib/services/skill/git_registry_skill_pack_source.dart
- Modify client/lib/services/storage/app_storage.dart around existing Skill Pack paths
- Create client/test/services/skill/git_registry_skill_pack_source_test.dart
- Create or modify client/test/services/storage/skill_pack_paths_test.dart

Interfaces:
- SkillPackRegistryConfig has owner, name, branch, rootPath, fullName, catalogPrefix, rawUri, and repoPath.
- SkillPackSource has Future<List<SkillPack>> fetchPacks({bool forceRefresh = false}).
- GitRegistrySkillPackSource accepts an injected fetcher, Filesystem, and cacheDirOverride.

- [ ] Step 1: Add failing source and path tests

Use the repository InMemoryFilesystem test helper and add:

    test('default registry points to resources repo', () {
      expect(kDefaultSkillPackRegistry.fullName, 'hhoao/teampilot-resources');
      expect(
        kDefaultSkillPackRegistry.rawUri('skill-packs/index.json').toString(),
        'https://raw.githubusercontent.com/hhoao/teampilot-resources/main/skill-packs/index.json',
      );
    });

    test('loads only indexed pack manifests and caches parsed packs', () async {
      final calls = <Uri>[];
      final fs = InMemoryFilesystem();
      final source = GitRegistrySkillPackSource(
        fs: fs,
        cacheDirOverride: '/cache',
        fetch: (uri) async {
          calls.add(uri);
          if (uri.path.endsWith('/index.json')) {
            return '{"packs":["gstack"]}';
          }
          return '{"id":"garrytan/gstack","name":"gstack","install":[{"FROM":"garrytan/gstack@main"}]}';
        },
      );

      final packs = await source.fetchPacks();
      expect(packs.single.id, 'garrytan/gstack');
      expect(calls.any((uri) => uri.path.endsWith('/skill-packs/gstack/pack.json')), isTrue);
      expect(await source.fetchPacks(), packs);
    });

Run the new tests. Expected: compilation failure because the source and path accessors do not exist.

- [ ] Step 2: Implement the source value object and interface

Use the same path normalization as TeamHubRegistry and define:

    const kDefaultSkillPackRegistry = SkillPackRegistryConfig(
      owner: 'hhoao',
      name: 'teampilot-resources',
      branch: 'main',
      rootPath: 'skill-packs',
    );

The source must use the Raw URL under skill-packs and must not inspect a local checkout.

- [ ] Step 3: Implement indexed fetch and cache

Implement fetchPacks with this sequence:

    if (!forceRefresh && _memory != null) return _memory!;
    if (!forceRefresh) {
      final cached = await _readCache();
      if (cached != null) {
        _memory = cached;
        return cached;
      }
    }
    final indexRaw = await _fetch(registry.rawUri('index.json'));
    if (indexRaw == null) {
      _lastFailure = CatalogSourceFailure(
        sourceId: 'skill-pack-registry',
        sourceLabel: registry.fullName,
        message: CatalogErrorSanitizer.sanitize('Registry index unavailable'),
      );
      _memory = const [];
      await _writeCache(const []);
      return const [];
    }
    final slugs = _parseSlugs(indexRaw);
    final packs = <SkillPack>[];
    for (final slug in slugs) {
      final raw = await _fetch(registry.rawUri('$slug/pack.json'));
      if (raw == null) continue;
      try {
        packs.add(SkillPack.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>(),
        ));
      } on FormatException catch (error) {
        appLogger.w('[skill-packs] bad pack.json for $slug: $error');
      }
    }

Parse the existing string-slug index shape, sanitize index failures, skip malformed individual packs, and write parsed packs as JSON to skill-packs/cache/<owner>-<name>/packs.json. Add tests for unavailable index, malformed pack, and valid-pack isolation.

- [ ] Step 4: Add AppPaths accessors

Add:

    static String skillPackCatalogCacheDirForTeampilotRoot(String teampilotRoot) =>
        _pathUnderTeampilotRoot(teampilotRoot, 'skill-packs/cache');

and:

    String get skillPackCatalogCacheDir =>
        skillPackCatalogCacheDirForTeampilotRoot(basePath);

Test the exact path /data/com.hhoa.teampilot/skill-packs/cache.

- [ ] Step 5: Run source/path tests and commit

    cd client && flutter test \
      test/services/skill/git_registry_skill_pack_source_test.dart \
      test/services/storage/skill_pack_paths_test.dart
    cd ..
    git add client/lib/services/skill/skill_pack_source.dart \
      client/lib/services/skill/git_registry_skill_pack_source.dart \
      client/lib/services/storage/app_storage.dart \
      client/test/services/skill/git_registry_skill_pack_source_test.dart \
      client/test/services/storage/skill_pack_paths_test.dart
    git commit -m "feat(skill-packs): add indexed resources registry source"

Expected: PASS before commit.

### Task 4: Lazily merge remote Skill Packs into acquisition

Files:
- Modify client/lib/services/skill/skill_pack_registry.dart
- Modify client/lib/services/skill/skill_acquisition_engine.dart around _runPack
- Modify client/test/services/skill/skill_pack_registry_test.dart
- Modify client/test/services/skill/skill_acquisition_engine_test.dart

Interfaces:
- SkillPackRegistry keeps synchronous byId(String) and all().
- SkillPackRegistry adds Future<void> ensureLoaded({bool forceRefresh = false}).
- Its optional remote source defaults to GitRegistrySkillPackSource().
- _runPack awaits ensureLoaded only after a synchronous byId miss.

- [ ] Step 1: Add failing lazy-load, precedence, and no-network tests

Define the fixture and fake source in the test file so the examples are
self-contained, then assert:

    final remoteGstackPack = SkillPack(
      id: 'garrytan/gstack',
      name: 'remote-gstack',
      install: [FromInstruction.parseRef('garrytan/gstack@main')],
    );

    class _FakeSkillPackSource implements SkillPackSource {
      _FakeSkillPackSource(this.loader);
      final Future<List<SkillPack>> Function() loader;
      @override
      Future<List<SkillPack>> fetchPacks({bool forceRefresh = false}) => loader();
    }

    test('loads a remote pack once after a lookup miss', () async {
      var loads = 0;
      final registry = SkillPackRegistry(
        remote: _FakeSkillPackSource(() async {
          loads++;
          return [remoteGstackPack];
        }),
      );

      expect(registry.byId('garrytan/gstack'), isNull);
      await registry.ensureLoaded();
      await registry.ensureLoaded();
      expect(loads, 1);
      expect(registry.byId('garrytan/gstack'), remoteGstackPack);
    });

    test('built-in pack wins over remote same id', () async {
      final registry = SkillPackRegistry(
        remote: _FakeSkillPackSource(() async => [remoteGstackPack]),
      );
      await registry.ensureLoaded();
      expect(registry.byId('garrytan/gstack'), kGstackSkillPack);
    });

Add an acquisition-engine test that a known local pack succeeds without invoking the fake remote source.

- [ ] Step 2: Implement lazy merge and failure retention

Keep local packs in _byId and merge remote packs with putIfAbsent. Use one in-flight Future for concurrent first loads, set the loaded flag in finally, retain local packs if remote fetch fails, and allow explicit forceRefresh. Do not overwrite local IDs.

The core merge is:

    for (final pack in remote) {
      _byId.putIfAbsent(pack.id, () => pack);
    }

- [ ] Step 3: Await remote resolution only after a miss

Change _runPack to:

    var pack = _packRegistry.byId(packId);
    if (pack == null) {
      await _packRegistry.ensureLoaded();
      pack = _packRegistry.byId(packId);
    }
    if (pack == null) {
      return SkillAcquireResult(
        success: false,
        message: 'Unknown skill pack: $packId',
      );
    }

Keep the existing empty-install, install execution, expected-skill, and install-record behavior unchanged.

- [ ] Step 4: Run and commit Skill Pack tests

    cd client && flutter test \
      test/services/skill/skill_pack_registry_test.dart \
      test/services/skill/skill_acquisition_engine_test.dart \
      test/services/skill/skill_pack_install_store_test.dart
    cd ..
    git add client/lib/services/skill/skill_pack_registry.dart \
      client/lib/services/skill/skill_acquisition_engine.dart \
      client/test/services/skill/skill_pack_registry_test.dart \
      client/test/services/skill/skill_acquisition_engine_test.dart
    git commit -m "feat(skill-packs): lazy-load remote pack definitions"

Expected: PASS.

### Task 5: Update documentation and active references

Files:
- Modify README.md
- Modify README.zh.md
- Do not modify approved design text unless implementation materially differs

Interfaces:
- Documents the resources/ submodule and dedicated public registry.
- Does not describe old-prefix compatibility or runtime submodule scanning.

- [ ] Step 1: Update user-facing documentation

State that public Team/Expert/Skill Pack resources are maintained in hhoao/teampilot-resources, the application repository tracks it at resources/, consumers use indexed Raw endpoints, and Hub publishing targets the resources repository.

- [ ] Step 2: Audit active old-prefix references

    rg -n 'hhoao/teampilot/(team-hub|member-hub)' \
      client/lib client/test README.md README.zh.md docs

Update active code, tests, and user-facing docs. The launch-profile comment
must describe only the new resources-repository key. Historical design text may
mention the old identity only to document the clean-break policy; it must not
be used by runtime code or migrated manifests.

- [ ] Step 3: Validate repository structure and JSON

    git ls-files team-hub member-hub skill-packs
    git submodule status
    find resources -name '*.json' -print0 |
      xargs -0 -n1 ruby -e 'require "json"; JSON.parse(File.read(ARGV.fetch(0)))'

Expected: the first command prints nothing, the second shows the resources gitlink, and all submodule JSON files parse.

- [ ] Step 4: Commit documentation cleanup

    git add README.md README.zh.md
    git commit -m "docs: document dedicated resources registry"

Expected: only documentation and active-reference changes are included.

### Task 6: Full verification and handoff

Files:
- No planned production changes; if a failure is found, add a focused regression test before changing feature-owned code.

Interfaces:
- Verifies every acceptance criterion in the approved design.

- [ ] Step 1: Run focused catalog tests

    cd client && flutter test \
      test/services/team_hub \
      test/services/expert_hub \
      test/services/hub_publish \
      test/pages/hub_publish \
      test/services/skill \
      test/services/storage

Expected: PASS.

- [ ] Step 2: Run static analysis

    cd client && flutter analyze --no-fatal-infos --no-fatal-warnings

Expected: exit code 0 and no analyzer errors.

- [ ] Step 3: Run the repository test entry point

    cd client && dart run tool/run_tests.dart

Expected: exit code 0. Existing unrelated dirty-worktree changes are preserved and reported separately if relevant.

- [ ] Step 4: Verify the pushed pointer and final diff

    git diff --check
    git submodule status
    git ls-remote https://github.com/hhoao/teampilot-resources.git refs/heads/main
    git status --short

Expected: the resource commit exists remotely, the parent gitlink points to it, no whitespace errors are reported, and only existing unrelated changes plus this feature remain.

- [ ] Step 5: Report evidence

Summarize parent commits, resource repository commit, tests, analyzer output, and any GitHub push limitation.
