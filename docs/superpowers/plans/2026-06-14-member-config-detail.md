# Member Config Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a right-click menu to each member row in the project page's right-side tool list, with a read-only "member detail" dialog whose contents are read from that member's real CLI config directory (runtime dir, with team-layer fallback).

**Architecture:** A new `MemberConfigInspector` service resolves the member's CONFIG_DIR (runtime → team fallback) and delegates per-CLI reads to a new `MemberConfigInspectionCapability` on each `CliToolDefinition`. A `MemberConfigCubit` loads the resulting `MemberConfigDetail` model into a tabbed read-only dialog. The member-row right-click menu reuses the existing `showSidebarActionMenuFromSpecsAtTap` helper.

**Tech Stack:** Flutter, `flutter_bloc` (cubits), the capability-based `CliToolRegistry`, `CliDataLayout` path model, `AppStorage.fs` / `Filesystem` abstraction, `InMemoryFilesystem` test helper.

**Reference spec:** [docs/superpowers/specs/2026-06-14-member-config-detail-design.md](../specs/2026-06-14-member-config-detail-design.md)

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `client/lib/services/cli/member_config/member_config_detail.dart` | Immutable result model + value types + source-layer enum | Create |
| `client/lib/services/cli/registry/capabilities/member_config_inspection_capability.dart` | Capability interface, `MemberConfigContext`, `DefaultMemberConfigInspection` | Create |
| `client/lib/services/cli/member_config/member_config_inspector.dart` | Resolve CONFIG_DIR (runtime→team), pick source layer, call capability | Create |
| `client/lib/services/io/system_folder_opener.dart` | Inject-able "open folder in OS file manager" service | Create |
| `client/lib/cubits/member_config_cubit.dart` | Async load of `MemberConfigDetail` (loading/loaded/error) | Create |
| `client/lib/pages/home_workspace/project/member_detail_dialog.dart` | Read-only tabbed dialog (概览/Skills/MCP/插件/设置) | Create |
| `client/lib/widgets/right_tools/members_panel.dart` | Add right-click menu specs per row | Modify |
| `client/lib/widgets/right_tools/right_tools_panel.dart` | Supply menu callbacks + gating (`activeTab != null`) | Modify |
| `client/lib/services/cli/registry/tools/*.dart` (all 5) | Register the inspection capability | Modify |
| `client/lib/services/cli/registry/built_in_cli_tools.dart` | Assert every CLI registers the capability | Modify |
| `client/lib/pages/home_workspace/project/project_info_section.dart` | Use `SystemFolderOpener` instead of local `_openFolder` | Modify |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | New UI strings | Modify |

---

## Task 1: MemberConfigDetail model

**Files:**
- Create: `client/lib/services/cli/member_config/member_config_detail.dart`
- Test: `client/test/services/cli/member_config/member_config_detail_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/member_config/member_config_detail_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';

void main() {
  test('MemberConfigDetail.none marks an absent config dir', () {
    const detail = MemberConfigDetail.none(cli: CliTool.claude);
    expect(detail.sourceLayer, MemberConfigSourceLayer.none);
    expect(detail.resolvedDir, '');
    expect(detail.skills, isEmpty);
    expect(detail.mcpServers, isEmpty);
    expect(detail.plugins, isEmpty);
    expect(detail.settings, isEmpty);
    expect(detail.warnings, isEmpty);
    expect(detail.hasConfig, isFalse);
  });

  test('hasConfig is true when source layer is runtime or team', () {
    const detail = MemberConfigDetail(
      cli: CliTool.claude,
      resolvedDir: '/tp/config-profiles/teams/t/claude',
      sourceLayer: MemberConfigSourceLayer.team,
    );
    expect(detail.hasConfig, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/member_config/member_config_detail_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / `MemberConfigDetail` undefined.

- [ ] **Step 3: Write the model**

```dart
// client/lib/services/cli/member_config/member_config_detail.dart
import 'package:flutter/foundation.dart';

import '../../../models/team_config.dart';

/// Which isolation layer the member's config was read from.
enum MemberConfigSourceLayer { runtime, team, none }

@immutable
class ConfigEntry {
  const ConfigEntry({required this.key, required this.value});
  final String key;
  final String value;
}

@immutable
class SkillEntry {
  const SkillEntry({required this.name, this.description = '', this.path = ''});
  final String name;
  final String description;
  final String path;
}

@immutable
class McpServerEntry {
  const McpServerEntry({required this.name, this.summary = ''});
  final String name;

  /// Human-readable transport/command summary (e.g. `npx ...` or a URL).
  final String summary;
}

@immutable
class PluginEntry {
  const PluginEntry({required this.name, this.version = '', this.source = ''});
  final String name;
  final String version;
  final String source;
}

/// A non-fatal problem reading one section; the rest of the detail still renders.
@immutable
class SectionWarning {
  const SectionWarning({required this.section, required this.message});
  final String section;
  final String message;
}

/// Read-only snapshot of a team member's on-disk CLI configuration.
@immutable
class MemberConfigDetail {
  const MemberConfigDetail({
    required this.cli,
    this.resolvedDir = '',
    this.sourceLayer = MemberConfigSourceLayer.none,
    this.provider = '',
    this.model = '',
    this.settings = const [],
    this.skills = const [],
    this.mcpServers = const [],
    this.plugins = const [],
    this.warnings = const [],
  });

  const MemberConfigDetail.none({required this.cli})
      : resolvedDir = '',
        sourceLayer = MemberConfigSourceLayer.none,
        provider = '',
        model = '',
        settings = const [],
        skills = const [],
        mcpServers = const [],
        plugins = const [],
        warnings = const [];

  final CliTool cli;
  final String resolvedDir;
  final MemberConfigSourceLayer sourceLayer;
  final String provider;
  final String model;
  final List<ConfigEntry> settings;
  final List<SkillEntry> skills;
  final List<McpServerEntry> mcpServers;
  final List<PluginEntry> plugins;
  final List<SectionWarning> warnings;

  bool get hasConfig => sourceLayer != MemberConfigSourceLayer.none;

