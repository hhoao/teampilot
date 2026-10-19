# Remote ACP Adapter Smoke Checklist

Manual verification for `docs/superpowers/specs/2026-10-16-remote-acp-adapter-readiness-design.md`.
Unit tests cover the plumbing; the items below are the only proof that the
remote ACP session actually spawns and answers like the PTY path.

Run with a host reachable over SSH from the app (`ssh:<profile>` target).

1. **Missing adapter is surfaced**
   - Remote host has `claude` but not `claude-agent-acp`.
   - Compose a personal Claude launch on the remote project with ACP enabled.
   - Expect: the "Required CLIs on this machine" panel appears below the compose
     card with a "Claude Code ACP adapter" row marked not found and an Install
     button.

2. **Install lands on the host**
   - Press Install. Expect: progress phases (Checking npm / Bootstrapping Node /
     Installing CLI / Locating executable) and a ready row.
   - On the host, confirm `claude-agent-acp` exists and
     `targets.json` now has `acpAdapterPathOverrides["ssh:<profile>"]["claude"]`
     set to its absolute path.

3. **Handshake and first turn (Official OAuth)**
   - With the Claude provider set to official login, start the session.
   - Expect: ACP handshake completes, the first prompt is answered, and one tool
     call runs. **If it reports "Not logged in", stop and debug the remote
     `.credentials.json` → remote `CLAUDE_CONFIG_DIR` linkage before shipping.**

4. **Handshake and first turn (API key)**
   - Repeat 3 with an API-key provider.

5. **Codex**
   - Repeat 1-4 for Codex / `codex-acp`.

6. **Override reuse**
   - Kill the SSH session, relaunch the same personal Claude ACP session.
   - Expect: no re-locate needed; the stored absolute adapter path is used.

7. **PATH-independence**
   - Move/install the adapter to a location outside the ssh exec `PATH`
     (e.g. `/opt/acp/`), set the override via Settings Locate, and relaunch.
   - Expect: the session still starts (proof the absolute-path injection works).
