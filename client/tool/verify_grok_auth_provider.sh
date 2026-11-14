#!/bin/sh
# Verifies that grok's External Auth Provider is invoked by `grok agent stdio`
# (ACP/headless), not just by the TUI / `grok -p`.
#
# Usage: sh client/tool/verify_grok_auth_provider.sh
#
# Each probe gets a FRESH GROK_HOME: a successful `grok -p` persists the minted
# token to <GROK_HOME>/auth.json, so reusing one home would let the ACP probes
# run on cached credentials and never call the provider (a false negative).
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

SHIM="$TMP/auth-provider.sh"
CALLS="$TMP/calls.log"

# Unquoted heredoc: $CALLS must expand NOW, while GROK_AUTH_EXPIRED must stay
# a runtime reference (escaped) so the log records what grok passed in.
cat > "$SHIM" <<EOS
#!/bin/sh
echo "called GROK_AUTH_EXPIRED=\${GROK_AUTH_EXPIRED:-unset}" >> "$CALLS"
# stdout MUST contain only the token JSON
printf '%s\n' '{"access_token":"probe-token","expires_in":3600}'
EOS
chmod +x "$SHIM"

fresh_home() {
  home="$TMP/home-$1"
  mkdir -p "$home"
  cat > "$home/config.toml" <<EOT
[auth]
auth_provider_command = "$SHIM"
EOT
  printf '%s\n' "$home"
}

# grep -c prints 0 and exits non-zero when there is no match; `|| true` keeps
# that 0 on one line. `grep -c ... || echo 0` would emit "0\n0" and break the
# integer comparison below.
count_calls() {
  grep -c 'called' "$CALLS" 2>/dev/null || true
}

# 1) Headless one-shot: must invoke the provider (baseline for the feature).
HOME_ONESHOT=$(fresh_home oneshot)
: > "$CALLS"
GROK_HOME="$HOME_ONESHOT" timeout 25 grok -p "say hi" \
  >"$TMP/oneshot.out" 2>"$TMP/oneshot.err" || true
ONESHOT=$(count_calls)
ONESHOT=${ONESHOT:-0}

# 2) ACP stdio without authenticate: session/new is expected to be rejected,
#    so the provider is NOT expected to be called here.
HOME_BARE=$(fresh_home acp-bare)
: > "$CALLS"
{
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"%s","mcpServers":[]}}\n' "$TMP"
  sleep 2
} | GROK_HOME="$HOME_BARE" timeout 25 grok agent --no-leader stdio \
  >"$TMP/acp-bare.out" 2>"$TMP/acp-bare.err" || true
ACP_BARE=$(count_calls)
ACP_BARE=${ACP_BARE:-0}

# 3) ACP stdio with the protocol's auth step: initialize -> authenticate ->
#    session/new. This is the flow a real ACP client uses when the agent
#    reports authMethods. Keep stdin open long enough for each reply.
HOME_ACP=$(fresh_home acp-auth)
: > "$CALLS"
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
ACP=$(count_calls)
ACP=${ACP:-0}

AUTH_MODE=missing
if [ -f "$HOME_ACP/auth.json" ] &&
  grep -q '"auth_mode": "external"' "$HOME_ACP/auth.json"; then
  AUTH_MODE=external
fi

SESSION_OK=no
if grep -q '"id":3,"result":{"sessionId"' "$TMP/acp.out"; then
  SESSION_OK=yes
fi

if [ "$ACP" -gt 0 ]; then
  RESULT=yes
else
  RESULT=no
fi

cat > "$OUT" <<EOM
# Grok External Auth Provider — ACP Risk Gate

- 日期：2026-11-14
- grok 版本：$(grok --version 2>/dev/null | head -1)
- \`grok -p\` 回调次数：$ONESHOT
- \`grok agent stdio\` 裸 \`session/new\`（无 authenticate）回调次数：$ACP_BARE
- \`grok agent stdio\`（initialize → authenticate → session/new）回调次数：$ACP
- ACP authenticate 后 \`auth.json\` 的 auth_mode：$AUTH_MODE
- ACP authenticate 后 \`session/new\` 成功：$SESSION_OK
- **GROK_AUTH_PROVIDER_ACP_SUPPORTED=$RESULT**

判定：\`yes\` → 执行 Task 2–7 主路径；\`no\` → 执行 Task 5 时改用附录 B 的降级适配器，
跳过 Task 5 中「注入 GROK_AUTH_PROVIDER_COMMAND」的步骤。

## 结论说明

ACP 下 External Auth Provider **可用**，但只走 ACP 的认证步骤：
\`session/new\` 在未认证时直接返回 \`Authentication required / no auth method id provided\`，
此时不会回调 \`auth_provider_command\`；客户端先发
\`authenticate {"methodId":"grok.com"}\`，grok 才会执行 provider、把
\`access_token\` 以 \`auth_mode: "external"\` 写入 \`<GROK_HOME>/auth.json\`，
随后的 \`session/new\` 成功。

对 Task 5 的要求：ACP 客户端必须在 initialize 后处理认证（发送上述
\`authenticate\`，或预置带同一 token 的 \`auth.json\`），否则会话创建会停在
auth-required，provider 永远不会被调用。

另：\`grok -p\` 会把 provider 换来的 token 持久化到 \`auth.json\`；本脚本因此为每个
探针使用独立的 \`GROK_HOME\`，避免 cached-token 掩盖 ACP 侧的真实行为。

<details><summary>grok agent stdio stderr（authenticate 流程）</summary>

\`\`\`
$(head -40 "$TMP/acp.err" 2>/dev/null)
\`\`\`

</details>
EOM

echo "GROK_AUTH_PROVIDER_ACP_SUPPORTED=$RESULT (wrote $OUT)"
