# Work-plane apply: CAS + ApplyPlan + teampilot-apply

- 日期：2026-09-16
- 状态：已批准
- 来源：SSH stdin+tar 修好了传输，但 off-home 个人 Cursor 启动仍把插件/技能树每会话再 ship 一遍（~2MB、18 次 exec）。目标架构对齐 Flink `YarnClusterDescriptor` 的「资源引用 + 远端落地」，不引入 YARN。

## Goal

Session launch and workspace provision on a work machine must **submit a descriptor and missing bytes**, then **apply on that machine**. The control plane must not compile `LaunchManifest` into ad-hoc bash/tar epochs as the long-term architecture.

Three stable concepts:

1. **Blob** — content-addressed bytes (`sha256`), stored once per work-plane root.
2. **ApplyPlan** — ordered, versioned JSON of filesystem mutations. Large bodies are blob refs; small generated files may be inline.
3. **Applier** — one engine that interprets ApplyPlan. In-process on the control host; on SSH, a provisioned CLI `teampilot-apply` (not a daemon).

SSH stdin (`runOnStorageWithStdin`) remains the **transport**. [2026-09-16-ssh-manifest-stdin-tar](./2026-09-16-ssh-manifest-stdin-tar-design.md) stays; this spec replaces how payloads are *chosen*, not how CHANNEL_DATA works.

## Current state

Staging still builds a `LaunchManifest` (~113 ops). Off-home flush walks it in order and, on each tar/script kind switch, emits another gzip + `exec`. Root-external `symlink` / `copyTree` read the **control-plane** tree and pack bytes (`_copyExternal`), even when workspace provision already copied the same layout onto the work root (`plugins/installed/…`, `cli-defaults/…`, `skills/installed/…`).

Plugin pool already prefers `keptSymlink=true` into `plugins/installed`. The flush planner then often reifies that link into a tar because the target is treated as “not on the work plane.”

Workspace provision (`WorkMachineMaterializer._copySubtree`) still writes per-file SFTP (~6.5s + ~9.4s on the traced home-server launch). Same architectural miss: no shared artifact identity, no shared applier.

## Target architecture

```text
Control plane (Flutter)
  LaunchManifest (staging API, unchanged)
       │  path projection (homeRoot → workRoot)
       │  provided-link / blob-split
       ▼
  ApplyPlan v1  +  missing blobs[]
       │
       ├─ same-host / local: WorkPlaneApplier.apply(plan, fs)
       └─ SSH:  put missing blobs into work cas/
                 exec teampilot-apply --root <workRoot>   (plan on stdin)

Work plane <teampilotRoot>
  cas/sha256/<ab>/<sha256>     immutable blob objects
  bin/teampilot-apply          helper (phase 2)
```

Flink mapping (vocabulary only):

| Flink | This design |
|---|---|
| HDFS file + `YarnLocalResourceDescriptor` | cas object + ApplyPlan `file`/`tree` ref |
| `providedLibDirs` | path already under workRoot with matching identity → `symlink` / skip |
| NodeManager localize | `WorkPlaneApplier` / `teampilot-apply` |
| ApplicationMaster | not used; PTY still starts `cursor-agent` as today |

No ResourceManager, no NM daemon, no HDFS.

## Components

| Unit | Responsibility | Depends on |
|---|---|---|
| `LaunchManifest` | Staging-time overlay API (already exists) | `Filesystem` overlay |
| `WorkPathProjector` | Rewrite control-plane absolute paths to work-plane paths; decide provided vs blob | homeRoot, workRoot, sourceFs, optional workFs stat/hash |
| `ApplyPlan` | Versioned JSON document of ordered ops | projector output |
| `BlobStore` | `put`/`has`/`open` under `cas/sha256/…` | work `Filesystem` |
| `WorkPlaneApplier` | Apply a plan to a `Filesystem` (mkdir, ln, rm, materialize blob, inline write) | BlobStore + Filesystem |
| `teampilot-apply` | Thin CLI around `WorkPlaneApplier` | same library |
| `ApplyTransport` | SSH: upload missing blobs + one helper exec; local: in-process | existing `runOnStorageWithStdin` |

