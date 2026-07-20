/// 写入成员 opencode 配置目录的 agent-status 上报 plugin（JS）。
///
/// 与 [opencodeIdlePluginFileName] 并列：idle 仅 mixed 模式上报 `/idle`；
/// 本 plugin 在 simple/team 只要 `agentStatus != null` 就安装，POST `/agent-status`。
const opencodeAgentStatusPluginFileName = 'teampilot-agent-status.js';

const opencodeAgentStatusPluginSource = r'''
export const TeampilotAgentStatus = async (input, options) => {
  const member = options?.member ?? process.env.TEAMPILOT_MEMBER;
  const url =
    options?.url ??
    process.env.TEAMPILOT_AGENT_STATUS_URL ??
    (process.env.TEAMPILOT_BUS_PORT
      ? `http://127.0.0.1:${process.env.TEAMPILOT_BUS_PORT}/agent-status`
      : null);
  const token = options?.token ?? process.env.TEAMPILOT_BUS_TOKEN;
  const session = options?.session ?? process.env.TEAMPILOT_SESSION;
  const headers = {
    "Content-Type": "application/json",
    "X-Member": String(member),
  };
  if (session) headers["X-Session"] = String(session);
  if (token) headers["X-Bus-Token"] = String(token);

  const post = async (eventName) => {
    if (!member || !url) return;
    await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify({ event: eventName }),
    }).catch(() => {});
  };

  return {
    event: async ({ event }) => {
      if (!event || !event.type) return;
      if (event.type === "permission.asked") {
        await post("permission.asked");
        return;
      }
      if (event.type === "question.asked") {
        await post("question.asked");
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
