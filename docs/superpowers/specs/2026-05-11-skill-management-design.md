# Skill Management — Design

> Date: 2026-05-11
> Status: approved
> Scope: FlashskyAI client (Flutter). Adds a global skill management surface with
> install/uninstall/update/discover flows, mirroring the cc-switch feature set.

## 1. Goals

Provide a UI for the FlashskyAI client to manage Skill packages independently
of any team or project. Equivalent feature surface to cc-switch:

- List installed Skills with enable toggle, uninstall, update.
- Discover Skills from GitHub repos (`SkillRepo`) and from the public
  `skills.sh` search index.
- Manage the repo list (add / remove / enable).
- Install from local ZIP.
- Scan filesystem for unmanaged Skills and import them into the manifest.
- Backup uninstalled Skills and restore on demand.
- Check for and apply updates from upstream `SKILL.md`.

Skill files are stored globally in the app's support directory; per-team
scoping is out of scope (will be revisited later).

## 2. On-disk layout

All paths are rooted at `AppStorage.flashskyaiDir`
(`<applicationSupportDirectory>/flashskyai/`).

```
flashskyai/
├── skills.json                    # existing — repo list (SkillRepoService)
├── skills/
│   ├── manifest.json              # NEW — installed skill index
│   ├── <skill-name>/              # actual skill payload
│   │   ├── SKILL.md
│   │   └── ...
│   └── ...
└── skill-backups/                 # uninstalled / pre-update payloads
    └── <skill-name>-<unixSeconds>/
        └── ...
```

`manifest.json` schema:

```json
{
  "version": 1,
  "skills": [ /* Skill.toJson() entries */ ],
  "backups": [ /* SkillBackup.toJson() entries */ ]
}
```

Backup retention: keep newest 20 entries across all skills. Oldest backups
beyond the limit are deleted from disk on next mutation.

## 3. Data model

Reuses existing [skill.dart](../../client/lib/models/skill.dart) types
(`Skill`, `SkillRepo`, `DiscoverableSkill`). Additions:

- `SkillUpdateInfo { id, name, currentHash?, remoteHash }`
- `SkillBackup { backupId, backupPath, createdAt, skill: Skill }`
- `UnmanagedSkill { directory, name, description?, path }`
- `SkillsShEntry { key, name, directory, repoOwner, repoName, repoBranch, readmeUrl?, installs }`

Identity rules:

- `Skill.id` format: `<repoOwner>/<repoName>:<directory-basename>` when sourced
  from a repo, else `local:<directory-basename>`.
- Discovery dedup key: `<directory-basename>:<repoOwner>:<repoName>` (case
  insensitive). Matches cc-switch.
- Content hash: SHA-256 of the `SKILL.md` file contents at install time, used
  for update detection.

The pre-existing single-app `enabled: bool` field replaces cc-switch's
per-app `SkillApps` map. We are one app.

## 4. Service layer

Path: `client/lib/services/`.

| Service | Responsibility |
|---|---|
| `SkillRepoService` (existing) | Persist enabled `SkillRepo` list in `skills.json`. Add `setEnabled(owner, name, enabled)` and `branch` mutation helpers. |
| `SkillManifestService` (new) | Read/write `skills/manifest.json`. CRUD for `Skill` and `SkillBackup`. |
| `SkillFetchService` (new) | GitHub tarball download + `archive` extraction. Parses `SKILL.md` YAML frontmatter. In-memory cache of decoded tarballs keyed by `(owner, name, branch)` for 1 hour. |
| `SkillInstallService` (new) | Composes Fetch + Manifest. Implements install, uninstall, update, restore, scan-unmanaged, install-from-zip. Calculates content hashes. Handles backup rotation. |
| `SkillsShService` (new) | HTTP GET to `https://skills.sh/api/search?q=&limit=&offset=`. Filters non-GitHub `source` values (those containing `.` in owner or repo). |
| `SkillRepository` (new) | Thin facade aggregating the four services for the cubit. Mirrors `SessionRepository` style. |

### 4.1 SKILL.md frontmatter parser

Minimal hand-rolled YAML reader — only fields needed: `name`, `description`,
`webServer` (passthrough as JSON map). Frontmatter is delimited by `---` lines
at the top of the file. Unsupported nested YAML structures other than
`webServer` may be ignored. Invalid frontmatter → reject skill with named
exception.

