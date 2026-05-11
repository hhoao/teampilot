# Team Config Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move team configuration out of Settings into its own standalone page, accessible from the left sidebar under the team selector.

**Architecture:** Remove `ConfigSection.team` from the settings enum, move `TeamConfigWorkspace` to a new `TeamConfigPage`, add a "Team Config" nav tile in the sidebar above sessions, and update routes accordingly.

**Tech Stack:** Flutter/Dart, flutter_bloc, go_router

---

### Task 1: Add `teamConfig` localization string

**Files:**
- Modify: `client/lib/l10n/app_localizations.dart`

- [ ] **Step 1: Add getter property**

Add after `configure` getter (line 30):

```dart
  String get teamConfig => _strings['teamConfig']!;
```

- [ ] **Step 2: Add _strings entry**

In the `_strings` map (around line 165, near `configure`), add:

```dart
    'teamConfig': {'en': 'Team Config', 'zh': '团队配置'},
```

- [ ] **Step 3: Commit**

```bash
git add client/lib/l10n/app_localizations.dart
git commit -m "feat(l10n): add teamConfig localization string"
```

---

### Task 2: Remove `team` from ConfigSection enum

**Files:**
- Modify: `client/lib/cubits/config_cubit.dart`

- [ ] **Step 1: Update ConfigSection enum**

Change line 6 from:
```dart
enum ConfigSection { team, members, layout, llm }
```
to:
```dart
enum ConfigSection { members, layout, llm }
```

- [ ] **Step 2: Update default section**

Change line 10 from:
```dart
  const ConfigState({this.section = ConfigSection.team, this.selectedMemberId = ''});
```
to:
```dart
  const ConfigState({this.section = ConfigSection.layout, this.selectedMemberId = ''});
```

- [ ] **Step 3: Update switch expressions**

Replace the `title` getter switch (lines 15-20):
```dart
  String get title => switch (section) {
        ConfigSection.members => 'Member Configuration',
        ConfigSection.layout => 'Layout Configuration',
        ConfigSection.llm => 'LLM Configuration',
      };

  String get breadcrumb => switch (section) {
        ConfigSection.members => 'Config / Members',
        ConfigSection.layout => 'Config / Layout',
        ConfigSection.llm => 'Config / LLM',
      };
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/cubits/config_cubit.dart
git commit -m "refactor(config): remove team from ConfigSection, default to layout"
```

---

### Task 3: Create standalone TeamConfigPage

**Files:**
- Create: `client/lib/pages/team_config_page.dart`

- [ ] **Step 1: Write the new page file**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/team_config.dart';
import '../services/launch_command_builder.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';

