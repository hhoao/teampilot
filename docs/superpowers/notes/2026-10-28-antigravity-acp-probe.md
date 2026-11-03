# Antigravity ACP probe (1.4.3)

Probe date: 2026-10-28. Host: Ubuntu 26.04.1 (x86_64), non-root user `hhoa`,
no `agy` CLI installed, no Antigravity login, network available. The host *does*
have a real `~/.gemini/` (Gemini CLI leftovers: `GEMINI.md`, `config/`,
`google_accounts.json`), so HOME isolation is not academic here.

Legend for every line: **[observed]** = seen on the wire from the running
1.4.3 binary; **[source]** = read from the Python source shipped inside the
1.4.3 `.par` (not executed); **[not tested]** = not verified in this probe.

- Adapter path: `/tmp/agy-acp/extracted/agy_acp_server.par`
  (927,707,135 bytes per `unzip -l`).
  Note: the pre-existing copy at `/tmp/agy-acp/agy_acp_server.par` was
  774,504,448 bytes — short by ~153 MB. It still answered `initialize`, but all
  evidence below uses the fully extracted copy. The zip also contains a
  **required sidecar** `localharness_external` (133,926,136 bytes); see Notes.
- HOME isolation: reads/writes under HOME? **yes**
  - Every path resolves under `$HOME/.gemini` (`paths.gemini_home()`):
    `<home>/antigravity-acp/settings.json`, `<home>/antigravity-acp/conversations/`,
    `<home>/antigravity-acp/brain/`, `<home>/config/`, `<home>/antigravity/bin/`.
    [observed] the `Authentication required` error message names
    `$HOME/.gemini/antigravity-acp/settings.json` for the overridden HOME.
  - [observed] `strace -f -e trace=openat,stat,newfstatat` over `initialize`
    with `HOME=/tmp/agy-strace-home` recorded **0** accesses to `/home/hhoa`
    and only these `.gemini`/config paths:
    `/tmp/agy-strace-home/.gemini/antigravity-acp/settings.json`,
    `/tmp/agy-strace-home/.config/gcloud/certificate_config.json`.
  - [observed] `GEMINI_HOME` is the documented, stronger knob: it *is* the
    `.gemini` directory itself. With `GEMINI_HOME=/tmp/agy-acp/gh-probe` the
    settings path in the error message became
    `/tmp/agy-acp/gh-probe/antigravity-acp/settings.json`. [source]
    `paths.py` docstring: "`GEMINI_HOME` names the `.gemini` directory itself".
  - [observed] first session under a fresh HOME materialised
    `.gemini/antigravity/bin/webm_encoder` (16,851,235 bytes),
    `.gemini/antigravity-acp/conversations/<id>.db` (458,752 bytes),
    `.../<id>.meta` (27 bytes) and
    `.gemini/antigravity-acp/brain/<id>/.system_generated/logs/transcript*.jsonl`.
  - Consequence: an isolated `HOME` also isolates Google ADC
    (`$HOME/.config/gcloud`), so `agent-platform` auth would need
    `GOOGLE_APPLICATION_CREDENTIALS` or a pre-seeded HOME. [source+observed]
- `--uid`: required? **only on hosts without a `nobody` group**; accepted empty?
  **yes (`--uid=`)**; accepted value? **a *user name*, not an account id**.
  - [observed] Without `--uid`, startup aborts before any JSON-RPC:
    ```
    F1028 09:54:14.370595 1563401 init_google.cc:396] Check failed: LookupGIDByGroupName(groupname, &new_gid)  Group nobody not found
    ```
    (stack: `SwitchGroup` → `ChangeRootAndUser` → `RealInitGoogle`). This host
    has user `nobody` but no group `nobody` (`getent group nobody` → exit 2).
  - [observed] `--uid=` (empty string) starts normally and answers `initialize`.
  - [observed] `--uid=abc-123` → `Check failed: LookupGIDByGroupName(...) Group abc-123 not found` (fatal). So the value is used as a *user/group name* to drop privileges to, not as an Antigravity account selector.
  - [observed] `--helpfull` documents it under `third_party/gloop/base/init_google.cc`:
    `--uid: [C++] If root, switch to this user id (or empty-string not to switch) (default: 'nobody')`,
    `--gid: ... (default: '=uid')`.
  - [observed] Unknown flags are fatal: `FATAL Flags parsing error: Unknown command line flag 'bogus-flag'`.
  - Caveat for the probe script in this repo: `client/tool/antigravity_acp_probe.dart`
    accepts only an executable path, so it cannot pass `--uid=`; on this host it
    dies with the `nobody` fatal above and no JSON-RPC is exchanged.