Keep each unit under the ~600-line service limit. Do not grow `manifest_executor.dart` / `manifest_ssh_flush_plan.dart` into the CAS layer; executor becomes a caller of projector + transport.

## ApplyPlan v1

JSON object, UTF-8, protocol field required:

```json
{
  "protocolVersion": 1,
  "workRoot": "/home/hhoa/.local/share/com.hhoa.teampilot",
  "ops": [ ]
}
```

`workRoot` is the work-plane `appDataRoot`. Every path in `ops` is absolute POSIX (or the work host’s path style) and **must** be `workRoot` itself or lie inside it. The applier rejects `..`, NUL, and any path that escapes `workRoot`.

Ops (order is the apply order; last write to a path still wins only if a later op says so — do not reorder):

| `op` | Fields | Effect |
|---|---|---|
| `ensureDir` | `path` | `mkdir -p` |
| `remove` | `path` | `rm -rf` |
| `rename` | `from`, `to` | `mv` |
| `symlink` | `linkPath`, `target` | `rm -rf linkPath` then `ln -sfn target linkPath`. Both `linkPath` and `target` must be under `workRoot` in v1 (plugin/skill installs live in-root; no links to `/usr` or the control plane). |
| `writeInline` | `path`, `content`, `mode?` | UTF-8 file; default mode `0644` |
| `writeBlob` | `path`, `sha256`, `mode?` | materialize cas object to `path` (copy or hardlink) |
| `tree` | `dest`, `entries: [{rel, sha256, mode}]` | `ensureDir dest`; for each entry, `ensureDir` of the parent of `dest/rel`, then write blob at `dest/rel`. `rel` must be relative with no `..` |

No `copyFile` / `copyTree` on the wire. The projector turns those into `symlink` (provided), `writeBlob`/`tree` (missing bytes), or `writeInline` (small generated text).

**Inline vs blob:** `writeFile` whose UTF-8 size is **≤ 4096 bytes** stays `writeInline`. Larger text, all binary, and every `copyFile`/`copyTree` member become blobs. 4096 is a hard constant in v1 (keeps the plan small without a knob).

**Symlink targets** in the plan are **work-plane** paths, never control-plane paths. The projector rewrites them. If the target cannot be projected and is not a blob-backed tree, fail staging (do not silently `_copyExternal` without recording why).

`protocolVersion` other than `1`: applier exits non-zero with a one-line error `unsupported protocolVersion`. The client then re-bootstraps the helper (phase 2) or refuses (phase 1 in-process must ship v1 only).

## Path projection and provided-link

Inputs: `homeRoot` (control `appDataRoot`), `workRoot` (work `appDataRoot`), source path or symlink target.

Rule: if `path` is under `homeRoot`, the candidate work path is `workRoot + relative(path, homeRoot)` (POSIX join via `AppPaths.pathContextForDataRoot`).

A candidate is **provided** when all of:

1. The candidate is under `workRoot`.
2. Work-plane `lstat(candidate)` exists.
3. For a **file**: sha256 of work bytes equals sha256 of source bytes. For a **directory** used as a `copyTree`/`symlink` target: treat as provided if the directory exists; do not recursively hash the whole tree on the hot path. Stale dir content is provision’s job (hash skip there). For a **symlink**: provided if the work symlink’s target string equals the projected target.

Then:

- `copyTree` / `copyFile` to a session path whose **source** is provided → plan `symlink` (`linkPath` = destination, `target` = candidate). Same as plugin pool’s `keptSymlink`, but the target is the **work** install path.
- `symlink` whose target projects to a provided path → keep `symlink` with rewritten target.
- Otherwise hash source bytes, `BlobStore.put` locally (control-side buffer), and emit `writeBlob` or `tree`.

Do **not** treat “same path string on two machines” as provided without (2)+(3). Laptop and home-server can both use `/home/hhoa/.local/share/com.hhoa.teampilot` with different contents.

Session-only generated files (cli config JSON, stamps) have no home equivalent → inline or blob, never provided-link.

## Blob store

Layout (work plane, documented in [workspace-storage-layout](../../workspace-storage-layout.md) when implemented):

