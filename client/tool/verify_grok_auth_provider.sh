#!/bin/sh
# Verifies that grok's External Auth Provider is invoked by `grok agent stdio`
# (ACP/headless), not just by the TUI / `grok -p`.
#
# Usage: sh client/tool/verify_grok_auth_provider.sh
#
# Each probe gets its OWN GROK_HOME *and* its OWN call log, so a token refresh
# or a leftover process can never be counted against another probe. The one
# shot also pins [cli] use_leader = false because `grok -p` has no --no-leader
# flag; a shared leader would otherwise see the same shim path and config.
#
# Each probe also gets a fresh home because a successful `grok -p` persists the
# minted token to <GROK_HOME>/auth.json; reusing a home would let the ACP probes
# run on cached credentials and never call the provider.
#
# ACP owns an auth step: `session/new` alone is rejected with "Authentication
# required" until the client sends `authenticate`. So the ACP probe that can
# actually exercise the provider is initialize -> authenticate -> session/new;
# the bare session/new probe is kept to document that gate.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT="$ROOT/docs/superpowers/plans/2026-11-14-grok-credential-authority-gate.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Environment guard: never report a verdict from a host that cannot run grok.
GROK_ERR=""
GROK_VERSION=""
if command -v grok >/dev/null 2>&1; then
  if GROK_VERSION=$(grok --version 2>&1); then
    GROK_VERSION=$(printf '%s\n' "$GROK_VERSION" | head -1)
  else
    GROK_ERR="\`grok --version\` failed: $GROK_VERSION"
  fi
else
  GROK_ERR="\`grok\` not found in PATH"
fi

if [ -n "$GROK_ERR" ]; then
  cat > "$OUT" <<EOM
# Grok External Auth Provider — ACP Risk Gate

- 日期：2026-11-14
- grok 版本：unavailable
- 错误：$GROK_ERR
- **GROK_AUTH_PROVIDER_ACP_SUPPORTED=BLOCKED**