- initialize agentInfo: **[observed]**
  ```json
  {"name":"antigravity-acp","title":"Google Antigravity","version":"1.4.3"}
  ```
  Full `initialize` result (protocolVersion 1, empty `clientCapabilities`):
  ```json
  {"protocolVersion":1,
   "agentCapabilities":{"loadSession":true,
     "promptCapabilities":{"image":true,"audio":true,"embeddedContext":true},
     "mcpCapabilities":{"http":true,"sse":true},
     "sessionCapabilities":{"list":{},"resume":{}},
     "auth":{"logout":{}},
     "_meta":{"antigravity":{"tier":true,"systemPrompt":{"append":true}}}},
   "authMethods":[...],
   "agentInfo":{"name":"antigravity-acp","title":"Google Antigravity","version":"1.4.3"}}
  ```
- initialize authMethods: **[observed]** four entries, in this order:
  1. `oauth-personal` — "Log in with Google"
  2. `oauth-business` — "Log in with Gemini Enterprise"
  3. `gemini-api-key` — "Gemini API key" (Gemini Developer API)
  4. `agent-platform` — "Gemini Enterprise Agent Platform" (formerly Vertex AI;
     ADC or API key)
- authenticate required: **yes** — `session/new` is refused until auth is known.
  - [observed] with no auth configured:
    ```
    {"code":-32000,"message":"Authentication required",
     "data":{"message":"No authentication method selected. Either call the `authenticate` method (supports oauth-personal, gemini-api-key, agent-platform), or set `auth.type` in settings.json (<HOME>/.gemini/antigravity-acp/settings.json) to one of: oauth-personal, gemini-api-key (requires GEMINI_API_KEY env var), oauth-business ..., agent-platform ..., gateway (...)."}}
    ```
  - [observed] `authenticate {"methodId":"gemini-api-key"}` → `{}` (accepted),
    persists `{"auth":{"type":"gemini-api-key"}}` into settings.json, and the
    *next* `session/new` then fails with `-32000`
    "auth.type is set to 'gemini-api-key' ... but the GEMINI_API_KEY environment
    variable is not set."
  - [observed] `authenticate {"methodId":"nope"}` →
    `{"code":-32602,"message":"Unsupported auth method: 'nope'","data":null}`.
  - [observed] `authenticate {"methodId":"oauth-personal"}` does **not** return:
    it prints the Google consent URL to stderr
    (`https://accounts.google.com/o/oauth2/v2/auth?...redirect_uri=http://127.0.0.1:36429/...pkce...`),
    tries to open a browser (on this box `snap-confine` fails), and the request
    stays pending until a human completes the flow (>25 s, then the probe was
    killed). Do not call it from TeamPilot's non-interactive path.
  - [observed] Pre-seeding `settings.json` with `{"auth":{"type":"gemini-api-key"}}`
    plus `GEMINI_API_KEY` (a dummy value is enough) lets `session/new` succeed;
    the key is only validated on the first model call.
