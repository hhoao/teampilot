# Remote download catalog design

**Date:** 2026-07-31  
**Status:** Approved for planning  
**Problem:** TeamPilot fetches many assets from GitHub (app updates, skills, hubs, and soon Termux APKs) with hard-coded origins and almost no mirror layer (Node’s `npmmirror` is a rare exception). Adding Termux in-app install as yet another one-off URL path would worsen fragmentation. China and restricted networks need a single place to configure download sources without rewriting each feature.

**Builds on:** Android Termux home ([2026-07-31-android-termux-home-design.md](./2026-07-31-android-termux-home-design.md)), existing `AppUpdateService` / `AppUpdateInstaller` / `AndroidPackageInstaller`, `app_update_config.dart` dart-defines.

## Goal

Introduce a **URL-rewrite download catalog**: features keep constructing **logical** GitHub (or similar) URLs; a shared resolver expands them into ordered **candidates** (official + optional mirrors); a shared downloader tries candidates with progress and optional checksums.  
**v1 consumers:** (1) Termux APK acquire + system install, (2) App Update metadata + asset download.  
**v1 catalog:** a **single enabled source** (official GitHub identity); mirror slots exist so adding a CDN later is configuration, not a redesign.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Architecture | URL rewrite gateway (not asset-id menu, not global HTTP proxy) |
| v1 scope | Catalog core + Termux APK install UX + App Update wired through resolver/downloader |
| Default sources | Source **list** shape; only one entry enabled (official GitHub) |
| Termux UX | Primary “Download & install” when Termux missing; store/GitHub links secondary |
| Later | Skill/Hub `codeload` / `raw` rules reserved; npm/cargo out of this catalog |
| Non-goal | Bundling Termux inside TeamPilot APK |

## Invariants

1. **Business code speaks logical URLs** (or thin helpers that build them). Mirror policy lives only in the catalog.
2. **Unknown hosts pass through** unchanged (single identity candidate) so non-GitHub URLs keep working.
3. **Install ≠ download.** Catalog owns fetch; Termux uses `AndroidPackageInstaller`, App Update keeps `AppUpdateInstaller`.
4. **Control-plane / device-local settings** for catalog overrides must not ride a remote SSH/Termux home filesystem (same lesson as SSH profiles).
5. **Fail soft for users:** if all candidates fail, show actionable l10n (retry / open external link), not a raw stack dump.

## Design

### 1. Core modules

```text
Feature
  → logical URL / release intent
  → RemoteDownloadResolver.resolve(uri) → List<DownloadCandidate>
  → RemoteDownloader.fetch(candidates, {sha256?, onProgress}) → File
  → Feature-specific install/apply
```

| Type | Role |
|------|------|
| `RemoteDownloadSource` | `id`, `priority`, `enabled`, `matchHost`, optional `matchPathPrefix`, `rewriteOrigin` (or identity) |
| `RemoteDownloadCatalog` | Ordered list of sources; load defaults + overrides |
| `RemoteDownloadResolver` | Expand logical URL → candidates |
| `RemoteDownloader` | Sequential try, timeout/retry, progress, optional sha256, aggregate errors |
| `RemoteDownloadSettings` | Runtime overrides (settings UI / dart-define / optional local JSON) |

Suggested rewrite behavior: replace origin (`scheme://host[:port]`) with `rewriteOrigin`, keep path + query. Identity source = no rewrite.

### 2. Host coverage

| Host / shape | v1 | Notes |
|--------------|----|-------|
| `github.com/.../releases/download/...` | Required | App Update assets, Termux APK |
| `api.github.com/repos/.../releases/...` | Required | App Update metadata |
| `github.com/.../releases/latest` | Required | Existing tag-redirect fallback |
| `codeload.github.com` | Reserved | Future Skill |
| `raw.githubusercontent.com` | Reserved | Future Hub/Skill |
| `github.com/.../archive/...` | Reserved | Future Skill zip fallback |

