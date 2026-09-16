# Remote Runtime Closure Design

## Goal

Make remote CLI launch materialize only the active session's runtime closure.
Codex must not copy the local shared plugin repository, Git metadata, disabled
plugins, or other control-plane caches to an SSH work machine.

## Current failure

`WorkMachineMaterializer` copies the complete `cli-defaults/{tool}` tree before
session staging. The local Codex tree currently contains roughly 100 MB and
5,300 files under `.tmp/plugins`, including a large `.git` directory. The
materializer then performs eight concurrent SFTP writes against one pooled SSH
storage connection. A disconnect during this phase aborts the SFTP channel and
causes the session connect to fail before the Codex process starts.

## Design

### 1. Control-plane and runtime-plane ownership

The local app owns catalogs, marketplace clones, Git metadata, shared plugin
repositories, and reusable caches. A remote session owns only the files it
needs to execute the selected CLI.

`cli-defaults/codex/.tmp/plugins` is no longer inherited by remote sessions.
Each session receives an empty, real `.tmp/plugins` directory and Codex's
native plugin installer populates it from the session's selected plugin source.
The global Codex cache remains local-only.

### 2. Cross-machine runtime projection

`ManifestFilesystem` distinguishes symlinks whose targets are inside the
remote work root from symlinks whose targets are local control-plane paths.
Internal inheritance links remain symlinks. External links are projected as
content copies into the launch manifest. This makes the current session's
plugin pool self-contained on the remote machine and prevents broken links to
the local home directory.

The projection is applied during staging, so it uses the already-resolved
runtime bundle and copies only enabled plugin bundles and generated runtime
resources. No workspace-level scan is needed to discover active plugins.

### 3. Materialization filter

The workspace-level materializer keeps small CLI config and workspace metadata,
but applies a runtime projection filter:

- skip Codex's `.tmp` shared cache tree;
- skip repository metadata directories (`.git`, `.hg`, `.svn`) in copied trees;
- keep normal config files and directories needed for inheritance;
- leave session-specific resources to the launch manifest projection.

The filter is explicit and testable rather than a broad extension or size
heuristic. Runtime content is never silently discarded based on file size.

### 4. Transfer reliability

Storage operations are tracked per profile. Evicting a pooled client removes it
from the pool immediately so new callers can reconnect, but closes the old
client only after in-flight SFTP/exec operations drain or a bounded grace
period expires. SFTP data operations are retried once on a channel/transport
closure when the operation is safe to replay.

Remote materialization uses a bounded write scheduler with a lower SFTP-safe
parallelism than the local worker pool, preserves the content-hash manifest,
and reports file/byte progress. A failed write never records its hash as
materialized.

Expected member-session disconnects consume their asynchronous close errors so
dartssh2 channel teardown cannot appear as an unhandled application error.

## Data flow

```text
runtime plan
  -> workspace preflight (small config only)
  -> session staging (active plugin/skill/resource closure)
  -> external symlink projection (copy into manifest)
  -> one remote manifest flush
  -> native Codex plugin install inside session-owned CODEX_HOME
  -> shell launch
```

## Compatibility policy

This intentionally changes remote Codex storage semantics. Existing remote
shared-cache links are replaced by session-owned directories during launch.
No compatibility shim is retained for the old full-cache inheritance model.

## Tests

- materializer excludes Codex shared cache and repository metadata;
- external staging symlinks become copy operations while in-root inheritance
  remains a symlink;
- active Codex plugin bundles are present in the remote launch manifest;
- storage client eviction drains in-flight SFTP operations;
- member-session close does not produce an unhandled expected teardown error;
- existing remote materialization and Codex launch tests remain green.