- session/new configOptions: **[observed]** (with `gemini-api-key` auth)
  - `modes`: `default` / `auto_edit` / `yolo` (current `default`).
  - `configOptions` (ACP session config options):
    - `model` (category `model`, type select, current `gemini-3.8-flash`):
      `gemini-3.8-flash`, `gemini-3.7-flash`, `gemini-3.6-flash`,
      `gemini-3.5-flash`, `gemini-3.1-pro`.
    - `thinking_level` (category `thought_level`, current `high`):
      `low`, `medium`, `high` — the offered set is model-dependent; after
      selecting `gemini-3.1-pro` only `low`/`high` remained.
    - `mode` (category `mode`, current `default`): same three modes.
  - Legacy `models.availableModels` (14 flat ids) and
    `models.currentModelId = "gemini-3.8-flash-high"` are still emitted:
    `gemini-3.8-flash-{high,medium,low}`, `3.7-…`, `3.6-…`, `3.5-…`,
    `gemini-3.1-pro-{high,low}`.
  - [source] `config_options.py`: model families collapse thinking-level
    variants into one `model` entry + `thinking_level`; the flat list is kept for
    pre-config-options clients.
- session/new model honored: **no for a `model` field; yes for
  `AGY_ACP_DEFAULT_MODEL`**
  - [observed] `session/new` with an extra top-level `"model":"gemini-3.1-pro"`
    was accepted without error and had **no effect**: `currentModelId` stayed
    `gemini-3.8-flash-high`. (The ACP `NewSessionRequest` carries no model field,
    so the value is simply ignored.)
  - [observed] `AGY_ACP_DEFAULT_MODEL=gemini-3.8-flash-medium` in the server env
    changed `models.currentModelId` to `gemini-3.8-flash-medium` and
    `configOptions[thinking_level].currentValue` to `medium`.
  - [observed] Per-session selection works over ACP:
    `session/set_config_option {"configId":"model","value":"gemini-3.1-pro"}`
    → returns full `configOptions` with `model.currentValue = gemini-3.1-pro`
    (and the `thinking_level` option list re-narrowed to `low`,`high`).
    `session/set_config_option {"configId":"nope"}` →
    `{"code":-32602,"message":"Unknown config option id: nope"}`.
- session/new mcpServers honored: **yes**
  - [observed] `session/new` with one stdio server
    (`{"name":"probe","command":"/usr/bin/python3","args":["/tmp/agy-acp/mcp_stub.py"],"env":[]}`)
    spawned the stub right after the response. The stub received, in order:
    `server/discover` (with `_meta.io.modelcontextprotocol/protocolVersion`
    `"2026-07-28"`), `initialize` (`protocolVersion:"2025-11-25"`,
    `clientInfo:{name:"antigravity-client",version:"v1.0.0"}`),
    `notifications/initialized`.
  - [source] `mcp_servers.py` accepts Stdio/Http/Sse entries and also merges
    global MCP config; `_meta.antigravity.eagerMcpServers` and
    `_meta.antigravity.mcpMaxOutputBytes` are extra knobs.
- session/load: **supported** (`agentCapabilities.loadSession: true`)
  - [observed] `session/load {sessionId, cwd, mcpServers}` on a live session
    returned exactly `{"modes":…,"configOptions":…,"models":…}` — no `sessionId`
    echo — and subsequent `session/prompt` on the same id worked
    (`stopReason:"end_turn"`).
  - [observed] `session/load` **replays the transcript** before answering: it
    emitted `session/update` with `user_message_chunk` (`"hi"`), then
    `available_commands_update`, then the result. A client that also renders
    its own stored history will duplicate messages unless it treats the replay
    as authoritative.
  - Resuming a *persisted* session in a fresh process was not exercised
    [not tested].
- session/list: **supported** (`agentCapabilities.sessionCapabilities.list`)
  - [observed] before any session: `{"sessions":[]}`.
  - [observed] after `session/new`:
    `{"sessions":[{"sessionId":"bb972c18-…","cwd":"/tmp/agy-acp","title":"Session bb972c18"}]}`
    (no `updatedAt`/`mtime` fields observed).
