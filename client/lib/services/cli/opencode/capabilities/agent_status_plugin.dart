/// 写入成员 opencode 配置目录的 agent-status 上报 plugin（JS）。
///
/// 与 [opencodeIdlePluginFileName] 并列：idle 仅 mixed 模式上报 `/idle`；
/// 本 plugin 在 simple/team 只要 `agentStatus != null` 就安装，POST `/agent-status`。
///
/// On `question.asked`, also polls `GET /ask-user-answer?request_id=` and calls
/// OpenCode SDK `client.question.reply` / `client.question.reject` when the SDK
/// exposes them; otherwise delivers over the OpenCode HTTP API
/// (`POST /question/{requestID}/reply|reject`).
///
/// SDK note: the plugin `input.client` (`createOpencodeClient` from
/// `@opencode-ai/sdk`) is the **v1** client, which has **no `question` member**
/// (verified 1.18.x and current main) — `client.question.reply` throws and the
/// answer silently never reaches OpenCode. The v2 SDK (`@opencode-ai/sdk/v2`)
/// does expose `question.reply({ requestID, answers? })` with the flat shape
/// (HTTP `POST /question/{requestID}/reply|reject`); prefer it when present.
///
/// Fallback must route through the client's own request pipeline
/// (`client._client.post`), **not** a raw `fetch(input.serverUrl)`:
/// in the default TUI mode (`opencode` without `--port`/`--hostname`/mdns) the
/// server never binds a TCP port — HTTP is handled in-process via the worker
/// RPC bridge, and `input.serverUrl` is a dead `http://localhost:4096`
/// (checked against opencode 1.18.4 `cli/cmd/tui.ts`).
const opencodeAgentStatusPluginFileName = 'teampilot-agent-status.js';