class TeamConfigPage extends StatelessWidget {
  const TeamConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      key: AppKeys.teamConfigWorkspace,
      color: colors.workspaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBar(
            title: l10n.teamConfig,
            subtitle: l10n.editTeamSubtitle,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 36, 44, 28),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: _TeamConfigForm(team: team),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamConfigForm extends StatefulWidget {
  const _TeamConfigForm({required this.team});

  final TeamConfig team;

  @override
  State<_TeamConfigForm> createState() => _TeamConfigFormState();
}

class _TeamConfigFormState extends State<_TeamConfigForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _directoryController;
  late final TextEditingController _extraArgsController;
  String _teamId = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _directoryController = TextEditingController();
    _extraArgsController = TextEditingController();
    _syncFromTeam();
  }

  @override
  void didUpdateWidget(covariant _TeamConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.team.id != _teamId) {
      _syncFromTeam();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _directoryController.dispose();
    _extraArgsController.dispose();
    super.dispose();
  }

  void _syncFromTeam() {
    _teamId = widget.team.id;
    _nameController.text = widget.team.name;
    _directoryController.text = widget.team.workingDirectory;
    _extraArgsController.text = widget.team.extraArgs;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(title: l10n.teamSettings, subtitle: l10n.editTeamSubtitle),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.builder(
            itemCount: widget.team.members.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _SizedField(
                          child: TextField(
                            key: AppKeys.teamNameField,
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: l10n.teamName,
                              prefixIcon: const Icon(Icons.badge_outlined),
                            ),
                          ),
                        ),
                        _SizedField(
                          child: TextField(
                            key: AppKeys.workingDirectoryField,
                            controller: _directoryController,
                            decoration: InputDecoration(
                              labelText: l10n.workingDirectory,
                              prefixIcon: const Icon(
                                Icons.folder_open_outlined,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: AppKeys.extraArgsField,
                      controller: _extraArgsController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: l10n.teamExtraArgs,
                        hintText: l10n.teamExtraArgsHint,
                        prefixIcon: const Icon(Icons.terminal_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.memberLaunchOrder,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textBase,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              }
              final memberIndex = index - 1;
              return _LaunchOrderRow(
                index: memberIndex,
                team: widget.team,
                member: widget.team.members[memberIndex],
                controller: context.read<TeamCubit>(),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: AppKeys.saveButton,
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.save),
            ),
            Text(
              context.read<TeamCubit>().state.statusMessage,
              style: TextStyle(color: textBase.withValues(alpha: 0.66)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() {
    return context.read<TeamCubit>().updateSelected(
      widget.team.copyWith(
        name: _nameController.text,
        workingDirectory: _directoryController.text,
        extraArgs: _extraArgsController.text,
      ),
    );
  }
}

class _LaunchOrderRow extends StatelessWidget {
  const _LaunchOrderRow({
    required this.index,
    required this.team,
    required this.member,
    required this.controller,
  });

  final int index;
  final TeamConfig team;
  final TeamMemberConfig member;
  final TeamCubit controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text('${index + 1}')),
          Expanded(child: Text(member.name)),
          IconButton(
            key: AppKeys.memberOpenButton(member.id),
            tooltip: l10n.openMember,
            onPressed: () => controller.launchMember(member.id),
            icon: const Icon(Icons.open_in_new),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              LaunchCommandBuilder.preview(team, member),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: colors.workspaceBackground,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textBase,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textBase.withValues(alpha: 0.66),
              fontSize: 14,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textBase,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(color: textBase.withValues(alpha: 0.64)),
        ),
      ],
    );
  }
}

class _SizedField extends StatelessWidget {
  const _SizedField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 360, child: child);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add client/lib/pages/team_config_page.dart
git commit -m "feat: add standalone TeamConfigPage"
```

---

### Task 4: Remove team config from Settings page

**Files:**
- Modify: `client/lib/pages/config_workspace.dart`

- [ ] **Step 1: Remove TeamConfigWorkspace class (lines 115-276)**

Delete the entire `TeamConfigWorkspace` class and `_TeamConfigWorkspaceState` (from line 115 to line 276).

- [ ] **Step 2: Remove _LaunchOrderRow class (lines 729-778)**

Delete the entire `_LaunchOrderRow` class (from line 729 to line 778).

- [ ] **Step 3: Remove ConfigSection.team switch case**

In `ConfigWorkspace.build`, change lines 87-97 from:
```dart
                                child: switch (configCubit.state.section) {
                                  ConfigSection.team => TeamConfigWorkspace(
                                    team: team,
                                  ),
                                  ConfigSection.members =>
                                    MemberConfigWorkspace(team: team),
                                  ConfigSection.layout =>
                                    const LayoutConfigWorkspace(),
                                  ConfigSection.llm =>
                                    const LlmConfigWorkspace(),
                                },
```
to:
```dart
                                child: switch (configCubit.state.section) {
                                  ConfigSection.members =>
                                    MemberConfigWorkspace(team: team),
                                  ConfigSection.layout =>
                                    const LayoutConfigWorkspace(),
                                  ConfigSection.llm =>
                                    const LlmConfigWorkspace(),
                                },
```

- [ ] **Step 4: Remove team nav item from _ConfigNavPanel**

In `_ConfigNavPanel.build`, remove lines 955-962:
```dart
          _ConfigNavItem(
            key: AppKeys.configTeamSectionButton,
            title: l10n.teamSettings,
            icon: Icons.groups_2_outlined,
            compact: compact,
            selected: section == ConfigSection.team,
            onTap: () => onSelectSection(ConfigSection.team),
          ),
```

- [ ] **Step 5: Clean up unused imports**

Remove unused imports at top of file. `LaunchCommandBuilder` is used by `_LaunchOrderRow` (being deleted) and by `MemberConfigWorkspace` (stays). Check: `team_config.dart` import — `TeamConfig` is used by `MemberConfigWorkspace`, keep it. Remove `perf.dart` if no longer used.

Actually, verify carefully:
- `launch_command_builder.dart` — still used by `MemberConfigWorkspace` (line 456: `LaunchCommandBuilder.preview`), keep
- `team_config.dart` — `TeamConfig` used by `MemberConfigWorkspace`, `TeamMemberConfig` used, keep
- `perf.dart` — `FramePerf.mark` used in `_ConfigNavPanel.onSelect` and `PipelinePerf`/`BuildPerf` in ConfigWorkspace.build, keep

No import changes needed.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/config_workspace.dart
git commit -m "refactor: remove team config section from Settings page"
```

---

### Task 5: Update sidebar navigation

**Files:**
- Modify: `client/lib/widgets/context_sidebar.dart`

- [ ] **Step 1: Add _TeamConfigTile between team selector and session list**

In `_ContextSidebarState.build`, after the `SizedBox(height: 14)` following `_TeamSelector` (line 61), add:

```dart
                  _TeamConfigTile(
                    onTap: () {
                      FramePerf.mark('nav team config');
                      context.go('/team-config');
                    },
                  ),
                  const SizedBox(height: 14),
```

- [ ] **Step 2: Change _SettingsTile navigation**

Change line 78 from:
```dart
                      context.go('/config/team');
```
to:
```dart
                      context.go('/config/layout');
```

Also update the log message on line 80 from:
```dart
                      appLogger.d(
                        '[perf] context.go /config/team: ${sw.elapsedMilliseconds}ms',
                      );
```
to:
```dart
                      appLogger.d(
                        '[perf] context.go /config/layout: ${sw.elapsedMilliseconds}ms',
                      );
```

- [ ] **Step 3: Add _TeamConfigTile widget**

Add after `_SettingsTile` class (after line 194):

```dart
class _TeamConfigTile extends StatelessWidget {
  const _TeamConfigTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.groups_2_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(
                context.l10n.teamConfig,
                style: TextStyle(fontWeight: FontWeight.w700, color: textBase),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Wait — `context.l10n` requires the extension import. Since the file already imports `../l10n/app_localizations.dart`, this will work. But `_TeamConfigTile` is a StatelessWidget with `context` available in `build`, so `context.l10n` is fine. Actually, to keep consistent with `_SettingsTile` which uses a hardcoded `'Settings'` string, let me check — `_SettingsTile` hardcodes `'Settings'` instead of using l10n. We should use l10n for the new tile. Let me use `context.l10n.teamConfig`.

Actually, looking at `_SettingsTile` more carefully — it hardcodes `'Settings'` (line 185) instead of using `l10n.settings`. That's an existing inconsistency. For the new tile, let's use `l10n.teamConfig` properly.

But wait — `_TeamConfigTile` needs to be a StatelessWidget that takes no extra params besides `onTap`. To use l10n, I access it via `context.l10n` in the build method. That works.

Actually wait — I should double check. The `BuildContextL10n` extension is defined in `app_localizations.dart`. The current file imports `../l10n/app_localizations.dart`, so `context.l10n` is available. Good.

But hmm, I should also add an AppKey for this tile. Let me add it.

- [ ] **Step 4: Commit**

```bash
git add client/lib/widgets/context_sidebar.dart
git commit -m "feat: add Team Config nav tile to sidebar, redirect settings to layout"
```

---

### Task 6: Update routes

**Files:**
- Modify: `client/lib/router/app_router.dart`

- [ ] **Step 1: Add import for TeamConfigPage**

Add after the config_workspace import (line 8):
```dart
import '../pages/team_config_page.dart';
```

- [ ] **Step 2: Remove /config/team route**

Delete lines 61-66:
```dart
        GoRoute(
          path: '/config/team',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ConfigWorkspace(section: ConfigSection.team),
          ),
        ),