判定：\`BLOCKED\` 表示本机无法执行 grok，未做任何探针，不能据此选择 Task 5 的主路径
或附录 B。修复 grok 环境后重新运行本脚本。
EOM
  echo "GROK_AUTH_PROVIDER_ACP_SUPPORTED=BLOCKED ($GROK_ERR; wrote $OUT)" >&2
  exit 1
fi

# One home, one shim, one call log per probe.
fresh_home() {
  home="$TMP/home-$1"
  mkdir -p "$home"
  # Unquoted heredoc: $home must expand NOW; GROK_AUTH_EXPIRED must stay a
  # runtime reference (escaped) so the log records what grok actually passed.
  cat > "$home/auth-provider.sh" <<EOS
#!/bin/sh
echo "called GROK_AUTH_EXPIRED=\${GROK_AUTH_EXPIRED:-unset}" >> "$home/calls.log"
# stdout MUST contain only the token JSON
printf '%s\n' '{"access_token":"probe-token","expires_in":3600}'
EOS
  chmod +x "$home/auth-provider.sh"
  cat > "$home/config.toml" <<EOT
[cli]
use_leader = false

[auth]
auth_provider_command = "$home/auth-provider.sh"
EOT
  printf '%s\n' "$home"
}

# grep -c prints 0 and exits non-zero when there is no match; `|| true` keeps
# that 0 on one line. `grep -c ... || echo 0` would emit "0\n0" and break the
# integer comparison below.
count_calls() {
  grep -c 'called' "$1/calls.log" 2>/dev/null || true
}

# 1) Headless one-shot: baseline that the provider works outside ACP.
HOME_ONESHOT=$(fresh_home oneshot)
GROK_HOME="$HOME_ONESHOT" timeout 25 grok -p "say hi" \
  >"$TMP/oneshot.out" 2>"$TMP/oneshot.err" || true
ONESHOT=$(count_calls "$HOME_ONESHOT")
ONESHOT=${ONESHOT:-0}

# 2) ACP stdio without authenticate: session/new is expected to be rejected,
#    so the provider is NOT expected to be called here.
HOME_BARE=$(fresh_home acp-bare)
{
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"%s","mcpServers":[]}}\n' "$TMP"
  sleep 2
} | GROK_HOME="$HOME_BARE" timeout 25 grok agent --no-leader stdio \
  >"$TMP/acp-bare.out" 2>"$TMP/acp-bare.err" || true
ACP_BARE=$(count_calls "$HOME_BARE")
ACP_BARE=${ACP_BARE:-0}

BARE_RESULT=no-response
if grep -q 'Authentication required' "$TMP/acp-bare.out"; then
  BARE_RESULT=auth-required
elif grep -q '"id":2,"result"' "$TMP/acp-bare.out"; then
  BARE_RESULT=session-created
fi

# 3) ACP stdio with the protocol's auth step: initialize -> authenticate ->
#    session/new. This is the flow a real ACP client uses when the agent
#    reports authMethods. Keep stdin open long enough for each reply.
HOME_ACP=$(fresh_home acp-auth)
{
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  sleep 1
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"authenticate","params":{"methodId":"grok.com"}}'
  sleep 5
  printf '{"jsonrpc":"2.0","id":3,"method":"session/new","params":{"cwd":"%s","mcpServers":[]}}\n' "$TMP"
  sleep 4
} | GROK_HOME="$HOME_ACP" timeout 30 grok agent --no-leader stdio \
  >"$TMP/acp.out" 2>"$TMP/acp.err" || true
ACP=$(count_calls "$HOME_ACP")
ACP=${ACP:-0}

AUTH_MODE=missing
if [ -f "$HOME_ACP/auth.json" ]; then
  AUTH_MODE=other
  if grep -q '"auth_mode": "external"' "$HOME_ACP/auth.json"; then
    AUTH_MODE=external
  fi
fi

SESSION_OK=no
if grep -q '"id":3,"result":{"sessionId"' "$TMP/acp.out"; then
  SESSION_OK=yes
fi

# Consistency assertion: a call count alone can be contaminated by a retry or
# a leftover process, so `yes` also requires the ACP home to hold the token the
# provider minted, recorded as auth_mode=external.
REASON=""
if [ "$ACP" -gt 0 ]; then
  if [ "$AUTH_MODE" = external ]; then
    RESULT=yes
  else
    RESULT=no
    REASON="ACP shim was invoked ($ACP time(s)) but the ACP home's auth.json did not record auth_mode=external (observed: $AUTH_MODE)"
  fi
else
  RESULT=no
  REASON="auth_provider_command was not invoked during the ACP authenticate run (0 call(s); ACP auth.json: $AUTH_MODE)"
fi

if [ "$RESULT" = yes ]; then
  CONCLUSION="ACP 下 External Auth Provider 可用：本次运行在 authenticate 步骤观察到 \`auth_provider_command\` 被调用（$ACP 次），其 token 以 \`auth_mode: \"external\"\` 写入 ACP home 的 \`auth.json\`，随后 \`session/new\` 成功=$SESSION_OK。裸 \`session/new\`（无 authenticate）回调 $ACP_BARE 次，本次返回 $BARE_RESULT。对 Task 5 的要求：ACP 客户端必须在 initialize 后处理认证（发送 \`authenticate {\"methodId\":\"grok.com\"}\`，或预置带同一 token 的 \`auth.json\`），否则会话创建会停在 auth-required，provider 不会被调用。"
else
  if [ "$ACP" -gt 0 ]; then
    CONCLUSION="本次运行的判定输入不一致：ACP 流程中 shim 被调用 $ACP 次，但 ACP home 的 \`auth.json\` 未记录 \`auth_mode: \"external\"\`（观察到：$AUTH_MODE）。按保守原则判为 no：不能据此确认 ACP 会正常采用 External Auth Provider。session/new 成功=$SESSION_OK。"
  else
    CONCLUSION="本次运行未观察到 \`auth_provider_command\` 在 ACP authenticate 流程中被调用（0 次；裸 session/new 回调 $ACP_BARE 次，本次返回 $BARE_RESULT；ACP home 的 auth.json：$AUTH_MODE；session/new 成功=$SESSION_OK）。按本门禁语义判为 no：不应假设 ACP 会回调 External Auth Provider。原因记录：$REASON"
  fi
fi

cat > "$OUT" <<EOM
# Grok External Auth Provider — ACP Risk Gate

- 日期：2026-11-14
- grok 版本：$GROK_VERSION
- \`grok -p\` 回调次数：$ONESHOT
- \`grok agent stdio\` 裸 \`session/new\`（无 authenticate）回调次数：$ACP_BARE，结果：$BARE_RESULT
- \`grok agent stdio\`（initialize → authenticate → session/new）回调次数：$ACP
- ACP authenticate 后 \`auth.json\` 的 auth_mode：$AUTH_MODE
- ACP authenticate 后 \`session/new\` 成功：$SESSION_OK
- **GROK_AUTH_PROVIDER_ACP_SUPPORTED=$RESULT**

判定：\`yes\` → 执行 Task 2–7 主路径；\`no\` → 执行 Task 5 时改用附录 B 的降级适配器，
跳过 Task 5 中「注入 GROK_AUTH_PROVIDER_COMMAND」的步骤。

## 结论说明

$CONCLUSION

另：\`grok -p\` 会把 provider 换来的 token 持久化到 \`auth.json\`；本脚本因此为每个
探针使用独立的 \`GROK_HOME\` 和独立的 call log，避免 cached-token 或跨探针重试污染判定。

<details><summary>grok agent stdio stderr（authenticate 流程）</summary>

\`\`\`
$(head -40 "$TMP/acp.err" 2>/dev/null)
\`\`\`

</details>
EOM

echo "GROK_AUTH_PROVIDER_ACP_SUPPORTED=$RESULT (wrote $OUT)"