```text
<teampilotRoot>/cas/sha256/<first two hex chars>/<64 hex sha256>
```

Objects are immutable. `put` is write-to-temp + `rename` into place. Never overwrite a hash that already exists. Mode of the cas object is `0644`; destination mode lives in the plan entry.

Control plane may keep an identical cas tree under the **home** root for upload-by-hash; that is an implementation cache, not a second protocol.

**GC:** out of scope for both phases. Cas may grow. A later spec can unref objects not named by any live session/plugin tree.

**Concurrency:** while putting a blob or applying a plan on a work root, take an exclusive advisory lock on `<teampilotRoot>/cas/LOCK` (or in-process mutex when local). SSH applies are already naturally serial per storage-plane client; the lock covers two TeamPilot clients on the same machine.

## WorkPlaneApplier

Pure library. Constructor injection: `Filesystem fs`, `BlobStore blobs`, `workRoot`. No `Directory.current`. No SSH.

`apply(ApplyPlan plan)`:

1. Verify `protocolVersion == 1` and `plan.workRoot` equals the applier’s `workRoot`.
2. Sandbox every path.
3. For each op, apply in order. `writeBlob`/`tree`: `blobs.open(sha256)` must succeed; missing blob is a hard error (transport must have uploaded first).
4. `symlink`: `rm -rf linkPath` then `ln -sfn` (same leftover-dir rule as today).

Local / WSL / same-host SSH (`identical(sourceFs, targetFs)`): call this library in-process. Same-host may skip cas and copy/link bytes directly **only when** `sourceFs === targetFs`; the plan still uses blob hashes computed from those bytes so the document stays the same. Implementation may materialize from source path if hash matches a just-read file (avoid double-write).

### `teampilot-apply`

Phase 2 CLI around the same library:

```text
teampilot-apply --root <workRoot>
```

Reads ApplyPlan JSON from stdin. Blobs must already exist in `<root>/cas/…`. Exit 0 on success; stderr is diagnostics; stdout is a single JSON line `{ "ok": true, "ops": N }` so the client can log.

`--protocol-version` prints `1` and exits 0 (used by provision to decide bootstrap).

Not a daemon. One process per apply. Do not listen on a port.

**Distribution:** `client/bin/teampilot_apply.dart` compiled with `dart compile exe` for the work OS/arch. Installed to `<teampilotRoot>/bin/teampilot-apply`. A sibling `teampilot-apply.protocol` file contains `1`.

**Bootstrap (phase 2):** during workspace provision, if the helper is missing, not executable, or protocol file ≠ client’s v1, upload the matching binary with the existing stdin tar / SFTP path **once**, `chmod 0755`. Detect arch with a short `uname -m` / `os` probe already used for CLI locate. First apply after bootstrap uses the helper.

If the work OS/arch has no shipped binary, fail provision with a clear error (l10n). Do not fall back to compiling bash from ApplyPlan on that host in phase 2 — that would resurrect two interpreters. Phase 1 (below) is the bash/tar fallback and is **removed** when phase 2 ships for that host.

v1 hosts: POSIX Linux and macOS SSH (the production path). Windows work-plane helper is a later host, not a v1 requirement.

## Transport (SSH)

Reuse `runOnStorageWithStdin`. Command strings stay under 1KB.

**Phase 1 (no helper):** client still applies with today’s overlay gzip + mutation script, but the **input to that compiler is ApplyPlan**, and the plan’s blob set is only non-provided files. Expected: far fewer tar members, often one mutation script of `ln`/`mkdir`/`rm` plus one gzip of generated files. Still one or two `exec`s, not one per kind-switch of the raw manifest. Kind-switch epoch splitting of the unexpanded manifest is **retired**.

**Phase 2:**

1. For each missing sha256 (work `cas` `has` is false): upload a gzip tar whose members are `sha256/<ab>/<hash>` relative to `cas/` (or a single object put). One tar of all missing blobs is enough.
2. `teampilot-apply --root '<workRoot>'` with ApplyPlan JSON on stdin.

Two `exec`s worst case (blobs + apply), one if nothing missing.

Do not send blob payloads inside the ApplyPlan JSON.

## Data flow