```

- [ ] **Step 3: Change /config redirect**

Change line 60 from:
```dart
        GoRoute(path: '/config', redirect: (context, state) => '/config/team'),
```
to:
```dart
        GoRoute(path: '/config', redirect: (context, state) => '/config/layout'),
```

- [ ] **Step 4: Add /team-config route**

Add a new route after the `/config/llm` route (after line 84):
```dart
        GoRoute(
          path: '/team-config',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: TeamConfigPage(),
          ),
        ),
```

- [ ] **Step 5: Clean up unused import**

The import `'../cubits/config_cubit.dart'` is still needed — `ConfigSection.members`, `ConfigSection.layout`, `ConfigSection.llm` are used in route paths. Keep.

- [ ] **Step 6: Commit**

```bash
git add client/lib/router/app_router.dart
git commit -m "feat: add /team-config route, remove /config/team, redirect /config to /config/layout"
```

---

### Task 7: Verify build

**Files:**
- None (verification only)

- [ ] **Step 1: Run Flutter analyze**

```bash
cd client && flutter analyze
```

Expected: No errors.

- [ ] **Step 2: Fix any issues**

If the analyzer reports errors, fix them (likely unused imports in config_workspace.dart or missing imports).

- [ ] **Step 3: Run Flutter build**

```bash
cd client && flutter build linux --debug
```

Expected: Build succeeds.