### 4.2 GitHub tarball flow

1. URL: `https://codeload.github.com/{owner}/{name}/tar.gz/{branch}`
2. Stream into `archive.GZipDecoder` → `TarDecoder` (use `package:archive`).
3. Top-level entries have prefix `{name}-{branch-sha-or-branch}/`. Strip it.
4. A "skill" = any top-level subdirectory containing `SKILL.md`.
5. For discovery: only parse `SKILL.md` files; do not write to disk.
6. For install: write the chosen subdirectory's entire tree to
   `skills/<basename>/`.

Network errors, non-200 responses, decode errors → throw
`SkillFetchException(reason, repo)`.

### 4.3 skills.sh

GET `https://skills.sh/api/search` returns
`{ skills: [{ id, name, skillId, source, installs, ... }], count, query }`.
Split `source` on `/`; require exactly `<owner>/<repo>` with no dots in either
half (drops non-GitHub mirrors). Map to `SkillsShEntry`. Branch defaults to
`main`; install will fall back to `master` if 404 on tarball fetch.

## 5. State layer

Single `SkillCubit` (path `client/lib/cubits/skill_cubit.dart`) holds:

```dart
class SkillState {
  final List<Skill> installed;
  final List<SkillRepo> repos;
  final List<DiscoverableSkill> discoverable;     // aggregated across repos
  final List<SkillUpdateInfo> updates;
  final List<SkillBackup> backups;
  final SkillsShSearch? skillsShSearch;            // last query + accumulated results + nextOffset
  final SkillLoadStatus status;                    // idle | loading | ready | error
  final String? errorMessage;
  final Set<String> busyIds;                       // per-skill in-flight ops
}
```

Methods (each returns `Future<void>` and surfaces errors via state):
`loadAll`, `refreshInstalled`, `refreshDiscoverable`, `refreshBackups`,
`addRepo`, `removeRepo`, `toggleRepo`, `installFromDiscovery`,
`installFromZip`, `installFromSkillsSh`, `uninstall`, `toggleSkillEnabled`,
`checkUpdates`, `updateSkill`, `updateAll`, `restoreBackup`, `deleteBackup`,
`scanUnmanaged`, `importUnmanaged`, `searchSkillsSh(query, reset)`,
`loadMoreSkillsSh`.

Wired in `main.dart` via `BlocProvider` alongside the existing cubits. Triggers
`loadAll()` on construction.

## 6. UI

### 6.1 Sidebar entry

In [context_sidebar.dart](../../client/lib/widgets/context_sidebar.dart) `build`,
insert a `_SkillTile` immediately above `_TeamSelector`. Same visual style as
`_TeamConfigTile`. Icon: `Icons.auto_awesome_outlined`. Tap → `context.go('/skills')`.

### 6.2 Route

Add to [app_router.dart](../../client/lib/router/app_router.dart):

```dart
GoRoute(
  path: '/skills',
  pageBuilder: (_, __) => const NoTransitionPage(child: SkillManagementPage()),
),
```

### 6.3 SkillManagementPage layout

Reuses the `_TitleBar + _NavPanel + content` skeleton from
[team_config_page.dart](../../client/lib/pages/team_config_page.dart).
TitleBar: localized `Skills` / `Manage installable skills`.

Left nav sections (`enum SkillSection`): `Installed` (default), `Discovery`,
`Repos`, `Backups`.

### 6.4 Installed section

- Header row: `N installed` + actions: `Import from disk`, `Install from ZIP`,
  `Check updates`. `Update all (N)` appears only when `updates.isNotEmpty`.
- List of `_InstalledSkillRow`:
  - name · external link icon (if readmeUrl) · source badge (`repoOwner/repoName`
    or `local`) · update available badge (when applicable)
  - description (truncated)
  - enable Switch (calls `toggleSkillEnabled`)
  - per-row hover actions: `Update` (if has update), `Uninstall`
- Empty state: icon + message + link "Go to Discovery".

### 6.5 Discovery section

- Top: segmented control `Repos` | `skills.sh`.
- Repos mode:
  - Search input (filter by name / repo)
  - Repo dropdown (filter by `owner/name`)
  - Status dropdown (`all` / `installed` / `uninstalled`)
  - 3-column responsive grid of `_SkillCard` (cc-switch parity).
  - Card: name, description, source, `Install` / `Installed ✓` button,
    optional external link.