const opencodeAgentStatusPluginSource = r'''
export const TeampilotAgentStatus = async (input, options) => {
  const client = input?.client;
  const member = options?.member ?? process.env.TEAMPILOT_MEMBER;
  const url =
    options?.url ??
    process.env.TEAMPILOT_AGENT_STATUS_URL ??
    (process.env.TEAMPILOT_BUS_PORT
      ? `http://127.0.0.1:${process.env.TEAMPILOT_BUS_PORT}/agent-status`
      : null);
  const token = options?.token ?? process.env.TEAMPILOT_BUS_TOKEN;
  const session = options?.session ?? process.env.TEAMPILOT_SESSION;
  // Prefer explicit port (idle plugin); else TEAMPILOT_BUS_PORT; else parse
  // from agent-status url so poll works when only `url` is stamped.
  let port = options?.port ?? process.env.TEAMPILOT_BUS_PORT ?? null;
  if (!port && url) {
    try {
      port = new URL(url).port || null;
    } catch (_) {}
  }
  const headers = {
    "Content-Type": "application/json",
    "X-Member": String(member),
  };
  if (session) headers["X-Session"] = String(session);
  if (token) headers["X-Bus-Token"] = String(token);

  const post = async (eventName, payload = {}) => {
    if (!member || !url) return;
    await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify({ event: eventName, ...payload }),
    }).catch(() => {});
  };

  // Requests resolved outside the pending store (answered in the native TUI,
  // rejected, HTTP API, …). The poll loop stops and never posts
  // reply_failed once opencode itself published replied/rejected.
  const resolvedRequests = new Set();
  const resolveRequest = (requestId) => {
    if (requestId) resolvedRequests.add(String(requestId));
  };
  const isResolved = (requestId) => resolvedRequests.has(String(requestId));

  // User message commit tracking: message ids whose role is "user" (learned
  // from `message.updated`) and text part ids already forwarded, so each user
  // submission is reported exactly once and assistant parts are never sent.
  const userMessageIds = new Set();
  const forwardedUserParts = new Set();

  // Attention TTL — keep polling until the human can still answer.
  const ASK_POLL_TTL_MS = 30 * 60 * 1000;
  const ASK_POLL_INTERVAL_MS = 400;

  // Deliver the user's answer back into OpenCode. The plugin `input.client`
  // is the v1 SDK client, which has no `question` member (see file comment);
  // prefer the SDK call when a future version exposes it, otherwise POST the
  // OpenCode HTTP API through the client's own request pipeline (`_client`).
  // The pipeline keeps this runtime's fetch (in-process RPC bridge in default
  // TUI mode) and auth headers; a raw `fetch(input.serverUrl)` would hit a
  // dead `http://localhost:4096` because no TCP listener exists.
  const deliverQuestionReply = async (requestId, body) => {
    if (client?.question?.reply) {
      if (body.reject) {
        await client.question.reject({ requestID: requestId });
      } else {
        await client.question.reply({
          requestID: requestId,
          answers: body.answers,
        });
      }
      return;
    }
    const action = body.reject ? "reject" : "reply";
    const raw = client?._client;
    if (raw?.post) {
      const result = await raw.post({
        url: `/question/${encodeURIComponent(requestId)}/${action}`,
        headers: { "Content-Type": "application/json" },
        body: body.reject ? undefined : { answers: body.answers },
      });
      if (result?.error) {
        throw new Error(
          `opencode question ${action} failed: ${JSON.stringify(result.error)}`,
        );
      }
      return;
    }
    const serverUrl = input?.serverUrl ? String(input.serverUrl) : null;
    if (!serverUrl) throw new Error("no opencode serverUrl");
    const base = serverUrl.replace(/\/+$/, "");
    const r = await fetch(
      `${base}/question/${encodeURIComponent(requestId)}/${action}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: body.reject ? undefined : JSON.stringify({ answers: body.answers }),
      },
    );
    if (!r.ok) throw new Error(`opencode question ${action} HTTP ${r.status}`);
  };

  // Deliver an allow/deny reply for a permission request. Prefer the v2 SDK
  // `client.permission.reply` (flat requestID shape); fall back to the OpenCode
  // HTTP API through the client's own request pipeline (`_client`) — same rule
  // as deliverQuestionReply (dead serverUrl in default TUI mode).
  const deliverPermissionReply = async (requestId, body) => {
    const reply =
      body.permission_reply ?? (body.reject ? "reject" : "once");
    if (client?.permission?.reply) {
      await client.permission.reply({ requestID: requestId, reply });
      return;
    }
    const raw = client?._client;
    if (raw?.post) {
      const result = await raw.post({
        url: `/permission/${encodeURIComponent(requestId)}/reply`,
        headers: { "Content-Type": "application/json" },
        body: { reply },
      });
      if (result?.error) {
        throw new Error(
          `opencode permission reply failed: ${JSON.stringify(result.error)}`,
        );
      }
      return;
    }
    const serverUrl = input?.serverUrl ? String(input.serverUrl) : null;
    if (!serverUrl) throw new Error("no opencode serverUrl");
    const base = serverUrl.replace(/\/+$/, "");
    const r = await fetch(
      `${base}/permission/${encodeURIComponent(requestId)}/reply`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reply }),
      },
    );
    if (!r.ok) throw new Error(`opencode permission reply HTTP ${r.status}`);
  };

  const pollAndReply = async (requestId, kind = "question") => {
    if (!requestId || !port) return;
    const deadline = Date.now() + ASK_POLL_TTL_MS;
    let replyFailureReported = false;
    while (Date.now() < deadline && !isResolved(requestId)) {
      let status = 0;
      let body = null;
      try {
        const r = await fetch(
          `http://127.0.0.1:${port}/ask-user-answer?request_id=${encodeURIComponent(requestId)}`,
          { headers },
        );
        status = r.status;
        if (status === 200) {
          body = await r.json();
        }
      } catch (_) {
        // Transient bus/network error — keep polling until TTL.
      }
      if (status === 200 && body) {
        try {
          if (kind === "permission") {
            await deliverPermissionReply(requestId, body);
          } else {
            await deliverQuestionReply(requestId, body);
          }
        } catch (e) {
          // Delivery failed (v1 SDK without question, server down, auth, …).
          // Signal once so the chat restores the waiting card, then keep
          // polling: a re-answer stores a fresh entry under the same request
          // id and this loop delivers it.
          if (!replyFailureReported) {
            replyFailureReported = true;
            await post("question.reply_failed", {
              request_id: requestId,
              message: String(e),
            });
          }
          continue;
        }
        return;
      }
      await new Promise((res) => setTimeout(res, ASK_POLL_INTERVAL_MS));
    }
    // Resolved natively (TUI) — the answered signal already cleared the chat
    // card; never report a failure for a request opencode finished itself.
    if (isResolved(requestId)) return;
    // Poll deadline exceeded: always signal so Dart can restore waiting if the
    // user already answered (optimistic working) or keep recoverable UI.
    await post("question.reply_failed", {
      request_id: requestId,
      message: "ask-user-answer poll timed out",
    });
  };

  return {
    event: async ({ event }) => {
      if (!event || !event.type) return;
      // OpenCode resolved the request itself (native TUI answer, reject, HTTP
      // API, …): forward so the chat card clears immediately and the pending
      // poll stops. `replied`/`rejected` fire regardless of who answered.
      if (
        event.type === "question.replied" ||
        event.type === "question.v2.replied" ||
        event.type === "question.rejected" ||
        event.type === "question.v2.rejected"
      ) {
        const props = event.properties ?? event.data ?? {};
        const requestId =
          props.requestID ?? props.request_id ?? event.requestID ?? null;
        resolveRequest(requestId);
        if (!requestId) return;
        await post("question.answered", {
          request_id: requestId,
          session_id:
            props.sessionID ??
            props.session_id ??
            event.sessionID ??
            event.session_id ??
            null,
          rejected: event.type.endsWith("rejected") ? true : undefined,
        });
        return;
      }
      if (
        event.type === "permission.replied" ||
        event.type === "permission.v2.replied"
      ) {
        const props = event.properties ?? event.data ?? {};
        const requestId =
          props.requestID ?? props.request_id ?? event.requestID ?? null;
        resolveRequest(requestId);
        if (!requestId) return;
        await post("permission.answered", {
          request_id: requestId,
          session_id:
            props.sessionID ??
            props.session_id ??
            event.sessionID ??
            event.session_id ??
            null,
        });
        return;
      }
      if (event.type === "permission.asked") {
        // Forward the permission payload so the chat can render allow/deny
        // buttons. Path varies by opencode version: properties (SDK v1) vs
        // data vs the raw event fields (SDK v2).
        const props = event.properties ?? event.data ?? {};
        const requestId =
          props.id ?? props.request_id ?? event.id ?? event.request_id ?? null;
        const sessionID =
          props.sessionID ??
          props.session_id ??
          event.sessionID ??
          event.session_id ??
          null;
        const tool = props.tool ?? event.tool ?? null;
        await post("permission.asked", {
          request_id: requestId,
          session_id: sessionID,
          permission:
            props.permission ??
            props.description ??
            props.title ??
            event.permission ??
            null,
          patterns:
            props.patterns ??
            (props.pattern
              ? Array.isArray(props.pattern)
                ? props.pattern
                : [props.pattern]
              : null),
          always: props.always ?? event.always ?? null,
          tool: tool,
        });
        if (requestId) await pollAndReply(requestId, "permission");
        return;
      }
      if (event.type === "question.asked") {
        // Forward the question payload so the chat can render/answer it.
        // Path varies by opencode version: properties (SDK v1) vs data vs
        // the raw event fields (SDK v2).
        const props = event.properties ?? event.data ?? {};
        const questions = Array.isArray(props.questions)
          ? props.questions
          : Array.isArray(event.questions)
            ? event.questions
            : null;
        const requestId = props.id ?? props.request_id ?? null;
        const sessionID =
          props.sessionID ??
          props.session_id ??
          event.sessionID ??
          event.session_id ??
          null;
        await post("question.asked", {
          questions: questions,
          request_id: requestId,
          session_id: sessionID,
        });
        await pollAndReply(requestId);
        return;
      }
      // Clear waiting: idle plugin uses session.next.step.ended for /idle;
      // also accept session.idle for the normalizer's done signal.
      if (
        event.type === "session.next.step.ended" ||
        event.type === "session.idle"
      ) {
        await post("session.idle");
      }
      // User message commit: forward the submitted prompt text so the app can
      // ACK the PTY delivery (mirror of Claude UserPromptSubmit).
      //
      // Event shape verified empirically against opencode 1.18.4 (server
      // session subscribed via @opencode-ai/sdk while submitting a prompt):
      //   - `message.updated`  → properties.info.role === "user" fires when
      //     the user message is created, BEFORE its parts stream.
      //   - `message.part.updated` → properties.part (type "text", text)
      //     carries the user's submitted text; the part object has no role,
      //     so membership is decided by the user message id set below.
      // `session.updated` carries only session info (no parts), so it cannot
      // be used to observe the submitted text.
      if (event.type === "message.updated") {
        const props = event.properties ?? event.data ?? {};
        const info = props.info ?? {};
        if (info.role === "user" && info.id) {
          userMessageIds.add(String(info.id));
        }
        return;
      }
      if (event.type === "message.part.updated") {
        const props = event.properties ?? event.data ?? {};
        const part = props.part ?? {};
        if (
          part.type === "text" &&
          !part.synthetic &&
          part.messageID &&
          userMessageIds.has(String(part.messageID))
        ) {
          const text = typeof part.text === "string" ? part.text : "";
          if (text.trim() && !forwardedUserParts.has(String(part.id))) {
            forwardedUserParts.add(String(part.id));
            await post("userMessageSubmitted", { prompt: text });
          }
        }
        return;
      }
    },
  };
};
''';
