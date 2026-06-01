/// 写入成员 opencode 配置目录的 idle 上报 plugin（JS）。
const opencodeIdlePluginFileName = 'teampilot-idle-bus.js';

const opencodeIdlePluginSource = r'''
export const TeampilotIdleBus = async (input, options) => {
  const member = options?.member ?? process.env.TEAMPILOT_MEMBER;
  const port = options?.port ?? process.env.TEAMPILOT_BUS_PORT;
  return {
    event: async ({ event }) => {
      if (event && event.type === "session.next.step.ended" && member && port) {
        await fetch(`http://127.0.0.1:${port}/idle`, {
          method: "POST",
          headers: { "X-Member": String(member) },
        }).catch(() => {});
      }
    },
  };
};
''';
