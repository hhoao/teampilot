# CodeBuddy ACP Smoke Checklist

Manual verification for the ACP-only CodeBuddy integration. Automated
coverage: `client/test/services/cli/codebuddy/` plus
`client/test/integration/codebuddy_acp_local_smoke_test.dart`.

Prerequisite: none for the in-app flow — Providers → CodeBuddy →
**Sign in** opens the CLI login terminal.

1. **Detect / install**
   - Settings → AI CLIs: the CodeBuddy card shows the binary path and
     version; the ACP row says "uses CLI" (no adapter row, no switch).
   - Missing binary: Install runs `npm i -g @tencent-ai/codebuddy-code`.

2. **Sign in (isolated official provider)**
   - Add the "CodeBuddy" preset (API key / base URL hidden).
   - Click **Sign in** → terminal opens with an isolated, **per-provider**
     `HOME` (`<appData>/cli-login/codebuddy/<provider>/home`); pick a login
     method if asked, complete the browser flow.
   - Click **Done** → the row shows Connected; the access token is copied to
     `<appData>/providers/codebuddy/<provider>.auth.json`.
   - Add the preset a second time, sign in with another account, and run two
     sessions concurrently: each provider row keeps its own account.
   - Verify isolation: the global CLI login
     (`~/.local/share/CodeBuddyExtension/.../auth/*.info`) is untouched, and
     `codebuddy` in a normal terminal still shows the original account.
   - Click **Sign in** again to switch accounts; each provider row keeps its
     own token.
   - Manual fallback: run `codebuddy` in any terminal and use `/login`
     (then `/status` to confirm).

2. **Personal ACP session** (desktop local)
   - New personal session with CodeBuddy.
   - Expect: no terminal view; ACP chat opens, the first prompt answers,
     tool calls render, a Bash call shows the permission card with
     Allow / Always / Reject.
   - Stop cancels the turn (not the process); the next prompt still works.

3. **Config isolation**
   - `<teampilotRoot>/workspace/workspaces/<ws>/sessions/<s>/runtime/codebuddy`
     contains `settings.json`, `models.json` (custom provider only),
     `mcp.json`, `skills/`, `plugins/`, `CODEBUDDY.md`.
   - No API key plaintext in `models.json`; it is passed via
     `CODEBUDDY_API_KEY`.

4. **Provider**
   - Add a "CodeBuddy" official provider → the session uses
     the account login and the selected model.
   - Add an OpenAI-compatible provider (base URL + key) → the session
     picks it up via `models.json` + env.

5. **Skills / MCP / plugins / hooks**
   - Enable a skill → `/skill-name` works in the chat.
   - Enable a catalog MCP server → its tools appear in the tool calls.
   - Import existing hooks from `~/.codebuddy/settings.json` → they render
     in the session's `settings.json#hooks`.

6. **Reconnect**
   - Close and reopen the session: ACP transcript restores from the app
     store (no `session/load` walk through the CLI transcript).
