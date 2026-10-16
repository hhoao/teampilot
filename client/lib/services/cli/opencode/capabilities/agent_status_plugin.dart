/// 写入成员 opencode 配置目录的 agent-status 上报 plugin（JS）。
///
/// 与 [opencodeIdlePluginFileName] 并列：idle 仅 mixed 模式上报 `/idle`；
/// 本 plugin 在 simple/team 只要 `agentStatus != null` 就安装，POST `/agent-status`。
///
/// On `question.asked`, also polls `GET /ask-user-answer?request_id=` and calls
/// OpenCode v2 `ctx.question.reply` / `ctx.question.reject`; otherwise delivers
/// over the OpenCode HTTP API (`POST /question/{requestID}/reply|reject`).
///
/// Fallback must route through the context's own request pipeline
/// (`ctx._client.post`), **not** a raw `fetch` of a guessed server URL:
/// in the default TUI mode the server may not bind a TCP port.
const opencodeAgentStatusPluginFileName = 'teampilot-agent-status.js';

const opencodeAgentStatusPluginSource = r'''
import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "teampilot.agent-status",
  setup(ctx) {
    const options = ctx.options ?? {};
    const member = options.member ?? process.env.TEAMPILOT_MEMBER;
    const url =
      options.url ??
      process.env.TEAMPILOT_AGENT_STATUS_URL ??
      (process.env.TEAMPILOT_BUS_PORT
        ? `http://127.0.0.1:${process.env.TEAMPILOT_BUS_PORT}/agent-status`
        : null);
    const token = options.token ?? process.env.TEAMPILOT_BUS_TOKEN;
    const session = options.session ?? process.env.TEAMPILOT_SESSION;
    let port = options.port ?? process.env.TEAMPILOT_BUS_PORT ?? null;
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

    const resolvedRequests = new Set();
    const resolveRequest = (requestId) => {
      if (requestId) resolvedRequests.add(String(requestId));
    };
    const isResolved = (requestId) => resolvedRequests.has(String(requestId));

    const userMessageIds = new Set();
    const forwardedUserParts = new Set();
    // Background work tracking (see the shell / subagent branches below).
    const backgroundShellIds = new Set();
    const childSessionIds = new Set();

    const ASK_POLL_TTL_MS = 30 * 60 * 1000;
    const ASK_POLL_INTERVAL_MS = 400;

    const deliverQuestionReply = async (requestId, body, sessionID) => {
      if (ctx.question?.reply) {
        if (body.reject) {
          await ctx.question.reject({ requestID: requestId, sessionID });
        } else {
          await ctx.question.reply({
            requestID: requestId,
            sessionID,
            answers: body.answers,
          });
        }
        return;
      }
      const action = body.reject ? "reject" : "reply";
      const raw = ctx._client;
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
      throw new Error("no opencode question delivery path");
    };

    const deliverPermissionReply = async (requestId, body, sessionID) => {
      const reply =
        body.permission_reply ?? (body.reject ? "reject" : "once");
      if (ctx.permission?.reply) {
        await ctx.permission.reply({ requestID: requestId, sessionID, reply });
        return;
      }
      const raw = ctx._client;
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
      throw new Error("no opencode permission delivery path");
    };

    const pollAndReply = async (requestId, kind = "question", sessionID) => {
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
        } catch (_) {}
        if (status === 200 && body) {
          try {
            if (kind === "permission") {
              await deliverPermissionReply(requestId, body, sessionID);
            } else {
              await deliverQuestionReply(requestId, body, sessionID);
            }
          } catch (e) {
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
      if (isResolved(requestId)) return;
      await post("question.reply_failed", {
        request_id: requestId,
        message: "ask-user-answer poll timed out",
      });
    };

    const handleEvent = async (event) => {
      if (!event || !event.type) return;
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
        if (requestId) await pollAndReply(requestId, "permission", sessionID);
        return;
      }
      if (event.type === "question.asked") {
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
        await pollAndReply(requestId, "question", sessionID);
        return;
      }
      // Background shell tasks. OpenCode runs them under the CLI process and
      // they outlive the turn, so mirror them as leases
      // (backgroundTaskStarted / taskNotificationToolUseId in the Dart
      // normalizer). `shell.metadata.background` is only set for detached
      // shells; foreground steps are ignored.
      //
      // Both the `session.shell.*` and `session.next.shell.*` spellings are
      // accepted: the installed binary emits the former, while the generated
      // SDK types name the latter. The payload is likewise read from either
      // shape — a nested `properties.shell`, or the flattened event
      // properties (`callID` / `command` at the top level).
      if (
        event.type === "session.shell.started" ||
        event.type === "session.shell.ended" ||
        event.type === "session.next.shell.started" ||
        event.type === "session.next.shell.ended"
      ) {
        const props = event.properties ?? event.data ?? {};
        const shell = props.shell ?? {};
        const started = event.type.endsWith("shell.started");
        const shellId =
          shell.id != null
            ? String(shell.id)
            : props.callID != null
              ? String(props.callID)
              : props.shellID != null
                ? String(props.shellID)
                : null;
        if (!shellId) return;
        if (started) {
          const background =
            shell.metadata && shell.metadata.background
              ? true
              : props.background === true;
          if (!background) return;
          backgroundShellIds.add(shellId);
          await post("shell.started", {
            shell_id: shellId,
            command: shell.command ?? props.command ?? null,
          });
          return;
        }
        if (backgroundShellIds.delete(shellId)) {
          await post("shell.ended", { shell_id: shellId });
        }
        return;
      }

      // Subagent sessions. OpenCode runs each subagent in a child session
      // (`info.parentID`); track them as leases so a child going idle is never
      // mistaken for the parent session finishing.
      if (
        event.type === "session.created" ||
        event.type === "session.updated" ||
        event.type === "session.deleted"
      ) {
        const props = event.properties ?? event.data ?? {};
        const info = props.info ?? {};
        const sessionId = props.sessionID ?? event.sessionID ?? info.id ?? null;
        if (!sessionId) return;
        const id = String(sessionId);
        const parentId = info.parentID ?? info.parent_id ?? null;
        if (!parentId) return;
        if (event.type === "session.deleted") {
          if (childSessionIds.delete(id)) {
            await post("subagent.stopped", { subagent_id: id });
          }
          return;
        }
        if (!childSessionIds.has(id)) {
          childSessionIds.add(id);
          await post("subagent.started", { subagent_id: id });
        }
        return;
      }

      if (
        event.type === "session.next.step.ended" ||
        event.type === "session.idle"
      ) {
        const props = event.properties ?? event.data ?? {};
        const sessionId = props.sessionID ?? event.sessionID ?? null;
        const id = sessionId ? String(sessionId) : null;
        if (id && childSessionIds.delete(id)) {
          // A child session (subagent) going idle is not the parent turn
          // ending.
          await post("subagent.stopped", { subagent_id: id });
          return;
        }
        await post("session.idle");
      }
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
      }
    };

    const controller = new AbortController();
    void (async () => {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        await handleEvent(event);
      }
    })();

    return () => controller.abort();
  },
});
''';