- skills.sh mode:
  - Search input (`≥ 2` chars to submit; Enter or button)
  - Same card grid; cards show `installs` count
  - `Load more` button when `accumulated < totalCount`
  - Footer attribution `Powered by skills.sh`.
- If no repos are configured and source is `repos`, auto-switch to `skills.sh`
  and show an inline "Add a repo" hint.

### 6.6 Repos section

- Add form: three fields `owner`, `name`, `branch` (default `main`) + `Add`
  button. Validates non-empty owner/name.
- List rows: `owner/name @ branch` · enable Switch · `Remove`.
- Empty state: prompts user to add a repo.

### 6.7 Backups section

- List of `_BackupRow`: name, original directory chip, description, createdAt
  (localized), full path. Buttons: `Restore`, `Delete`.
- Empty state: `No backups yet`.

### 6.8 Dialogs

- Confirm uninstall / delete-backup / overwrite-on-install: `AlertDialog`
  matching the style of `_confirmDeleteProject` in `context_sidebar.dart`.
- Import unmanaged: full-screen `Dialog` listing scanned skills, checkboxes per
  skill, `Import selected` button.

### 6.9 Feedback

All success/error messages go through `ScaffoldMessenger.showSnackBar` (the
existing project pattern — no toast library is introduced). Long messages use
`SnackBarAction` with `Dismiss` so the user can clear them.

## 7. i18n

New keys under `skills.*` added to both `app_en.arb` and `app_zh.arb`, then
`flutter gen-l10n` is run to regenerate
[app_localizations.dart](../../client/lib/l10n/app_localizations.dart).
Key groups:

- `skillsTitle`, `skillsSubtitle`, `skillsSidebarLabel`
- `skillsNavInstalled`, `skillsNavDiscovery`, `skillsNavRepos`, `skillsNavBackups`
- `skillsInstalledCount`, `skillsCheckUpdates`, `skillsUpdateAll(count)`,
  `skillsImportFromDisk`, `skillsInstallFromZip`
- `skillsSourceRepos`, `skillsSourceSkillsSh`, `skillsSearchPlaceholder`,
  `skillsFilterRepoAll`, `skillsFilterStatusAll/Installed/Uninstalled`
- `skillsCardInstall`, `skillsCardInstalled`, `skillsCardSourceLocal`
- `skillsReposEmpty`, `skillsRepoAdd`, `skillsRepoOwner`, `skillsRepoName`,
  `skillsRepoBranch`, `skillsRepoRemoveConfirm(name)`
- `skillsBackupsEmpty`, `skillsBackupRestore`, `skillsBackupDelete`,
  `skillsBackupDeleteConfirm(name)`
- `skillsErrorFetch`, `skillsErrorInstall`, `skillsErrorParse`,
  `skillsInstallSuccess(name)`, `skillsUninstallSuccess(name)`,
  `skillsUpdateSuccess(name)`

## 8. Operations — sequence detail

### 8.1 Discovery refresh

1. `SkillCubit.refreshDiscoverable()` → for each enabled `SkillRepo`,
   `SkillFetchService.listSkills(repo)` runs concurrently (`Future.wait`).
2. Each call: fetch tarball (or read from 1-hour memory cache) → iterate
   entries → for every subdirectory containing `SKILL.md`, parse frontmatter,
   build `DiscoverableSkill`.
3. Merge results; dedup by key `directory:owner:repo`.
4. On any per-repo failure, that repo's contribution is dropped and an entry is
   added to `state.errorMessage` (non-fatal — other repos still render).

### 8.2 Install (from Discovery)

1. Confirm overwrite if `skills/<basename>/` already exists.
2. Re-fetch tarball if cached bytes evicted; extract only the target
   subdirectory tree → write to `skills/<basename>/`.
3. Compute SHA-256 of `SKILL.md` → `contentHash`.
4. Build `Skill` row (id = `owner/repo:basename`, repo fields set, `enabled: true`,
   timestamps now). Append to `manifest.json`.
5. Emit cubit state update; snackbar success.

### 8.3 Install from ZIP

