# Login-shell PATH resolution for local PTY child environments

## Problem

On macOS, launching TeamPilot from Finder/Dock/Spotlight gives the app process the
launchd default PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) instead of the user's shell
PATH. Local session PTYs pass the host environment through verbatim
(`PtyLaunchEnvironment.buildPtyEnvironment` with `inheritHostEnvironment: true`;
flutter_pty_new merges `Platform.environment`), so every CLI child sees that sparse
PATH.

npm-installed CLIs (`claude`, `codex`, `opencode`, `cursor-agent`) are Node scripts
with `#!/usr/bin/env node` shebangs. The executable itself is found — `CliToolLocator`
already has a login-shell lookup fallback for *locating* binaries — but once spawned,
`/usr/bin/env node` resolves against the sparse child PATH and fails:

```
env: node: No such file or directory
[process exited with code 127]
```

The user's terminal works because `.zshrc` / `.zprofile` set up Homebrew shellenv,
nvm, volta, `~/.local/bin`, etc. there. The codebase already acknowledges "sparse
PATH" for GUI launches (see `macos_npm_path_candidates.dart`,
`cli_tool_locator.dart`) but only for *finding* executables, never for the *child
environment*. Linux `.desktop` launches have the same class of gap (session PATH
typically misses `~/.local/bin`, `~/.cargo/bin`, version-manager dirs).

## Decision

Resolve the user's real login-shell PATH once per app run and make local PTY child
environments match a login shell.

- **Resolve at startup, cache forever.** A one-shot warmup runs the user's login
  shell non-interactively-driven (`-ilc`) to print its PATH behind a marker; the
  result is memoized for the process lifetime.
- **Replace-with-prefix-preservation on POSIX local PTYs.** When a resolved PATH
  exists, `buildPtyEnvironment` rebuilds the child `PATH` as
  `[deliberate prepends] + [login-shell dirs] + [leftover host dirs]`: entries the
  launch flow intentionally added on top of the inherited host PATH (skill-pack
  `PATH` exports from `SkillPackInstallStore.prependPath`) stay first, then login
  shell dirs fill in, then whatever remains of the sparse host base. Net effect:
  version managers (nvm) win exactly as in a real terminal, and nothing the app
  prepended is dropped.
- **Synchronous fallback candidates.** If resolution has not completed (or failed)
  by spawn time, append known directories (`/opt/homebrew/bin`, `/usr/local/bin`,
  `$HOME/.local/bin`) that exist and are missing from the current PATH. Cheap
  `existsSync` checks; guarantees Homebrew-style installs work even if the warmup
  loses the race with an immediate reconnect.
- **Scope: macOS + Linux, local PTY only.** Windows keeps its current behavior
  (GUI processes inherit user+system PATH including npm). SSH remote launches
  already pass `inheritHostEnvironment: false` and must not receive the control
  plane's PATH. WSL spawns run on a Windows host process, so the POSIX branch never
  triggers there.
- **Never block or fail loudly.** Each shell attempt times out (5 s); all failures
  fall back silently to candidate appending. Startup does not wait for resolution.

Out of scope: Windows PATH repair, re-resolving after install changes mid-session,
fixing one-shot `Process.run` lookups (they already carry their own fallbacks).

## Architecture

Two pieces: ① a resolver service with a cached result, ② a merge step inside
`buildPtyEnvironment`.

```
buildAppShell()
  └─ unawaited(HostShellPathResolver.warmup())        # POSIX desktops only
       └─ $SHELL|zsh|bash -ilc 'printf "%s" "__TP_PATH__$PATH"'
            └─ parse marker → cache PATH (success OR failure)

TerminalSession.connect / connectWorkspaceShell
  └─ PtyLaunchEnvironment.buildPtyEnvironment(env, inheritHostEnvironment: true)
       ├─ macOS/Linux: cached PATH? replace env['PATH']
       └─ else: append existing missing candidate dirs   # sync fallback
```

### 1. Resolver — `client/lib/services/host/host_shell_path_resolver.dart`

Follows the `HostLoginShellLookup` house style (static API + injectable runner):

- `Future<String?> resolve({ProcessRunner runner})` — tries `$SHELL` basename
  first, then `zsh`, then `bash`; each attempt `<shell> -ilc 'printf "%s"
  "__TP_PATH__$PATH"'` with a 5 s timeout. First success wins.
- Parsing takes everything after the **last** `__TP_PATH__` occurrence, truncates
  at the first newline (PATH cannot contain newlines), then trims whitespace —
  robust against interactive-shell noise (prompt escape sequences, nvm banners).
- Validation: non-empty result containing at least one absolute directory;
  otherwise treated as failure.
- Result (success or failure) is cached; `resetForTest()` clears it for tests.
- Runner typedef mirrors `cli_tool_locator.dart`'s `ProcessRunner` so tests inject
  fakes without spawning shells.

### 2. Merge — `pty_launch_environment.dart`

Inside `buildPtyEnvironment`, after host-env inheritance and before returning,
when `inheritHostEnvironment == true` and the platform is macOS or Linux:

- Cached resolved PATH available → `merged['PATH'] = resolvedPath`.
- Otherwise → for each fallback candidate dir that `existsSync()` and is not
  already in `PATH`, append it (`:`-separated).

Existing behavior elsewhere is untouched: hyperlink identity, `COLORFGBG`, the
Windows `Path`→`PATH` normalization, and the SSH branch.

### 3. Bootstrap wiring — `app_shell.dart`

One line near the top of `buildAppShell`: `unawaited(HostShellPathResolver.warmup())`.
The resolver no-ops on unsupported platforms. Resolution completes during splash;
by the time a session connects the cache is warm in the common case.

### 4. Coverage

Fixing the PTY environment fixes the whole subtree: member CLI sessions, workspace
shell terminals, hook glue scripts (children of the CLI), and any node/python/ruby
shebang script those CLIs execute — not just the reported `env: node:` symptom.

## Error handling

| Failure | Behavior |
|---------|----------|
| Shell hangs (bad rc plugin) | 5 s timeout → try next shell |
| All shells fail / noise breaks parsing | Cache failure → sync candidate fallback |
| Warmup loses race with instant connect | Candidate fallback still applies at spawn |
| Non-POSIX platform | No-op everywhere |

## Testing

- **New** `client/test/services/host/host_shell_path_resolver_test.dart` with an
  injected fake runner: marker extraction (noise before marker, multiple markers),
  shell fallback order (`$SHELL` → zsh → bash), timeout handling, validation
  rejection, caching + `resetForTest()`.
- **Extended** `client/test/services/terminal/pty_launch_environment_test.dart`:
  PATH replacement when resolved, dedup-append fallback on unresolved, no-op for
  `inheritHostEnvironment: false`, no-op on Windows, existing hyperlink/COLORFGBG
  assertions unchanged.

Verification per repo convention:
`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