- usage_update payload: **[observed]** `session/update` notification, sent once
  immediately after `session/new` and again after turns that consume tokens:
  ```json
  {"jsonrpc":"2.0","method":"session/update","params":{
    "sessionId":"…",
    "update":{"used":0,"size":1048576,"sessionUpdate":"usage_update"}}}
  ```
  [source] `size` comes from `get_context_window_size(model_id)`; `used` is the
  per-turn *context* delta, not the cumulative total, and the notification is
  skipped when the model's window is unknown. A second notification observed
  right after `session/new` is
  `available_commands_update` with `plan`, `logout`, `usage`.
- session/cancel behavior: **[observed]** it is a notification (no `id`, no
  response, no error) and it cancels the in-flight turn:
  - Prompt still running → `session/cancel {"sessionId": …}` after 0.3 s gave
    ```
    session/update: {"content":{"text":"The request was cancelled by the client.","type":"text"},"sessionUpdate":"agent_message_chunk"}
    session/prompt result: {"stopReason":"cancelled"}
    ```
  - Cancel after the turn had already ended → nothing on the wire (no error).
- cold start seconds: **[observed]** process start → `initialize` result was
  1.5–2.9 s across six fresh-HOME runs on this host (≈1.8 s typical; the
  spread is start-up jitter — no attempt was made to attribute it).
  `session/new` itself answered in ~0.1 s once auth was configured; a real
  harness conversation adds its own time [not tested for a live turn].