```text
stage-session → LaunchManifest
  → WorkPathProjector (provided-link / blob-split)
  → ApplyPlan
  → log: ops, inlineBytes, blobCount, blobBytes, providedLinks
  → local: WorkPlaneApplier
  → SSH phase 1: compile plan → at most {one mutation script, one overlay tar}
  → SSH phase 2: put missing cas objects → teampilot-apply
  → native plugin install / cursor home passthrough (unchanged hooks)
  → PTY
```

Workspace provision (phase 2, same engine): materializer computes hashes, uploads missing blobs, ApplyPlan of `tree`/`writeBlob` under `cli-defaults` and workspace config, then `teampilot-apply`. Per-file SFTP `_copyOne` is removed for those subtrees.

## Logging

Keep `[session-launch] manifest flush via ssh`. Add:

- `apply-plan protocol=1 ops=… provided=… blobs=… blobBytes=… inlineBytes=…`
- phase 2: `teampilot-apply` exit and `ops=` from its stdout JSON
- provision: `cas-put missing=… bytes=…` then `apply`

Do not log blob sha256 lists at info; debug only.

## Error handling

- Escaping path → `StateError` / helper non-zero; do not apply remaining ops (fail closed). Partial apply is possible if we die mid-plan; next launch rebuilds a full plan (ops are intended to be replay-safe: `ensureDir`, `ln -sfn`, `rm -rf`, blob materialize overwrite).
- Missing blob → fail; do not skip.
- Helper crash → surface as session connect failure (same reconnect rules as stdin-tar spec §4).
- Provided-link whose work target disappears between stat and apply: `ln` fails; fail the flush (do not fall back to packing the control-plane tree in the same attempt).

## Tests

- Projector: copyTree of `homeRoot/plugins/installed/foo` to a session pool dir becomes `symlink` to `workRoot/plugins/installed/foo` when work dir exists; becomes `tree` of hashed files when it does not.
- Same path string, different bytes → not provided (file hash mismatch).
- ApplyPlan sandbox rejects `../escape` and absolute paths outside workRoot.
- `writeFile` 4KiB stays inline; 4KiB+1 is blob.
- Applier: rm-then-write vs write-then-rm order; leftover dir then symlink.
- Phase 1 compiler: one script + at most one tar from a plan that interleaves ensureDir/symlink/writeInline (no 18 epochs).
- Phase 2 transport fake: missing hashes appear in the cas tar; plan JSON stdin has no file bodies.
- Helper `--protocol-version` is `1`.
- Local flush still uses in-process applier (no SSH).

Use `dart run tool/run_tests.dart`, not `flutter test`. Cubit tests that need a home plane use `setUpTestAppStorage()`.

## Phasing

**Phase 1 — ApplyPlan + provided-link + single-shot compile** (unblocks the 2MB / 18-exec session flush):

- Projector + ApplyPlan model + JSON
- ManifestExecutor SSH path consumes ApplyPlan, emits ≤2 stdin execs using existing bash/tar transport
- No `teampilot-apply`, no provision rewrite, no cas on disk required (blobs may be in-memory until the overlay tar)

**Phase 2 — BlobStore + helper + provision:**

- Cas layout + lock
- `teampilot-apply` bootstrap in provisioner
- Session flush uses helper
- Work-machine materialize / workspace config apply through the same applier
- Remove phase 1 bash/tar compiler for hosts that have the helper

Implementation plans are **one per phase**. This document is the target architecture for both.

## Out of scope

- YARN / a resident NM / RPC daemon
- Packing the entire TeamPilot home
- Cas GC
- Windows work-plane helper (v1)
- Changing dartssh2 CHANNEL_REQUEST limits
- Session SSH MCP (orthogonal)
- Executable-bit follow-up beyond storing `mode` on `writeBlob`/`tree` entries (phase 1 overlay tar still uses ArchiveFile modes as in the stdin-tar follow-up)

## Relation to stdin-tar spec

stdin-tar remains correct for **how** large bytes move. Epoch splitting on unexpanded manifest kind-switch is superseded by ApplyPlan. Root-external copy into overlay tar remains the **fallback** when provided-link does not apply, not the default for plugins/skills already on the work root.