  MemberConfigDetail copyWith({
    String? resolvedDir,
    MemberConfigSourceLayer? sourceLayer,
    String? provider,
    String? model,
    List<ConfigEntry>? settings,
    List<SkillEntry>? skills,
    List<McpServerEntry>? mcpServers,
    List<PluginEntry>? plugins,
    List<SectionWarning>? warnings,
  }) {
    return MemberConfigDetail(
      cli: cli,
      resolvedDir: resolvedDir ?? this.resolvedDir,
      sourceLayer: sourceLayer ?? this.sourceLayer,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      settings: settings ?? this.settings,
      skills: skills ?? this.skills,
      mcpServers: mcpServers ?? this.mcpServers,
      plugins: plugins ?? this.plugins,
      warnings: warnings ?? this.warnings,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/member_config/member_config_detail_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/member_config/member_config_detail.dart \
        client/test/services/cli/member_config/member_config_detail_test.dart
git commit -m "feat: add MemberConfigDetail model for member config inspection"
```

---

## Task 2: MemberConfigInspectionCapability + default implementation

The default impl reads the generic layout shared by all CLIs: `skills/` subdirs, `plugins/` subdirs via plugin manifest, an aggregated MCP `servers.json` (`{"mcpServers": {...}}`), and a top-level `settings.json` (flat string keys). Per-CLI subclasses can override later; for now every CLI uses the default.

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/member_config_inspection_capability.dart`
- Test: `client/test/services/cli/registry/capabilities/member_config_inspection_capability_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/capabilities/member_config_inspection_capability_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';
import 'package:teampilot/services/cli/registry/capabilities/member_config_inspection_capability.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  const cap = DefaultMemberConfigInspection();

  setUp(() => fs = InMemoryFilesystem());

  MemberConfigContext ctx() => MemberConfigContext(
        cli: CliTool.claude,
        configDir: '/cfg',
        sourceLayer: MemberConfigSourceLayer.runtime,
        mcpSnapshotPath: '/mcp/servers.json',
        provider: 'anthropic',
        model: 'claude-opus-4-8',
        fs: fs,
      );

  test('reads skills from skills/ subdirectories', () async {
    await fs.writeString(
      '/cfg/skills/alpha/SKILL.md',
      '---\nname: Alpha\ndescription: does alpha\n---\nbody',
    );
    await fs.ensureDir('/cfg/skills/beta');

    final detail = await cap.inspect(ctx());

    expect(detail.skills.map((s) => s.name).toList()..sort(),
        ['Alpha', 'beta']);
    final alpha = detail.skills.firstWhere((s) => s.name == 'Alpha');
    expect(alpha.description, 'does alpha');
  });

  test('reads plugins from plugins/ via manifest', () async {
    await fs.writeString(
      '/cfg/plugins/p1/.claude-plugin/plugin.json',
      '{"name":"p1","version":"1.2.0"}',
    );

    final detail = await cap.inspect(ctx());

    expect(detail.plugins, hasLength(1));
    expect(detail.plugins.single.name, 'p1');
    expect(detail.plugins.single.version, '1.2.0');
  });

  test('reads MCP servers from the snapshot file', () async {
    await fs.writeString(
      '/mcp/servers.json',
      '{"mcpServers":{"fs":{"command":"npx","args":["server-fs"]},'
      '"web":{"url":"https://example.com/mcp"}}}',
    );

    final detail = await cap.inspect(ctx());

    expect(detail.mcpServers.map((m) => m.name).toList()..sort(),
        ['fs', 'web']);
    final web = detail.mcpServers.firstWhere((m) => m.name == 'web');
    expect(web.summary, contains('https://example.com/mcp'));
  });

  test('reads flat settings from settings.json', () async {
    await fs.writeString(
      '/cfg/settings.json',
      '{"theme":"dark","autoUpdate":true}',
    );

    final detail = await cap.inspect(ctx());

    final keys = detail.settings.map((e) => e.key).toList()..sort();
    expect(keys, ['autoUpdate', 'theme']);
  });

  test('missing directories yield empty sections without warnings', () async {
    final detail = await cap.inspect(ctx());
    expect(detail.skills, isEmpty);
    expect(detail.plugins, isEmpty);
    expect(detail.mcpServers, isEmpty);
    expect(detail.settings, isEmpty);
    expect(detail.warnings, isEmpty);
  });

  test('corrupt settings.json produces a section warning, not a throw', () async {
    await fs.writeString('/cfg/settings.json', '{not json');
    final detail = await cap.inspect(ctx());
    expect(detail.settings, isEmpty);
    expect(detail.warnings.map((w) => w.section), contains('settings'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/capabilities/member_config_inspection_capability_test.dart`
Expected: FAIL — capability classes undefined.

- [ ] **Step 3: Write the capability + default implementation**

```dart
// client/lib/services/cli/registry/capabilities/member_config_inspection_capability.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../member_config/member_config_detail.dart';
import '../cli_capability.dart';
import 'plugin_manifest_capability.dart';

/// Inputs for [MemberConfigInspectionCapability.inspect], resolved by
/// `MemberConfigInspector` before delegating to the CLI.
@immutable
class MemberConfigContext {
  const MemberConfigContext({
    required this.cli,
    required this.configDir,
    required this.sourceLayer,
    required this.mcpSnapshotPath,
    required this.provider,
    required this.model,
    required this.fs,
  });

  final CliTool cli;
  final String configDir;
  final MemberConfigSourceLayer sourceLayer;

  /// Aggregated team MCP snapshot (`config-profiles/teams/{id}/mcp/servers.json`).
  final String mcpSnapshotPath;
  final String provider;
  final String model;
  final Filesystem fs;
}

/// Reads a member's on-disk config for a single CLI. Default behaviour lives in
/// [DefaultMemberConfigInspection]; CLIs whose layout differs register a subclass.
abstract interface class MemberConfigInspectionCapability
    implements CliCapability {
  Future<MemberConfigDetail> inspect(MemberConfigContext ctx);
}

/// Reads the layout common to all CLIs: `skills/`, `plugins/`, an aggregated MCP
/// `servers.json`, and a top-level `settings.json`.
class DefaultMemberConfigInspection
    implements MemberConfigInspectionCapability {
  const DefaultMemberConfigInspection();

  @override
  Future<MemberConfigDetail> inspect(MemberConfigContext ctx) async {
    final warnings = <SectionWarning>[];
    final skills = await _readSkills(ctx, warnings);
    final plugins = await _readPlugins(ctx, warnings);
    final mcp = await _readMcp(ctx, warnings);
    final settings = await _readSettings(ctx, warnings);
    return MemberConfigDetail(
      cli: ctx.cli,
      resolvedDir: ctx.configDir,
      sourceLayer: ctx.sourceLayer,
      provider: ctx.provider,
      model: ctx.model,
      skills: skills,
      plugins: plugins,
      mcpServers: mcp,
      settings: settings,
      warnings: warnings,
    );
  }

  p.Context _pc(MemberConfigContext ctx) => ctx.fs.pathContext;

  Future<List<SkillEntry>> _readSkills(
    MemberConfigContext ctx,
    List<SectionWarning> warnings,
  ) async {
    final dir = _pc(ctx).join(ctx.configDir, 'skills');
    if (!(await ctx.fs.stat(dir)).isDirectory) return const [];
    final out = <SkillEntry>[];
    try {
      for (final entry in await ctx.fs.listDir(dir)) {
        if (!entry.isDirectory) continue;
        final skillDir = _pc(ctx).join(dir, entry.name);
        var name = entry.name;
        var description = '';
        for (final manifest in const ['SKILL.md', 'skill.md']) {
          final raw = await ctx.fs.readString(_pc(ctx).join(skillDir, manifest));
          if (raw == null) continue;
          final fm = _frontMatter(raw);
          name = fm['name']?.trim().isNotEmpty == true ? fm['name']!.trim() : name;
          description = fm['description']?.trim() ?? '';
          break;
        }
        out.add(SkillEntry(name: name, description: description, path: skillDir));
      }
    } on Object catch (e) {
      warnings.add(SectionWarning(section: 'skills', message: '$e'));
    }
    return out;
  }

  Future<List<PluginEntry>> _readPlugins(
    MemberConfigContext ctx,
    List<SectionWarning> warnings,
  ) async {
    final dir = _pc(ctx).join(ctx.configDir, 'plugins');
    if (!(await ctx.fs.stat(dir)).isDirectory) return const [];
    final candidates = (pluginManifestPathsForTool(ctx.cli) ??
            claudePluginManifestPaths)
        .manifestCandidates()
        .toList();
    final out = <PluginEntry>[];
    try {
      for (final entry in await ctx.fs.listDir(dir)) {
        if (!entry.isDirectory) continue;
        final bundleDir = _pc(ctx).join(dir, entry.name);
        var name = entry.name;
        var version = '';
        for (final rel in candidates) {
          final raw = await ctx.fs.readString(_pc(ctx).join(bundleDir, rel));
          if (raw == null) continue;
          try {
            final json = jsonDecode(raw) as Map<String, Object?>;
            name = (json['name'] as String?)?.trim().isNotEmpty == true
                ? (json['name'] as String).trim()
                : name;
            version = (json['version'] as String?)?.trim() ?? '';
          } on Object {
            // fall through to directory-name defaults
          }
          break;
        }
        out.add(PluginEntry(name: name, version: version, source: bundleDir));
      }
    } on Object catch (e) {
      warnings.add(SectionWarning(section: 'plugins', message: '$e'));
    }
    return out;
  }

  Future<List<McpServerEntry>> _readMcp(
    MemberConfigContext ctx,
    List<SectionWarning> warnings,
  ) async {
    final raw = await ctx.fs.readString(ctx.mcpSnapshotPath);
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final servers = json['mcpServers'] as Map<String, Object?>? ??
          const <String, Object?>{};
      return [
        for (final e in servers.entries)
          McpServerEntry(
            name: e.key,
            summary: _mcpSummary(e.value),
          ),
      ];
    } on Object catch (e) {
      warnings.add(SectionWarning(section: 'mcp', message: '$e'));
      return const [];
    }
  }

  Future<List<ConfigEntry>> _readSettings(
    MemberConfigContext ctx,
    List<SectionWarning> warnings,
  ) async {
    final raw =
        await ctx.fs.readString(_pc(ctx).join(ctx.configDir, 'settings.json'));
    if (raw == null) return const [];
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return [
        for (final e in json.entries)
          ConfigEntry(key: e.key, value: '${e.value}'),
      ];
    } on Object catch (e) {
      warnings.add(SectionWarning(section: 'settings', message: '$e'));
      return const [];
    }
  }

  String _mcpSummary(Object? value) {
    if (value is! Map) return '';
    final url = value['url'];
    if (url is String && url.isNotEmpty) return url;
    final command = value['command'];
    final args = value['args'];
    if (command is String && command.isNotEmpty) {
      final argList = args is List ? args.join(' ') : '';
      return argList.isEmpty ? command : '$command $argList';
    }
    final type = value['type'];
    return type is String ? type : '';
  }

  /// Minimal YAML front-matter reader (`---` fenced `key: value` lines).
  Map<String, String> _frontMatter(String raw) {
    final lines = raw.replaceAll('\r\n', '\n').split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return const {};
    final out = <String, String>{};
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') break;
      final idx = lines[i].indexOf(':');
      if (idx <= 0) continue;
      final key = lines[i].substring(0, idx).trim();
      final value = lines[i].substring(idx + 1).trim();
      if (key.isNotEmpty) out[key] = value;
    }
    return out;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/registry/capabilities/member_config_inspection_capability_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/member_config_inspection_capability.dart \
        client/test/services/cli/registry/capabilities/member_config_inspection_capability_test.dart
git commit -m "feat: add MemberConfigInspectionCapability with default reader"
```

---

## Task 3: Register the capability on all five CLI tools

Add the capability field to each tool definition, include it in `capabilities`, and assert universal registration. All five use `DefaultMemberConfigInspection` for now.

**Files:**
- Modify: `client/lib/services/cli/registry/tools/claude_cli_tool.dart`, `flashskyai_cli_tool.dart`, `codex_cli_tool.dart`, `opencode_cli_tool.dart`, `cursor_cli_tool.dart`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart:54-69`
- Test: `client/test/services/cli/registry/member_config_inspection_registration_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/member_config_inspection_registration_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/member_config_inspection_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('every CLI registers a MemberConfigInspectionCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values) {
      expect(
        registry.capability<MemberConfigInspectionCapability>(cli),
        isNotNull,
        reason: 'missing inspection capability for ${cli.value}',
      );
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/registry/member_config_inspection_registration_test.dart`
Expected: FAIL — capability null for every CLI.

- [ ] **Step 3a: Add the field to each tool definition**

For `claude_cli_tool.dart`, add the import near the other capability imports:

```dart
import '../capabilities/member_config_inspection_capability.dart';
```

Add a constructor default field (place beside `pluginManifest`):

```dart
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
```

Add the field declaration (beside the others):

```dart
  final MemberConfigInspectionCapability memberConfigInspection;
```

Add it to the `capabilities` list (anywhere in the list):

```dart
    memberConfigInspection,
```

Repeat the same four edits in `flashskyai_cli_tool.dart`, `codex_cli_tool.dart`, `opencode_cli_tool.dart`, and `cursor_cli_tool.dart`. Each of those files follows the same `this.field = const X()` constructor + `final X field;` + `capabilities => [ ... ]` shape as `claude_cli_tool.dart:29-98`; insert the three lines and the import the same way.

- [ ] **Step 3b: Add a registration assert**

In `built_in_cli_tools.dart`, add the import:

```dart
import 'capabilities/member_config_inspection_capability.dart';
```

After the existing `ProviderModelCapability` assert block (ends at line 67), add:

```dart
  assert(
    CliTool.values.every(
      (cli) =>
          registry.capability<MemberConfigInspectionCapability>(cli) != null,
    ),
    'Every CliTool must register MemberConfigInspectionCapability',
  );
```

- [ ] **Step 4: Run the test + analyzer**

Run: `cd client && flutter test test/services/cli/registry/member_config_inspection_registration_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/cli/registry`
Expected: test PASS (1 test); analyzer reports no errors.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/tools \
        client/lib/services/cli/registry/built_in_cli_tools.dart \
        client/test/services/cli/registry/member_config_inspection_registration_test.dart
git commit -m "feat: register MemberConfigInspectionCapability on all CLIs"
```

---

## Task 4: MemberConfigInspector service

Resolves the member's CONFIG_DIR (runtime → team fallback), picks the source layer, then calls the CLI's capability. Path math uses `CliDataLayout` + `mixedModeMemberScopeSessionId`.

**Files:**
- Create: `client/lib/services/cli/member_config/member_config_inspector.dart`
- Test: `client/test/services/cli/member_config/member_config_inspector_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/member_config/member_config_inspector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';
import 'package:teampilot/services/cli/member_config/member_config_inspector.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CliDataLayout layout;
  late MemberConfigInspector inspector;

  const member = TeamMemberConfig(
    id: 'm1',
    name: 'Backend',
    provider: 'anthropic',
    model: 'claude-opus-4-8',
  );
  const team = TeamConfig(
    id: 'team-a',
    name: 'Team A',
    cli: CliTool.claude,
    teamMode: TeamMode.mixed,
    members: [member],
  );

  setUp(() {
    fs = InMemoryFilesystem();
    layout = CliDataLayout(teampilotRoot: '/tp', fs: fs);
    inspector = MemberConfigInspector(
      layout: layout,
      fs: fs,
      registry: CliToolRegistry.builtIn(),
    );
  });

  test('prefers the runtime member dir when it exists (mixed mode nests by id)',
      () async {
    // mixed mode dir id = {cliTeamName}/{memberId}
    final dir = layout.memberToolDir('team-a', 'team-a-1/m1', 'claude');
    await fs.ensureDir(dir);
    await fs.writeString('$dir/skills/a/SKILL.md', '---\nname: A\n---');

    final detail = await inspector.inspect(
      team: team,
      member: member,
      cliTeamName: 'team-a-1',
    );

    expect(detail.sourceLayer, MemberConfigSourceLayer.runtime);
    expect(detail.resolvedDir, dir);
    expect(detail.skills.single.name, 'A');
  });

  test('falls back to the team dir when runtime dir is absent', () async {
    final teamDir = layout.teamToolDir('team-a', 'claude');
    await fs.ensureDir(teamDir);

    final detail = await inspector.inspect(
      team: team,
      member: member,
      cliTeamName: 'team-a-1',
    );

    expect(detail.sourceLayer, MemberConfigSourceLayer.team);
    expect(detail.resolvedDir, teamDir);
  });

  test('returns none when neither layer exists', () async {
    final detail = await inspector.inspect(
      team: team,
      member: member,
      cliTeamName: '',
    );
    expect(detail.sourceLayer, MemberConfigSourceLayer.none);
    expect(detail.hasConfig, isFalse);
  });
}
```

> Note: if `TeamConfig` / `TeamMemberConfig` const constructors require more named params than shown, copy the exact required params from `client/lib/models/team_config.dart` — the three fields under test (`id`, `cli`, `teamMode`, `members`, member `id`/`provider`/`model`) are what matter.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/cli/member_config/member_config_inspector_test.dart`
Expected: FAIL — `MemberConfigInspector` undefined.

- [ ] **Step 3: Write the service**

```dart
// client/lib/services/cli/member_config/member_config_inspector.dart
import '../../../models/team_config.dart';
import '../../io/filesystem.dart';
import '../../storage/app_storage.dart';
import '../../storage/runtime_storage_context.dart';
import '../cli_data_layout.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/cli_tool_registry.dart';
import '../registry/config_profile/config_profile_scope.dart';
import 'member_config_detail.dart';

/// Resolves a team member's real CLI CONFIG_DIR (runtime dir, with team-layer
/// fallback) and reads it via the CLI's [MemberConfigInspectionCapability].
class MemberConfigInspector {
  MemberConfigInspector({
    CliDataLayout? layout,
    Filesystem? fs,
    CliToolRegistry? registry,
  })  : _fs = fs ?? AppStorage.fs,
        _layout = layout ??
            CliDataLayout(
              teampilotRoot: RuntimeStorageContext.current.appDataRoot,
              fs: fs ?? AppStorage.fs,
            ),
        _registry = registry ?? CliToolRegistry.builtIn();

  final Filesystem _fs;
  final CliDataLayout _layout;
  final CliToolRegistry _registry;

  Future<MemberConfigDetail> inspect({
    required TeamConfig team,
    required TeamMemberConfig member,
    required String cliTeamName,
  }) async {
    final cli = member.cliWithin(team);
    final tool = cli.value;

    final resolved = await _resolveDir(
      team: team,
      member: member,
      cliTeamName: cliTeamName.trim(),
      tool: tool,
    );
    if (resolved == null) {
      return MemberConfigDetail.none(cli: cli);
    }

    final capability =
        _registry.capability<MemberConfigInspectionCapability>(cli) ??
            const DefaultMemberConfigInspection();

    return capability.inspect(
      MemberConfigContext(
        cli: cli,
        configDir: resolved.dir,
        sourceLayer: resolved.layer,
        mcpSnapshotPath: _layout.teamMcpServersFile(team.id),
        provider: member.provider,
        model: member.model,
        fs: _fs,
      ),
    );
  }

  Future<_ResolvedDir?> _resolveDir({
    required TeamConfig team,
    required TeamMemberConfig member,
    required String cliTeamName,
    required String tool,
  }) async {
    if (cliTeamName.isNotEmpty) {
      final dirId = team.teamMode == TeamMode.mixed
          ? mixedModeMemberScopeSessionId(_fs.pathContext, cliTeamName, member)
          : cliTeamName;
      final runtimeDir = _layout.memberToolDir(team.id, dirId, tool);
      if ((await _fs.stat(runtimeDir)).isDirectory) {
        return _ResolvedDir(runtimeDir, MemberConfigSourceLayer.runtime);
      }
    }
    final teamDir = _layout.teamToolDir(team.id, tool);
    if ((await _fs.stat(teamDir)).isDirectory) {
      return _ResolvedDir(teamDir, MemberConfigSourceLayer.team);
    }
    return null;
  }
}

class _ResolvedDir {
  const _ResolvedDir(this.dir, this.layer);
  final String dir;
  final MemberConfigSourceLayer layer;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/cli/member_config/member_config_inspector_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/member_config/member_config_inspector.dart \
        client/test/services/cli/member_config/member_config_inspector_test.dart
git commit -m "feat: add MemberConfigInspector resolving member CONFIG_DIR"
```

---

## Task 5: SystemFolderOpener service + refactor project_info_section

Lift the existing `_openFolder` (`Process.run`) out of the page into one injectable service, and switch `project_info_section.dart` to use it. Keeps `Process.run` out of UI.

**Files:**
- Create: `client/lib/services/io/system_folder_opener.dart`
- Modify: `client/lib/pages/home_workspace/project/project_info_section.dart:341-348` (remove `_openFolder`, call the service); line 77 onPressed
- Test: `client/test/services/io/system_folder_opener_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/io/system_folder_opener_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/system_folder_opener.dart';

void main() {
  test('invokes the platform runner with the resolved command and path', () async {
    String? seenExe;
    List<String>? seenArgs;
    final opener = SystemFolderOpener(
      isMacOS: false,
      isWindows: true,
      isLinux: false,
      runner: (exe, args) async {
        seenExe = exe;
        seenArgs = args;
      },
    );

    await opener.reveal(r'C:\some\path');

    expect(seenExe, 'explorer');
    expect(seenArgs, [r'C:\some\path']);
  });

  test('uses open on macOS and xdg-open on Linux', () async {
    final calls = <String>[];
    final mac = SystemFolderOpener(
      isMacOS: true, isWindows: false, isLinux: false,
      runner: (exe, _) async => calls.add(exe),
    );
    final linux = SystemFolderOpener(
      isMacOS: false, isWindows: false, isLinux: true,
      runner: (exe, _) async => calls.add(exe),
    );
    await mac.reveal('/p');
    await linux.reveal('/p');
    expect(calls, ['open', 'xdg-open']);
  });

  test('does nothing for empty path', () async {
    var called = false;
    final opener = SystemFolderOpener(
      isMacOS: false, isWindows: false, isLinux: true,
      runner: (_, __) async => called = true,
    );
    await opener.reveal('   ');
    expect(called, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/io/system_folder_opener_test.dart`
Expected: FAIL — `SystemFolderOpener` undefined.

- [ ] **Step 3: Write the service**

```dart
// client/lib/services/io/system_folder_opener.dart
import 'dart:io';

typedef ProcessRunner = Future<void> Function(String exe, List<String> args);

/// Opens a directory in the OS file manager. Desktop-only; the caller hides the
/// affordance on remote (SSH) storage backends.
class SystemFolderOpener {
  SystemFolderOpener({
    bool? isMacOS,
    bool? isWindows,
    bool? isLinux,
    ProcessRunner? runner,
  })  : _isMacOS = isMacOS ?? Platform.isMacOS,
        _isWindows = isWindows ?? Platform.isWindows,
        _isLinux = isLinux ?? Platform.isLinux,
        _runner = runner ?? _defaultRunner;

  final bool _isMacOS;
  final bool _isWindows;
  final bool _isLinux;
  final ProcessRunner _runner;

  static Future<void> _defaultRunner(String exe, List<String> args) async {
    await Process.run(exe, args);
  }

  Future<void> reveal(String path) async {
    final target = path.trim();
    if (target.isEmpty) return;
    final exe = _isMacOS
        ? 'open'
        : _isWindows
            ? 'explorer'
            : 'xdg-open';
    await _runner(exe, [target]);
  }
}
```

> Note: the old page used `start` on Windows; `explorer <path>` is the correct argv form for `Process.run` (no shell), which is why the service uses `explorer`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/io/system_folder_opener_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Refactor project_info_section.dart**

Add import at top of `client/lib/pages/home_workspace/project/project_info_section.dart`:

```dart
import '../../../services/io/system_folder_opener.dart';
```

Replace the local helper (lines 341-348):

```dart
void _openFolder(String path) {
  final command = Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'start'
      : 'xdg-open';
  Process.run(command, [path]);
}
```

with:

```dart
void _openFolder(String path) {
  SystemFolderOpener().reveal(path);
}
```

If `dart:io` is now unused in that file, remove its import (the analyzer will flag it).

- [ ] **Step 6: Verify analyzer + run the service test again**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/home_workspace/project/project_info_section.dart lib/services/io/system_folder_opener.dart`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/io/system_folder_opener.dart \
        client/test/services/io/system_folder_opener_test.dart \
        client/lib/pages/home_workspace/project/project_info_section.dart
git commit -m "refactor: extract SystemFolderOpener service from project info section"
```

---

## Task 6: MemberConfigCubit + state

Drives the dialog: starts loading on open, exposes loading/loaded/error.

**Files:**
- Create: `client/lib/cubits/member_config_cubit.dart`
- Test: `client/test/cubits/member_config_cubit_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// client/test/cubits/member_config_cubit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/member_config_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';
import 'package:teampilot/services/cli/member_config/member_config_inspector.dart';

class _FakeInspector extends MemberConfigInspector {
  _FakeInspector(this._result, {this.throwIt = false});
  final MemberConfigDetail _result;
  final bool throwIt;

  @override
  Future<MemberConfigDetail> inspect({
    required TeamConfig team,
    required TeamMemberConfig member,
    required String cliTeamName,
  }) async {
    if (throwIt) throw StateError('boom');
    return _result;
  }
}

const _member = TeamMemberConfig(id: 'm1', name: 'Backend');
const _team = TeamConfig(id: 't', name: 'T', cli: CliTool.claude, members: [_member]);

void main() {
  test('emits loading then loaded', () async {
    final cubit = MemberConfigCubit(
      inspector: _FakeInspector(
        const MemberConfigDetail(
          cli: CliTool.claude,
          sourceLayer: MemberConfigSourceLayer.team,
          resolvedDir: '/x',
        ),
      ),
    );
    final states = <MemberConfigStatus>[];
    cubit.stream.listen((s) => states.add(s.status));

    await cubit.load(team: _team, member: _member, cliTeamName: 't-1');

    expect(cubit.state.status, MemberConfigStatus.loaded);
    expect(cubit.state.detail?.resolvedDir, '/x');
    expect(states.first, MemberConfigStatus.loading);
  });

  test('emits error when inspector throws', () async {
    final cubit = MemberConfigCubit(
      inspector: _FakeInspector(
        const MemberConfigDetail(cli: CliTool.claude),
        throwIt: true,
      ),
    );
    await cubit.load(team: _team, member: _member, cliTeamName: 't-1');
    expect(cubit.state.status, MemberConfigStatus.error);
  });
}
```

> Note: confirm `TeamMemberConfig` / `TeamConfig` const constructors accept these params; if `name` alone is insufficient, copy the required-param shape from `client/lib/models/team_config.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/member_config_cubit_test.dart`
Expected: FAIL — `MemberConfigCubit` undefined.

- [ ] **Step 3: Write the cubit + state**

```dart
// client/lib/cubits/member_config_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';
import '../services/cli/member_config/member_config_detail.dart';
import '../services/cli/member_config/member_config_inspector.dart';
import '../utils/logger.dart';

enum MemberConfigStatus { idle, loading, loaded, error }

class MemberConfigState {
  const MemberConfigState({
    this.status = MemberConfigStatus.idle,
    this.detail,
  });

  final MemberConfigStatus status;
  final MemberConfigDetail? detail;

  MemberConfigState copyWith({
    MemberConfigStatus? status,
    MemberConfigDetail? detail,
  }) =>
      MemberConfigState(
        status: status ?? this.status,
        detail: detail ?? this.detail,
      );
}

class MemberConfigCubit extends Cubit<MemberConfigState> {
  MemberConfigCubit({MemberConfigInspector? inspector})
      : _inspector = inspector ?? MemberConfigInspector(),
        super(const MemberConfigState());

  final MemberConfigInspector _inspector;

  Future<void> load({
    required TeamConfig team,
    required TeamMemberConfig member,
    required String cliTeamName,
  }) async {
    emit(state.copyWith(status: MemberConfigStatus.loading));
    try {
      final detail = await _inspector.inspect(
        team: team,
        member: member,
        cliTeamName: cliTeamName,
      );
      if (isClosed) return;
      emit(MemberConfigState(
        status: MemberConfigStatus.loaded,
        detail: detail,
      ));
    } on Object catch (e, st) {
      appLogger.w('[member-config] inspect failed: $e', stackTrace: st);
      if (isClosed) return;
      emit(state.copyWith(status: MemberConfigStatus.error));
    }
  }
}
```

> Note: confirm the logger import path (`../utils/logger.dart`) and symbol (`appLogger`) match the codebase — `session_lifecycle_service.dart:8` imports `'../../utils/logger.dart'` and uses `appLogger`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/member_config_cubit_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/member_config_cubit.dart \
        client/test/cubits/member_config_cubit_test.dart
git commit -m "feat: add MemberConfigCubit driving member detail loading"
```

---

## Task 7: l10n strings

Add UI strings for the menu items, dialog tabs, banners, and empty/error states. ARB edits only; generated localizations rebuild on `flutter pub get`.

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`

- [ ] **Step 1: Add keys to `app_en.arb`** (insert before the closing brace; each non-last entry needs a trailing comma)

```json
  "memberDetailTitle": "Member detail",
  "memberDetailViewAction": "View member detail",
  "memberDetailOpenConfigDir": "Open config directory",
  "memberDetailOpenInFileManager": "Open in file manager",
  "memberDetailNeedsSession": "Open a session first",
  "memberDetailTabOverview": "Overview",
  "memberDetailTabSkills": "Skills",
  "memberDetailTabMcp": "MCP",
  "memberDetailTabPlugins": "Plugins",
  "memberDetailTabSettings": "Settings",
  "memberDetailSourceRuntime": "Live session config",
  "memberDetailSourceTeam": "Team-level config (member not launched in this session)",
  "memberDetailEmpty": "This member has no config yet in this session, and the team layer is empty.",
  "memberDetailLoadError": "Failed to read this member's config directory.",
  "memberDetailSectionEmpty": "None"
```

- [ ] **Step 2: Add the same keys to `app_zh.arb`**

```json
  "memberDetailTitle": "成员详情",
  "memberDetailViewAction": "查看成员详情",
  "memberDetailOpenConfigDir": "打开配置目录",
  "memberDetailOpenInFileManager": "在文件管理器中打开",
  "memberDetailNeedsSession": "请先打开一个会话",
  "memberDetailTabOverview": "概览",
  "memberDetailTabSkills": "Skills",
  "memberDetailTabMcp": "MCP",
  "memberDetailTabPlugins": "插件",
  "memberDetailTabSettings": "设置",
  "memberDetailSourceRuntime": "运行会话配置",
  "memberDetailSourceTeam": "团队层配置（该成员未在此会话中启动）",
  "memberDetailEmpty": "该成员尚未在此会话中启动，且团队层无配置。",
  "memberDetailLoadError": "读取该成员的配置目录失败。",
  "memberDetailSectionEmpty": "无"
```

- [ ] **Step 3: Regenerate localizations + warmup glyphs**

Run: `cd client && flutter pub get && dart run tool/gen_warmup_glyphs.dart`
Expected: `app_localizations*.dart` regenerated (getters like `l10n.memberDetailTitle` now exist); `lib/widgets/warmup_glyphs.g.dart` refreshed.

- [ ] **Step 4: Verify analyzer sees the new getters**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/l10n`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/lib/widgets/warmup_glyphs.g.dart
git commit -m "feat: add l10n strings for member config detail"
```

---

## Task 8: MemberDetailDialog

A read-only tabbed dialog fed by `MemberConfigCubit`. Renders the five tabs, a source banner, empty/error states, and the "open in file manager" footer (hidden when `resolvedDir` is empty).

**Files:**
- Create: `client/lib/pages/home_workspace/project/member_detail_dialog.dart`
- Test: `client/test/pages/home_workspace/project/member_detail_dialog_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// client/test/pages/home_workspace/project/member_detail_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/project/member_detail_dialog.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders skills tab from a loaded detail', (tester) async {
    const detail = MemberConfigDetail(
      cli: CliTool.claude,
      resolvedDir: '/tp/.../claude',
      sourceLayer: MemberConfigSourceLayer.runtime,
      skills: [SkillEntry(name: 'alpha', description: 'does alpha')],
    );

    await tester.pumpWidget(_host(
      MemberDetailDialogBody(
        memberName: 'Backend',
        detail: detail,
        onOpenInFileManager: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Switch to Skills tab and confirm the entry shows.
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MemberDetailDialogBody)),
    )!;
    await tester.tap(find.text(l10n.memberDetailTabSkills));
    await tester.pumpAndSettle();
    expect(find.text('alpha'), findsOneWidget);
  });

  testWidgets('shows empty state when there is no config', (tester) async {
    const detail = MemberConfigDetail.none(cli: CliTool.claude);
    await tester.pumpWidget(_host(
      MemberDetailDialogBody(
        memberName: 'Backend',
        detail: detail,
        onOpenInFileManager: () {},
      ),
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(MemberDetailDialogBody)),
    )!;
    expect(find.text(l10n.memberDetailEmpty), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/home_workspace/project/member_detail_dialog_test.dart`
Expected: FAIL — `MemberDetailDialogBody` / `member_detail_dialog.dart` undefined.

- [ ] **Step 3: Write the dialog**

```dart
// client/lib/pages/home_workspace/project/member_detail_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/member_config_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/team_config.dart';
import '../../../services/cli/member_config/member_config_detail.dart';
import '../../../services/cli/member_config/member_config_inspector.dart';
import '../../../services/io/system_folder_opener.dart';
import '../../../services/storage/runtime_storage_context.dart';

/// Opens the read-only member config detail dialog.
Future<void> showMemberDetailDialog(
  BuildContext context, {
  required TeamConfig team,
  required TeamMemberConfig member,
  required String cliTeamName,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => MemberConfigCubit()
        ..load(team: team, member: member, cliTeamName: cliTeamName),
      child: _MemberDetailDialog(memberName: member.name),
    ),
  );
}

class _MemberDetailDialog extends StatelessWidget {
  const _MemberDetailDialog({required this.memberName});
  final String memberName;

  bool get _canRevealLocally =>
      !RuntimeStorageContext.current.filesystemIsRemote;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MemberConfigCubit>().state;
    final l10n = context.l10n;

    Widget body;
    switch (state.status) {
      case MemberConfigStatus.loaded:
        final detail = state.detail!;
        body = MemberDetailDialogBody(
          memberName: memberName,
          detail: detail,
          onOpenInFileManager:
              (_canRevealLocally && detail.resolvedDir.isNotEmpty)
                  ? () => SystemFolderOpener().reveal(detail.resolvedDir)
                  : null,
        );
      case MemberConfigStatus.error:
        body = Center(child: Text(l10n.memberDetailLoadError));
      case MemberConfigStatus.idle:
      case MemberConfigStatus.loading:
        body = const Center(child: CircularProgressIndicator());
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: body,
      ),
    );
  }
}

/// Pure presentational body (no cubit) so it is trivially widget-testable.
class MemberDetailDialogBody extends StatelessWidget {
  const MemberDetailDialogBody({
    required this.memberName,
    required this.detail,
    this.onOpenInFileManager,
    super.key,
  });

  final String memberName;
  final MemberConfigDetail detail;
  final VoidCallback? onOpenInFileManager;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!detail.hasConfig) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.memberDetailTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Text(l10n.memberDetailEmpty, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(MaterialLocalizations.of(context).closeButtonLabel),
              ),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.memberDetailTitle} · $memberName',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l10n.memberDetailTabOverview),
              Tab(text: l10n.memberDetailTabSkills),
              Tab(text: l10n.memberDetailTabMcp),
              Tab(text: l10n.memberDetailTabPlugins),
              Tab(text: l10n.memberDetailTabSettings),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(detail: detail),
                _ListTab(
                  empty: l10n.memberDetailSectionEmpty,
                  items: [
                    for (final s in detail.skills)
                      (title: s.name, subtitle: s.description),
                  ],
                ),
                _ListTab(
                  empty: l10n.memberDetailSectionEmpty,
                  items: [
                    for (final m in detail.mcpServers)
                      (title: m.name, subtitle: m.summary),
                  ],
                ),
                _ListTab(
                  empty: l10n.memberDetailSectionEmpty,
                  items: [
                    for (final pl in detail.plugins)
                      (title: pl.name, subtitle: pl.version),
                  ],
                ),
                _ListTab(
                  empty: l10n.memberDetailSectionEmpty,
                  items: [
                    for (final e in detail.settings)
                      (title: e.key, subtitle: e.value),
                  ],
                ),
              ],
            ),
          ),
          if (onOpenInFileManager != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: Text(l10n.memberDetailOpenInFileManager),
                  onPressed: onOpenInFileManager,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.detail});
  final MemberConfigDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final source = detail.sourceLayer == MemberConfigSourceLayer.team
        ? l10n.memberDetailSourceTeam
        : l10n.memberDetailSourceRuntime;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (detail.sourceLayer == MemberConfigSourceLayer.team)
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(source),
            ),
          ),
        const SizedBox(height: 8),
        _kv('CLI', detail.cli.value),
        if (detail.provider.isNotEmpty) _kv('Provider', detail.provider),
        if (detail.model.isNotEmpty) _kv('Model', detail.model),
        _kv('CONFIG_DIR', detail.resolvedDir),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k)),
            Expanded(child: SelectableText(v)),
          ],
        ),
      );
}

