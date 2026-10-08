/// 写入成员 opencode 配置目录的 idle 上报 plugin（JS）。
const opencodeIdlePluginFileName = 'teampilot-idle-bus.js';

/// OpenCode has no Claude-style Stop hook. On `session.idle` we POST `/idle`;
/// when the bus returns `decision:block`, re-enter via `ctx.session.prompt`
/// with the same redirect reason Claude/flashskyai Stop hooks use.
///
/// Only [session.idle] re-prompts — [session.next.step.ended] also POSTs /idle
/// for presence, but must not inject a second user turn mid-agent-loop.
const opencodeIdlePluginSource = r'''
import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "teampilot.idle-bus",
  setup(ctx) {
    const options = ctx.options ?? {};
    const member = options.member ?? process.env.TEAMPILOT_MEMBER;
    const port = options.port ?? process.env.TEAMPILOT_BUS_PORT;
    const token = options.token ?? process.env.TEAMPILOT_BUS_TOKEN;
    const session = options.session ?? process.env.TEAMPILOT_SESSION;
    const headers = { "X-Member": String(member) };
    if (session) headers["X-Session"] = String(session);
    if (token) headers["X-Bus-Token"] = String(token);
    const redirect =
      "<teambus type=\"stop_reason\">Do not stop. Call wait_for_message — it blocks until you " +
      "have something to do and returns either teammate/operator messages or a " +
      "task claimed for you from the work queue. You coordinate through the " +
      "bus, not by ending your turn.</teambus>";

    const sessionIdOf = (event) =>
      event?.properties?.sessionID ??
      event?.data?.sessionID ??
      event?.sessionID;

    const postIdle = async () => {
      if (!member || !port) return "";
      try {
        const r = await fetch(`http://127.0.0.1:${port}/idle`, {
          method: "POST",
          headers,
        });
        return await r.text();
      } catch (_) {
        return "";
      }
    };

    const reenterIfBlocked = async (event, resp) => {
      if (!resp.includes('"decision":"block"')) return;
      const sessionID = sessionIdOf(event);
      if (!sessionID || !ctx.session?.prompt) return;
      let reason = redirect;
      try {
        const parsed = JSON.parse(resp);
        if (typeof parsed?.reason === "string" && parsed.reason.trim()) {
          reason = parsed.reason.trim();
        }
      } catch (_) {}
      try {
        await ctx.session.prompt({ sessionID, text: reason });
      } catch (_) {}
    };

    const controller = new AbortController();
    void (async () => {
      for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
        if (!event || !event.type) continue;
        if (event.type === "session.next.step.ended") {
          await postIdle();
          continue;
        }
        if (event.type === "session.idle") {
          const resp = await postIdle();
          await reenterIfBlocked(event, resp);
        }
      }
    })();

    return () => controller.abort();
  },
});
''';
