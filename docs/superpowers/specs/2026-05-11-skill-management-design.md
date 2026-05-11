# Skill Management Design

> Date: 2026-05-11 | Status: Draft

## 1. Overview

Add a skill management feature to FlashskyAI UI, modeled after cc-switch's unified skill management. Skills are Claude-style `SKILL.md` directories, stored in a Single Source of Truth (SSOT) directory and symlinked into `~/.flashskyai/skills/`.

## 2. Sidebar Navigation

A new `_SkillManagerTile` is added at the **top** of the `ContextSidebar` Column, above `_TeamSelector`. It navigates to `/skills`.

```
_SkillManagerTile        ← NEW (topmost)
_TeamSelector
_TeamConfigTile
_SidebarSectionTitle("Projects")
_ProjectList
Divider + _SettingsTile
```

## 3. Data Model

### Skill

```dart
class Skill {
  String id;           // "owner/repo:directory" or "local:directory"
  String name;         // from SKILL.md frontmatter
  String description;  // from SKILL.md frontmatter
  String directory;    // subdirectory name in SSOT
  String? repoOwner;
  String? repoName;
  String? repoBranch;
  String? readmeUrl;
  bool enabled;        // enabled for FlashskyAI
  int installedAt;     // unix timestamp
  String? contentHash; // SHA-256 for update detection
  int updatedAt;
}
```

### SkillRepo

```dart
class SkillRepo {
  String owner;
  String name;
  String branch;
  bool enabled;
}
```

### DiscoverableSkill

```dart
class DiscoverableSkill {
  String key;          // "owner/name:directory"
  String name;
  String description;
  String directory;
  String? readmeUrl;
  String repoOwner;
  String repoName;
  String repoBranch;
}
```

## 4. Storage

```
AppStorage.flashskyaiDir/
  ├── skills/              ← SSOT (each subdirectory contains SKILL.md)
  │   ├── example-skill/
  │   │   └── SKILL.md
  │   └── ...
  ├── skills.json          ← manifest cache (skills + repos + discoverable cache)
  └── skill-backups/       ← uninstall backups (last 20)
```

```
~/.flashskyai/skills/      ← plugin dir
  └── example-skill → symlink to SSOT
```

- **SSOT**: `AppStorage.flashskyaiDir/skills/` — canonical skill directories
- **Manifest cache**: `skills.json` — serialized `List<Skill>` + `List<SkillRepo>` for fast reads without filesystem scanning
- **Symlinks**: `~/.flashskyai/skills/<name>` → SSOT directory (created on enable, removed on disable)
- **Backups**: ZIP archives in `skill-backups/`, max 20 retained

## 5. Architecture

```
UI Layer (Flutter Widgets)
  ├── SkillManagementPage     (installed skills list)
  ├── SkillDiscoveryPage      (discover + install)
  └── RepoManagementPage      (repo CRUD)

State Layer (Cubit)
  └── SkillCubit              (state: skills, discoverable, repos, loading/error)

Service Layer (Dart)
  ├── SkillService            (install, uninstall, toggle, discover, update, scan, backup/restore)
  └── SkillRepoService        (repo CRUD, default seed)

Storage Layer
  ├── skills.json             (manifest cache)
  ├── SSOT filesystem         (AppStorage.flashskyaiDir/skills/)
  └── Symlink manager         (~/.flashskyai/skills/ symlinks)
```

## 6. SkillService Methods

| Method | Purpose |
|--------|---------|
| `install(DiscoverableSkill)` | Download repo ZIP → extract → copy to SSOT → save to cache → create symlink |
| `uninstall(String id)` | Remove symlink → remove from SSOT → remove from cache → create backup |
| `toggle(String id, bool enabled)` | Update cache → create or remove symlink |
| `discoverAvailable()` | Parallel fetch from enabled repos → scan for SKILL.md → return discoverable list |
| `checkUpdates()` | Download repos → compare content hashes → return update info |
| `updateSkill(String id)` | Re-download → backup old → replace SSOT → re-symlink |
| `scanUnmanaged()` | Scan `~/.flashskyai/skills/` for dirs not in cache |
| `importUnmanaged(List<String> dirs)` | Copy to SSOT → add to cache → create symlinks |
| `installFromZip(String zipPath)` | Extract ZIP → scan for SKILL.md → install |
| `restoreBackup(String backupId)` | Extract backup ZIP → restore to SSOT + cache |

## 7. Default Repos

Seeded on first launch (matching cc-switch):

- `anthropics/skills` (main)
- `ComposioHQ/awesome-claude-skills` (master)
- `cexll/myclaude` (master)
- `JimLiu/baoyu-skills` (main)

## 8. UI Pages

### Skill Management Page (`/skills`)

- Header with title + action buttons: Discover, Import, Install from ZIP, Check Updates, Restore Backup
- List of installed skills, each row showing: name, description, source repo, enabled toggle, uninstall button

### Skill Discovery Page (`/skills/discover`)

- Search bar + repo filter dropdown
- Two sources: configured repos (default) and skills.sh public API
- Grid of `SkillCard` widgets showing: name, description, directory, repo badge, install/uninstall button, "View on GitHub" link

### Repo Management Page (`/skills/repos`)

- Add repo form (URL + branch)
- Repo list with remove buttons

## 9. Routing

Added to existing `ShellRoute`:

```dart
GoRoute(path: '/skills', ...),           // SkillManagementPage
GoRoute(path: '/skills/discover', ...),   // SkillDiscoveryPage
GoRoute(path: '/skills/repos', ...),      // RepoManagementPage
```

## 10. File Plan

| File | Purpose |
|------|---------|
| `client/lib/models/skill.dart` | Skill, SkillRepo, DiscoverableSkill models |
| `client/lib/services/skill_service.dart` | SkillService — core business logic |
| `client/lib/services/skill_repo_service.dart` | SkillRepoService — repo CRUD |
| `client/lib/cubits/skill_cubit.dart` | SkillCubit — state management |
| `client/lib/pages/skill_management_page.dart` | Installed skills management page |
| `client/lib/pages/skill_discovery_page.dart` | Discovery + install page |
| `client/lib/pages/skill_repo_page.dart` | Repo management page |
| `client/lib/widgets/context_sidebar.dart` | Add _SkillManagerTile |
| `client/lib/router/app_router.dart` | Add skill routes |
| `client/lib/l10n/*.arb` | Localization strings |

## 11. Error Handling

Structured error types with i18n keys:

- `SKILL_NOT_FOUND`
- `DOWNLOAD_FAILED`
- `DOWNLOAD_TIMEOUT`
- `SKILL_DIR_NOT_FOUND`
- `EMPTY_ARCHIVE`
- `SKILL_ALREADY_INSTALLED`
- `SYMLINK_FAILED`
- `BACKUP_FAILED`
