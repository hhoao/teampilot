/// 写入成员 opencode 配置目录的 agent-status 上报 plugin（JS）。
///
/// 与 [opencodeIdlePluginFileName] 并列：idle 仅 mixed 模式上报 `/idle`；
/// 本 plugin 在 simple/team 只要 `agentStatus != null` 就安装，POST `/agent-status`。
///
/// On `question.asked`, also polls `GET /ask-user-answer?request_id=` and calls
/// OpenCode SDK `client.question.reply` / `client.question.reject` when the SDK
/// exposes them; otherwise delivers over the raw HTTP API
/// (`POST /question/{requestID}/reply|reject`).
///
/// SDK note: the plugin `input.client` (`createOpencodeClient` from
/// `@opencode-ai/sdk`) is the **v1** client, which has **no `question` member**
/// (verified 1.18.x and current main) — `client.question.reply` throws and the
/// answer silently never reaches OpenCode. The v2 SDK (`@opencode-ai/sdk/v2`)
/// does expose `question.reply({ requestID, answers? })` with the flat shape
/// (HTTP `POST /question/{requestID}/reply|reject`); prefer it when present and
/// fall back to `fetch` against `input.serverUrl` (auth is only required when
/// `OPENCODE_SERVER_PASSWORD` is set, which TeamPilot launches never do).
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

  // Attention TTL — keep polling until the human can still answer.
  const ASK_POLL_TTL_MS = 30 * 60 * 1000;
  const ASK_POLL_INTERVAL_MS = 400;

  // Deliver the user's answer back into OpenCode. The plugin `input.client`
  // is the v1 SDK client, which has no `question` member (see file comment);
  // prefer the SDK call when a future version exposes it, otherwise POST the
  // OpenCode HTTP API directly on the server URL from `input.serverUrl`.
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
    const serverUrl = input?.serverUrl ? String(input.serverUrl) : null;
    if (!serverUrl) throw new Error("no opencode serverUrl");
    const base = serverUrl.replace(/\/+$/, "");
    const action = body.reject ? "reject" : "reply";
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

  const pollAndReply = async (requestId) => {
    if (!requestId || !port) return;
    const deadline = Date.now() + ASK_POLL_TTL_MS;
    let replyFailureReported = false;
    while (Date.now() < deadline) {
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
          await deliverQuestionReply(requestId, body);
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
      if (event.type === "permission.asked") {
        await post("permission.asked");
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
    },
  };
};
''';