class _ListTab extends StatelessWidget {
  const _ListTab({required this.items, required this.empty});
  final List<({String title, String subtitle})> items;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(empty));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) => ListTile(
        dense: true,
        title: Text(items[i].title),
        subtitle: items[i].subtitle.isEmpty ? null : Text(items[i].subtitle),
      ),
    );
  }
}
```

> Note: `RuntimeStorageContext` exposes the active filesystem via `current.filesystem`. If there is no `filesystemIsRemote` getter, replace `!RuntimeStorageContext.current.filesystemIsRemote` with a check matching `StorageRootsSnapshot.storageIsRemote` (i.e. `RuntimeStorageContext.current.filesystem is! SftpFilesystem`, importing `services/io/sftp_filesystem.dart`). Verify which exists before writing this line.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/pages/home_workspace/project/member_detail_dialog_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/project/member_detail_dialog.dart \
        client/test/pages/home_workspace/project/member_detail_dialog_test.dart
git commit -m "feat: add read-only MemberDetailDialog"
```

---

## Task 9: Wire the right-click menu into the members panel

Add `onSecondaryTapDown` / `onLongPress` to each member row, build the four-item menu, and supply callbacks + the "view detail enabled" flag from `RightToolsPanel`.

**Files:**
- Modify: `client/lib/widgets/right_tools/members_panel.dart`
- Modify: `client/lib/widgets/right_tools/right_tools_panel.dart:120-157`
- Test: `client/test/widgets/right_tools/members_panel_menu_test.dart`