1. `file_picker.pickFiles(allowedExtensions: ['zip'])`.
2. Decode with `archive.ZipDecoder`. Find every directory containing
   `SKILL.md`.
3. For each found, treat as `local` install (no repo info). Reuse the install
   flow's write step.
4. Report `installed.length` in snackbar.

### 8.4 Uninstall

1. Confirm dialog.
2. Move `skills/<basename>/` → `skill-backups/<basename>-<unixSeconds>/`
   (atomic rename when same filesystem; fall back to copy+delete).
3. Append `SkillBackup` to manifest, remove `Skill` entry.
4. Run retention: while `backups.length > 20`, delete oldest from disk and
   manifest.
5. Snackbar with backup path.

### 8.5 Check updates

For each installed skill with `repoOwner != null`:

1. `GET https://raw.githubusercontent.com/{owner}/{name}/{branch}/{basename}/SKILL.md`.
   Resolve via `skill.directory`; the manifest stores the exact in-repo
   subpath at install time.
2. Compute SHA-256 of the response body.
3. If `remoteHash != skill.contentHash`, append `SkillUpdateInfo` to `state.updates`.
4. 404 → skill flagged as `update.unknown` (logged, not surfaced as an error).

### 8.6 Update single skill

1. Back up the current `skills/<basename>/` (same as uninstall).
2. Run the install flow's write step against the same target path.
3. Update `manifest.json` row in place (new `contentHash`, `updatedAt`); do not
   create a new entry.
4. Drop the matching `SkillUpdateInfo` from `state.updates`.

### 8.7 Scan unmanaged

1. List `skills/*` subdirectories.
2. For each subdir whose path is not in `manifest.json` AND contains
   `SKILL.md`: read frontmatter → produce `UnmanagedSkill`.
3. User picks which to import; selected ones get manifest entries with
   `local:<basename>` IDs and `repoOwner = null`. Files are not moved.

### 8.8 Restore backup

1. Confirm.
2. Move `skill-backups/<id>/` → `skills/<basename>/` (rename, fall back to
   copy+delete). If target exists, fail with prompt to uninstall first.
3. Insert the backup's `Skill` row back into manifest (with fresh
   `updatedAt`); remove from `backups`.

## 9. Error model

All service methods throw named exceptions:

```dart
class SkillException implements Exception { final String message; final Object? cause; }
class SkillFetchException extends SkillException {}     // network / GitHub
class SkillParseException extends SkillException {}     // SKILL.md / YAML
class SkillInstallException extends SkillException {}   // filesystem
class SkillManifestException extends SkillException {}  // manifest IO
```

The cubit catches these, logs via `appLogger`, and surfaces a localized
message. The page binds to `state.errorMessage` and shows a `SnackBar` on
change (cleared after display).

## 10. Out of scope

- Per-team / per-project skill scoping. Skills are global only.
- Symlink-based installation into a runtime path (`/install-skill` semantics).
  We just store payloads in `skills/`. Wiring up a downstream runtime consumer
  is a separate task.
- Skill execution / `webServer` lifecycle.
- Authentication for GitHub API (we use codeload + raw.githubusercontent.com
  which have generous unauthenticated quotas).
- Diff view of skill content between versions.

## 11. File-touch summary

New files:

- `client/lib/services/skill_manifest_service.dart`
- `client/lib/services/skill_fetch_service.dart`
- `client/lib/services/skill_install_service.dart`
- `client/lib/services/skills_sh_service.dart`
- `client/lib/repositories/skill_repository.dart`
- `client/lib/cubits/skill_cubit.dart`
- `client/lib/pages/skill_management_page.dart`
- Test files mirror these under `client/test/`.

Modified:

- `client/lib/models/skill.dart` — add `SkillUpdateInfo`, `SkillBackup`,
  `UnmanagedSkill`, `SkillsShEntry`. Existing types unchanged.
- `client/lib/services/skill_repo_service.dart` — add `setEnabled`/`updateBranch`.
- `client/lib/widgets/context_sidebar.dart` — insert `_SkillTile` above
  `_TeamSelector`.
- `client/lib/router/app_router.dart` — add `/skills` route.
- `client/lib/main.dart` — register `SkillCubit` in `MultiBlocProvider`.
- `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb` — new `skills.*`
  keys; regenerate `app_localizations*.dart`.
