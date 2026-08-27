# TeamPilot resources submodule and remote catalog design

## Goal

Move the public resource catalogs out of the TeamPilot application repository
into `hhoao/teampilot-resources`, add that repository as a Git submodule, and
make resource acquisition read the dedicated repository instead of scanning the
application repository.

The migration covers:

- Team Hub resources;
- Expert Hub resources;
- Skill Pack manifests.

This is a clean break. Existing `hhoao/teampilot/...` remote keys, caches,
favorites, recent records, sessions, automations, and launch profiles are not
migrated or resolved after the change.

## Repository layout

The application repository will contain this submodule:

```text
resources/  # https://github.com/hhoao/teampilot-resources.git
```

The submodule's `main` branch will contain only resource catalogs and their
documentation:

```text
resources/
├── README.md
├── team-hub/
│   ├── README.md
│   ├── index.json
│   └── teams/<slug>/team.json
├── member-hub/
│   ├── README.md
│   ├── index.json
│   └── members/<slug>/member.json
└── skill-packs/
    ├── README.md
    ├── index.json
    └── <slug>/pack.json
```

The existing root-level `team-hub/`, `member-hub/`, and `skill-packs/`
directories will be moved into the submodule and removed from the parent
repository. The parent repository will track only the submodule gitlink and
client-side resource loading code.

The resources repository must be committed and pushed before the parent
repository records its submodule pointer. The resource and application
commits remain separate so resource-only updates do not require an application
code change or a full application repository checkout.

## Runtime catalog architecture

The submodule is a source-maintenance boundary, not a runtime filesystem
dependency. The Flutter application will never read or recursively scan
`resources/` at runtime.

### Team and Expert Hub

The existing `TeamHubRegistry` and `ExpertHubRegistry` abstractions remain the
network boundary. Their default registries change to:

```text
owner: hhoao
name: teampilot-resources
branch: main
rootPath: team-hub        # Team Hub
rootPath: member-hub      # Expert Hub
```

The existing indexed fetch protocol remains unchanged:

1. Fetch the type-specific `index.json` from GitHub Raw.
2. Read the listed slugs.
3. Fetch only the corresponding `team.json` or `member.json` manifests.
4. Stamp canonical keys using the new registry prefix.
5. Cache the parsed result under the existing application data cache layout,
   keyed by the new owner and repository name.

The default public keys become:

```text
hhoao/teampilot-resources/team-hub/<slug>
hhoao/teampilot-resources/member-hub/<slug>
```

Built-in entries under `teampilot/builtin/*` stay in client code and retain
their current precedence. No old-prefix aliases or fallback registry will be
added.

Hub publishing uses the new default registries, so Contents API paths and pull
requests target `hhoao/teampilot-resources`.

### Skill Pack registry

Skill Packs currently exist only as a synchronous in-process registry. Add the
same indexed Raw-content pattern without making application startup depend on
the network.

The new source boundary is conceptually:

```dart
abstract interface class SkillPackSource {
  Future<List<SkillPack>> fetchPacks({bool forceRefresh = false});
}
```

`GitRegistrySkillPackSource` will read:

```text
https://raw.githubusercontent.com/hhoao/teampilot-resources/main/
  skill-packs/index.json
https://raw.githubusercontent.com/hhoao/teampilot-resources/main/
  skill-packs/<slug>/pack.json
```

The registry URL helper receives paths relative to its `skill-packs` root, so
the second request is constructed with `<slug>/pack.json` and is rendered as
the full URL shown above.

The initial index format remains the existing string-slug shape:

```json
{
  "packs": ["gstack"]
}
```

`SkillPackRegistry` remains the synchronous lookup surface used by the
acquisition engine, but gains an asynchronous `ensureLoaded` operation:

- built-in packs are available immediately;
- the first pack installation awaits `ensureLoaded()`;
- concurrent first loads share one in-flight future;
- successful remote packs are merged by pack ID, with built-ins winning;
- the remote result is cached in a dedicated Skill Pack cache;
- an unavailable or malformed remote index leaves built-ins usable and
  records a sanitized source failure.

No network request is made merely by starting the application. The acquisition
engine waits for the remote catalog only when a dependency references a pack
that may need it.

## Data migration and identity policy

This change intentionally has no backward compatibility layer.

- Do not add key aliases or key canonicalization helpers.
- Do not rewrite existing user-owned JSON under the application data root.
- Do not read the old `hhoao/teampilot` Raw registry.
- Do not preserve old Team/Expert Hub cache entries, favorites, or recent
  records as valid catalog data.
- Update all migrated resource manifests so their internal `expertKey`
  references use `hhoao/teampilot-resources/member-hub/*`.
- Update code defaults and tests to expect only the new registry prefixes.

An old persisted key therefore follows the existing unknown-resource/error
path. This keeps the resource identity model single-sourced and avoids
maintaining two public registries indefinitely.

## Failure handling and caching

All three remote sources follow the existing source error conventions:

- index failure produces a source failure and an empty remote contribution;
- one failed or malformed manifest is skipped while other entries continue;
- errors are sanitized before they reach UI-facing catalog state;
- built-ins remain visible when the remote source fails;
- force refresh bypasses memory and disk cache and writes a fresh successful
  result;
- caches are separated by resource type and registry identity.

The new Skill Pack cache must use the injected `Filesystem` abstraction and
`AppStorage` paths, just like the existing Hub caches. Tests must be able to
override both filesystem and cache directory without touching the host disk.

## Implementation boundaries

Production changes are limited to:

- `.gitmodules` and the `resources/` submodule pointer;
- resource repository content and READMEs;
- Team/Expert registry defaults and their publish defaults;
- Skill Pack source, registry loading, cache path, and acquisition wiring;
- migrated resource keys in tests and documentation.

The following remain unchanged:

- client-code built-in Team/Expert templates;
- the Team/Expert UI and cubit contracts;
- external skills.sh / SkillsMP marketplace registries;
- provider catalogs and application-managed provider credentials;
- local user-created experts and cloned teams.

## Verification and acceptance criteria

The work is accepted when all of the following hold:

1. `resources/` is a valid submodule pointing at
   `https://github.com/hhoao/teampilot-resources.git` and its referenced
   commit exists on the remote `main` branch.
2. The parent repository no longer tracks root-level `team-hub/`,
   `member-hub/`, or `skill-packs/` directories.
3. The three resource indexes and all manifests in the resource repository
   parse successfully.
4. Team and Expert Hub requests target only
   `hhoao/teampilot-resources` and produce only new-prefix keys.
5. Skill Pack acquisition can resolve a remote pack after lazy loading and
   still resolves built-in packs when the remote source is unavailable.
6. Tests cover URL construction, index parsing, key stamping, lazy-load
   de-duplication, cache reads/writes, built-in precedence, and failure
   isolation.
7. `flutter analyze --no-fatal-infos --no-fatal-warnings` passes, followed by
   the repository's complete test command.