### 3. Download pipeline

1. For each candidate (priority order): GET with redirects, timeout, bounded retries.  
2. Stream to a temp file; report `(received, total?)`.  
3. If `expectedSha256` present and mismatches → discard, try next candidate.  
4. On success → atomic move to destination.  
5. On total failure → error listing per-candidate causes for logs; user-facing l10n summary.

### 4. Termux acquisition UX

On `TermuxSetupPage` (Android):

| State | UI |
|-------|----|
| `com.termux` not installed | Primary CTA: **Download & install Termux** + progress; Play / F-Droid / GitHub links secondary |
| Installed | Skip download; continue OpenSSH / keys / Connect |
| Download failed | Retry / try next source messaging / open external link |
| After APK install | Re-probe package; user returns from system installer |

`TermuxApkAcquisition`:

- Resolve latest Termux release asset for device ABI (prefer `arm64-v8a`).  
- Logical URL under `termux/termux-app` releases.  
- Fetch via Resolver + Downloader.  
- Install via `AndroidPackageInstaller` (same stack as app update APK).  

Package presence: small Android probe for `com.termux`; if probe unavailable, show download CTA conservatively.

### 5. App Update integration

- `AppUpdateService` keeps release discovery logic but routes GitHub HTTP GETs through Resolver + Downloader.  
- `AppUpdateInstaller` unchanged.  
- Existing `APP_UPDATE_GITHUB_OWNER/REPO` dart-defines remain for **which repo**; catalog controls **how hosts are reached**.

### 6. Settings

- Settings → Network / Download sources: list enabled catalog entries; restore defaults.  
- Advanced: import JSON override or a single “mirror base URL” that adds one rewrite rule for GitHub hosts.  
- Overrides stored **device-local**, not under remote/Termux home AppStorage.

### 7. Error handling

| Failure | User action |
|---------|-------------|
| Network / all candidates fail | Retry; optional open GitHub/F-Droid link |
| Checksum mismatch | Try next candidate; if none, clear error |
| User denies unknown-sources install | Explain system setting; keep APK for retry |
| Cancelled | Idle, no partial install |

User strings → l10n; diagnostics → `AppLogger`.

## Testing

- Resolver: identity-only catalog returns original URL; with mirror rule, candidates = [official, mirror] in priority order; unmatched host → single identity.  
- Downloader: first candidate fails → second succeeds; sha256 fail skips; cancel mid-flight.  
- Termux: missing package shows primary download CTA; acquisition builds expected logical release URL for ABI (unit with fixtures).  
- App Update: download path uses resolver (mock catalog) without changing install kind selection.  
- Settings override: device-local JSON changes candidate order without touching feature code.  
- No requirement for live GitHub in CI (fixtures / fake HTTP).

## Success criteria

1. Adding a mirror is a catalog/config change (no Termux or App Update code change for host rewrite).  
2. Android user without Termux can download + system-install from the setup page with progress.  
3. App Update still finds and downloads the correct platform asset; install path unchanged.  
4. Default shipping config uses a single official GitHub source.  
5. Catalog overrides do not disappear when home is Termux/SSH.

## Non-goals (this slice)

- Migrating Skill/Plugin/Hub fetch to the catalog (follow-up)  
- npm / cargo / brew registry mirroring  
- Bundling Termux or other large runtimes in the TeamPilot APK  
- Silent background prefetch of all tools  
- CI font / grammar sync tooling  

## Follow-ups

1. Enable `codeload` + `raw.githubusercontent.com` rewrite rules; route Skill/Hub GET through Downloader.  
2. Optional remote catalog JSON for fleet-wide mirror defaults.  
3. Richer per-source health UI (last success/failure).

## Relationship to Termux home

Termux **home** (loopback SSH work plane) is separate. This spec only covers **acquiring the Termux app package**. After install, users still complete OpenSSH setup and Connect per the Termux home design.