- [ ] **Step 1: Write the failing widget test**

```dart
// client/test/widgets/right_tools/members_panel_menu_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/widgets/right_tools/members_panel.dart';

const _member = TeamMemberConfig(id: 'm1', name: 'Backend');
const _team = TeamConfig(id: 't', name: 'T', cli: CliTool.claude, members: [_member]);

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('right-click opens the member menu with view-detail', (tester) async {
    await tester.pumpWidget(_host(
      MembersPanel(
        team: _team,
        members: const [_member],
        memberPresence: const {},
        selectedMemberId: '',
        onSelected: (_) {},
        onOpen: (_) {},
        onLaunchAll: () {},
        canViewDetail: true,
        onViewDetail: (_) {},
        onOpenConfigDir: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(MembersPanel)),
    )!;

    await tester.tap(find.byKey(const Key('member-row-m1')),
        buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text(l10n.memberDetailViewAction), findsOneWidget);
    expect(find.text(l10n.memberDetailOpenConfigDir), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/widgets/right_tools/members_panel_menu_test.dart`
Expected: FAIL — `MembersPanel` has no `canViewDetail` / `onViewDetail` / `onOpenConfigDir` params.

- [ ] **Step 3: Extend `MembersPanel`**

In `members_panel.dart`, add imports:

