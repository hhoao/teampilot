# Remote Antigravity OAuth Smoke Checklist

Manual verification for the remote `agy` login path in `AntigravityRemoteLoginDialog`.

> Status: **not executed in this development environment.** The checklist must be
> run against a real SSH Linux/macOS host before claiming remote OAuth support.
> The UI and SSH PTY path are covered by unit tests; the host-side OAuth flow is not.

## 1. Host prerequisites

- SSH target reachable from TeamPilot (`ssh:<profile>`).
- POSIX host with `curl` (or `wget`), `unzip` (or `python3`), and `sha256sum`
  (or `shasum`).
- Antigravity CLI installed (`agy` on PATH, or installed through the app).

## 2. Install the CLI + adapter

1. In Settings → CLI, select the Antigravity card on the remote target.
2. Press Install for the CLI. Expect `agy` on the remote PATH.
3. Press Install for the ACP adapter. Expect
   `$HOME/.local/share/teampilot/toolchain/antigravity-acp/1.4.3/agy_acp_server.par`
   and its `localharness_external` sidecar.
4. Confirm `targets.json` now has
   `acpAdapterPathOverrides["ssh:<profile>"]["antigravity"]`.

## 3. Run the login spike

On the SSH host, in an interactive shell:

```bash
export HOME="$HOME/.local/share/teampilot/cli-login/antigravity/spike/home"
mkdir -p "$HOME" "$HOME/.gemini"
export GEMINI_HOME="$HOME/.gemini"
export TERM=xterm-256color
export COLORTERM=truecolor
agy
```

Record exactly one of:

| Observed flow | Action |
|---|---|
| Device code + URL | `AntigravityRemoteLoginDialog` already supports it. Complete the code and continue. |
| `http://127.0.0.1:<port>/...` redirect | The app must forward a local port to the remote port before this can work. Add the forward in the dialog, then re-run. |
| Other / no output | Record the exact output and stop; do not claim remote OAuth support. |

## 4. Verify the login

```bash
export HOME="$HOME/.local/share/teampilot/cli-login/antigravity/spike/home"
export GEMINI_HOME="$HOME/.gemini"
agy models
```

Expected: exit 0 and a model list.

## 5. Verify the ACP adapter

Start an Antigravity ACP session on the same remote target and send one prompt.
Expected: `initialize` / `session/new` succeed and the first turn answers.

## 6. Known limitations

- The remote host's OS keyring may be unavailable in a headless SSH session.
  If `agy` requires a keyring and writes no file credentials under
  `GEMINI_HOME`, remote OAuth cannot work; use API key / ADC instead.
- Windows remote hosts are not supported by the Antigravity adapter installer.
- If the host uses a loopback OAuth redirect, port forwarding is required before
  the flow can complete from a phone browser.

## 7. Result log

| Field | Value |
|---|---|
| Host OS / arch | |
| Flow observed | |
| `agy models` | |
| ACP `session/new` | |
| Keyring fallback used | |
| Port forwarding needed | |
| Notes | |