- notes:
  - **`localharness_external` is required next to the `.par`.** [observed]
    launching a lone `agy_acp_server.par` (symlink) gave
    `session/new` → `{"code":-32603,"message":"Internal error","data":{"details":"Could not find default localharness binary. Please specify binary_path explicitly, set the ANTIGRAVITY_HARNESS_PATH environment variable, or ensure it is in your PATH. ..."}}`
    `initialize` still succeeds, so this fails only at session creation.
    [source] `main.py::_configure_localharness_path` looks for
    `localharness_external` (or `localharness`; `.exe` on Windows) in the
    executable's directory unless `ANTIGRAVITY_HARNESS_PATH` is set.
    Adapter acquisition must download/extract **both** zip entries and keep
    them in the same directory.
  - **Auth failures on the model call are not JSON-RPC errors.** [observed]
    with a dummy key, `session/prompt` returned
    `agent_message_chunk` text "API key not valid. Please pass a valid API key."
    and `{"stopReason":"end_turn"}`. So `stopReason` is `end_turn`, not an
    error/auth-required stop; a translator that only inspects `stopReason`
    cannot detect an auth failure.
  - **`SURFACE` has no effect on the ACP server.** [observed+source] a
    case-sensitive grep of the shipped `antigravity_extensions/acp_server`
    sources finds no `SURFACE` read; the only environment variables read are
    `GEMINI_HOME`, `AGY_ACP_DEFAULT_MODEL`, `AGY_ACP_ENABLE_OAUTH`,
    `ANTIGRAVITY_HARNESS_PATH`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`/
    `GOOGLE_CLOUD_PROJECT`/`GOOGLE_CLOUD_LOCATION` (agent-platform),
    `AGY_LLM_GATEWAY_*`, `AGY_ACP_DISABLE_WORKSPACE_TRUST` and
    `OAUTHLIB_RELAX_TOKEN_SCOPE`. Whether the opaque `localharness_external`
    binary reads `SURFACE` was not tested.
  - `--uid` is a Google runtime privilege-drop flag, **not** an account
    selector: passing an arbitrary persisted string is fatal (see above). Launch
    with no arguments on hosts that have group `nobody`, or `--uid=` on hosts
    that do not. There is no per-account launch contract in 1.4.3.
  - `session/new` does not require workspace trust; the trust file
    (`<home>/antigravity-acp/trusted_workspaces.json`) is only consulted by the
    hooks path [source]. `AGY_ACP_DISABLE_WORKSPACE_TRUST` exists.
  - Extra positional arguments are rejected by `main()`:
    `raise app.UsageError("Too many command-line arguments.")` [source].

## Evidence & method

1. `client/tool/antigravity_acp_probe.dart` (this repo, unmodified from the
   brief) run as
   `dart run tool/antigravity_acp_probe.dart /tmp/agy-acp/extracted/agy_acp_server.par`
   — 86 s, transcript in the appendix (Run A). Because the script cannot pass
   `--uid=`, the adapter died at startup on this host and only the outbound
   requests appear.
2. A throwaway JSON-RPC driver in `/tmp/agy-acp/` (`drive*.py`, not committed)
   launched the same binary with `--uid=`, a temp `HOME`/`USERPROFILE`, and
   spoke line-delimited JSON-RPC so responses could be matched by `id`. Runs B–J
   below. Auth was configured either via `settings.json`
   (`{"auth":{"type":"gemini-api-key"}}` + dummy `GEMINI_API_KEY`) or left unset
   to capture the auth error.
3. `strace` over `initialize` to check for real-home reads (see HOME isolation).
4. The 1.4.3 `.par` was also extracted (`unzip -o`) and the shipped Python
   package `google3/cloud/developer_experience/antigravity_extensions/acp_server/`
   was read for cross-checks. Anything marked **[source]** is *read*, not
   executed, and should be treated as weaker evidence than **[observed]**.

No Antigravity login was available, so no real model turn was exercised: token
counts, `usage_update` values during a live turn, tool calls/permissions, and
`session/load` of a persisted session remain **unverified**.

## Appendix — raw transcripts (trimmed paths, no key values)

Run A — committed probe script, no `--uid`:
```
>> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}
F1028 09:54:14.370595 1563401 init_google.cc:396] Check failed: LookupGIDByGroupName(groupname, &new_gid)  Group nobody not found
>> {"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"…/client","mcpServers":[]}}
>> {"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"probe","prompt":[{"type":"text","text":"Reply with exactly: ok"}]}}
HOME=/tmp/agy-probe-home-VFXDLR
```

Run B — no auth configured (`--uid=`):
```
<< {"jsonrpc":"2.0","id":1,"result":{…initialize as above…}}
>> session/list {}
<< {"jsonrpc":"2.0","id":2,"result":{"sessions":[]}}
>> session/new {"cwd":"/tmp/agy-acp","mcpServers":[]}
<< {"jsonrpc":"2.0","id":3,"error":{"code":-32000,"message":"Authentication required","data":{"message":"No authentication method selected. … set `auth.type` in settings.json (/tmp/agy-drive-home-2uynw6tg/.gemini/antigravity-acp/settings.json) …"}}}
```

Run C — `auth.type=gemini-api-key` + dummy `GEMINI_API_KEY`:
```
>> session/new {"cwd":"/tmp/agy-acp","mcpServers":[]}
<< {"jsonrpc":"2.0","id":2,"result":{"sessionId":"bb972c18-0305-45b2-9c12-ffe436b87c1c",
    "modes":{"currentModeId":"default","availableModes":[{"id":"default",…},{"id":"auto_edit",…},{"id":"yolo",…}]},
    "configOptions":[
      {"id":"model","name":"Model","category":"model","type":"select","currentValue":"gemini-3.8-flash",
       "options":["gemini-3.8-flash","gemini-3.7-flash","gemini-3.6-flash","gemini-3.5-flash","gemini-3.1-pro"]},
      {"id":"thinking_level","name":"Thinking Level","category":"thought_level","type":"select","currentValue":"high",
       "options":["low","medium","high"]},
      {"id":"mode","name":"Session Mode","category":"mode","type":"select","currentValue":"default",…}],
    "models":{"availableModels":[{"modelId":"gemini-3.8-flash-high",…},…],"currentModelId":"gemini-3.8-flash-high"}}}
<< session/update {"update":{"used":0,"size":1048576,"sessionUpdate":"usage_update"}}
<< session/update {"update":{"availableCommands":[{"name":"plan",…},{"name":"logout",…},{"name":"usage",…}],"sessionUpdate":"available_commands_update"}}
>> session/list {}
<< {"jsonrpc":"2.0","id":3,"result":{"sessions":[{"sessionId":"bb972c18-…","cwd":"/tmp/agy-acp","title":"Session bb972c18"}]}}
>> session/prompt {"sessionId":"bb972c18-…","prompt":[{"type":"text","text":"Reply with exactly: ok"}]}
<< session/update {"update":{"content":{"text":"API key not valid. Please pass a valid API key.","type":"text"},"sessionUpdate":"agent_message_chunk"}}
<< {"jsonrpc":"2.0","id":4,"result":{"stopReason":"end_turn"}}
```

Run D — cancel an in-flight turn (dummy key, cancel after 0.3 s):
```
>> session/prompt …
<< session/update {"update":{"content":{"text":"The request was cancelled by the client.","type":"text"},"sessionUpdate":"agent_message_chunk"}}
<< {"jsonrpc":"2.0","id":3,"result":{"stopReason":"cancelled"}}
```

Run E — `session/load` of the just-created session:
```
>> session/load {"sessionId":"97d8a437-…","cwd":"/tmp/agy-acp","mcpServers":[]}
<< session/update {"sessionId":"…","update":{"content":{"text":"hi","type":"text"},"sessionUpdate":"user_message_chunk"}}
<< session/update {"sessionId":"…","update":{"availableCommands":[…],"sessionUpdate":"available_commands_update"}}
<< {"jsonrpc":"2.0","id":4,"result":{"modes":…,"configOptions":…,"models":…}}
>> session/prompt {"sessionId":"97d8a437-…",…}
<< {"jsonrpc":"2.0","id":5,"result":{"stopReason":"end_turn"}}
```

Run F — `session/set_config_option`:
```
>> {"configId":"model","value":"gemini-3.1-pro"}
<< {"id":3,"result":{"configOptions":[{"id":"model","currentValue":"gemini-3.1-pro",…},
     {"id":"thinking_level","currentValue":"high","options":[{"value":"low",…},{"value":"high",…}]},…]}}
>> {"configId":"nope","value":"x"}
<< {"id":5,"error":{"code":-32602,"message":"Unknown config option id: nope","data":null}}
```

Run G — stdio MCP server supplied in `session/new` (stub log):
```
{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/clientCapabilities":{…},"io.modelcontextprotocol/clientInfo":{"name":"antigravity-client","version":"v1.0.0"},"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}
{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"clientInfo":{"name":"antigravity-client","version":"v1.0.0"},"protocolVersion":"2025-11-25","capabilities":{"elicitation":{…},"roots":{"listChanged":true}}}}
{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}
```

Run H — lone `.par` without `localharness_external`:
```
>> session/new {"cwd":"/tmp/agy-acp","mcpServers":[]}
<< {"jsonrpc":"2.0","id":2,"error":{"code":-32603,"message":"Internal error","data":{"details":"Could not find default localharness binary. Please specify binary_path explicitly, set the ANTIGRAVITY_HARNESS_PATH environment variable, or ensure it is in your PATH. …"}}}
```

Run I — `--uid` variants / unknown flag:
```
$ agy_acp_server.par                     → F1028 … Group nobody not found
$ agy_acp_server.par --uid=              → initialize result (ok)
$ agy_acp_server.par --uid=abc-123       → F1028 … Group abc-123 not found
$ agy_acp_server.par --uid= --bogus-flag=1 → FATAL Flags parsing error: Unknown command line flag 'bogus-flag'
```

Run J — fresh-HOME side effects after one successful `session/new`:
```
.gemini/antigravity/bin/webm_encoder                         16851235
.gemini/antigravity-acp/settings.json                              34
.gemini/antigravity-acp/conversations/<id>.db                  458752
.gemini/antigravity-acp/conversations/<id>.meta                    27
.gemini/antigravity-acp/brain/<id>/.system_generated/logs/transcript.jsonl
.gemini/antigravity-acp/brain/<id>/.system_generated/logs/transcript_full.jsonl
```