```dart
import '../../l10n/app_localizations.dart';
import '../menu/sidebar_action_menu.dart';
```

Add constructor params (after `onLaunchAll`):

```dart
    required this.canViewDetail,
    required this.onViewDetail,
    required this.onOpenConfigDir,
```

Add field declarations (after `onLaunchAll`):

```dart
  /// Whether "view detail" is enabled (true when a session/tab is active).
  final bool canViewDetail;
  final ValueChanged<String> onViewDetail;
  final ValueChanged<String> onOpenConfigDir;
```

Wrap the per-row `Material(...)` (the child of the row `Container` at lines 109-143) in a `GestureDetector` that opens the menu. Replace:

```dart
                  child: Material(
                    color: selected ? cs.secondaryContainer : cs.workspaceInset,
```

with:

```dart
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (d) =>
                        _showMemberMenu(context, l10n, member, d),
                    onLongPressStart: (d) => _showMemberMenu(
                      context,
                      l10n,
                      member,
                      TapDownDetails(globalPosition: d.globalPosition),
                    ),
                    child: Material(
                    color: selected ? cs.secondaryContainer : cs.workspaceInset,
```

and add a matching extra closing `)` for the new `GestureDetector` after the `Material(...)` closes (before the row `Container`'s closing). Then add this method to the `MembersPanel` class:

```dart
  void _showMemberMenu(
    BuildContext context,
    AppLocalizations l10n,
    TeamMemberConfig member,
    TapDownDetails details,
  ) {
    showSidebarActionMenuFromSpecsAtTap<void>(
      context: context,
      tapDetails: details,
      specs: [
        SidebarActionMenuSpec.item(
          icon: Icons.info_outline,
          label: l10n.memberDetailViewAction,
          enabled: canViewDetail,
          tooltip: canViewDetail ? null : l10n.memberDetailNeedsSession,
          onAction: () => onViewDetail(member.id),
        ),
        SidebarActionMenuSpec.item(
          icon: Icons.open_in_new,
          label: l10n.openTeam,
          onAction: () => onOpen(member.id),
        ),
        SidebarActionMenuSpec.item(
          icon: Icons.folder_open,
          label: l10n.memberDetailOpenConfigDir,
          onAction: () => onOpenConfigDir(member.id),
        ),
        const SidebarActionMenuSpec.divider(),
        SidebarActionMenuSpec.item(
          icon: Icons.play_arrow,
          label: l10n.openTeam,
          onAction: onLaunchAll,
        ),
      ],
    );
  }
```

> Note: reuse an existing l10n label for "open/connect session" and "launch all" — `l10n.openTeam` is already used for the launch-all button (line 68). If a more specific existing key (e.g. a connect/open-session label) exists, prefer it; do not invent new keys beyond Task 7's set.

- [ ] **Step 4: Wire callbacks in `right_tools_panel.dart`**

Add import:

```dart
import '../../pages/home_workspace/project/member_detail_dialog.dart';
import '../../services/cli/member_config/member_config_inspector.dart';
import '../../services/io/system_folder_opener.dart';
```

In the `MembersPanel(...)` construction (lines 127-156), add after `onLaunchAll`:

```dart
            canViewDetail: chatCubit.activeTab != null,
            onViewDetail: (id) {
              final member = team.members.firstWhere((m) => m.id == id);
              final cliTeamName = chatCubit.activeTab?.cliTeamName ?? '';
              unawaited(showMemberDetailDialog(
                context,
                team: team,
                member: member,
                cliTeamName: cliTeamName,
              ));
              maybeDismissDrawer();
            },
            onOpenConfigDir: (id) {
              final member = team.members.firstWhere((m) => m.id == id);
              final cliTeamName = chatCubit.activeTab?.cliTeamName ?? '';
              unawaited(() async {
                final detail = await MemberConfigInspector().inspect(
                  team: team,
                  member: member,
                  cliTeamName: cliTeamName,
                );
                if (detail.resolvedDir.isNotEmpty) {
                  await SystemFolderOpener().reveal(detail.resolvedDir);
                }
              }());
              maybeDismissDrawer();
            },
```

> Note: confirm `chatCubit.activeTab` exposes `cliTeamName` (it does — `ChatTab.cliTeamName`, see `cubits/chat/model/chat_tab.dart`). `activeTab` is read off `chatCubit` (already in scope at `right_tools_panel.dart:81`).

- [ ] **Step 5: Run the widget test + analyzer**

Run: `cd client && flutter test test/widgets/right_tools/members_panel_menu_test.dart && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets/right_tools`
Expected: test PASS (1 test); analyzer no errors.

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/right_tools/members_panel.dart \
        client/lib/widgets/right_tools/right_tools_panel.dart \
        client/test/widgets/right_tools/members_panel_menu_test.dart
git commit -m "feat: add member row right-click menu with config detail"
```

---

## Task 10: Full verification

- [ ] **Step 1: Analyze the whole client**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors.

- [ ] **Step 2: Run the full test suite (excluding integration)**

Run: `cd client && flutter test --exclude-tags integration`
Expected: all tests pass, including the six new test files.

- [ ] **Step 3: Manual golden-path check (document result)**

In a team-mode project: open a session, right-click a member → "查看成员详情" shows the dialog with Overview/Skills/MCP/Plugins/Settings; before launching the member, the banner reads "团队层配置"; "在文件管理器中打开" opens the resolved CONFIG_DIR. With no active session, "查看成员详情" is disabled with the tooltip. Note the outcome in the PR description.

- [ ] **Step 4: Commit any analyzer/test fixups**

```bash
git add -A && git commit -m "chore: member config detail verification fixups"
```

---

## Self-Review

**Spec coverage:**
- 右键菜单四项 → Task 9 (view detail / open-connect / open config dir / launch all). ✓
- 数据来源：运行目录优先回退团队层 → Task 4 `_resolveDir`. ✓
- 弹窗对话框 + 标签页 → Task 8. ✓
- 只读 + 打开目录/跳转 → Task 8 footer + Task 9 `onOpenConfigDir`; `SystemFolderOpener` Task 5. ✓
- 服务 + 每 CLI 能力钩子 → Tasks 2-4. ✓
- "查看详情"启用条件 = activeTab != null → Task 9 `canViewDetail`. ✓
- 错误处理：缺失目录空状态 / 分区告警 / 远端禁用 reveal → Task 4 (none), Task 2 (per-section warnings), Task 8 (`_canRevealLocally`). ✓
- 测试：inspector / capability / cubit / dialog / menu → Tasks 2,4,6,8,9. ✓
- l10n en+zh + warmup glyphs → Task 7. ✓

**Type consistency:** `MemberConfigDetail`, `MemberConfigContext`, `MemberConfigSourceLayer`, `MemberConfigInspectionCapability.inspect`, `MemberConfigInspector.inspect({team, member, cliTeamName})`, `MemberConfigCubit.load(...)`, `SystemFolderOpener.reveal(...)`, and the `MembersPanel` new params (`canViewDetail`/`onViewDetail`/`onOpenConfigDir`) are used identically across tasks. ✓

**Open verification flags (intentional — engineer confirms against codebase):** const-constructor params for `TeamConfig`/`TeamMemberConfig` in tests; logger symbol/path (`appLogger`); `RuntimeStorageContext` remote-filesystem getter name; whether a more specific l10n key than `openTeam` exists for "open session"/"launch all". Each is called out inline at its task.
