/// rev 4：只建已有真实消费者的类型；agents/rules/commands 有需求再补。
enum AssetKind { skills, mcp, plugins, hooks }

enum AssetScope { app, team, workspace, session }

enum AssetSource { capability, userConfig, pluginBundle, hubInstall }

/// 资产注册时带 scope；落盘时按 seat 上下文合并四层。
class CliConfigAsset<T> {
  const CliConfigAsset({
    required this.kind,
    required this.payload,
    required this.scope,
    required this.source,
    required this.level,
    required this.id,
  });

  final AssetKind kind;
  final T payload;
  final AssetScope scope;
  final AssetSource source;
  final int level;
  final String id;
}

/// 落盘时一个 seat 的完整上下文（assetsFor 的入参——不是单一 scope）。
/// app 层资产始终参与合并（最低优先级基底），无需字段标记。
class AssetSeatContext {
  const AssetSeatContext({
    required this.sessionId,
    required this.teamId,
    required this.workspaceId,
    required this.memberId,
  });

  final String sessionId;
  final String teamId;
  final String workspaceId;
  final String memberId;
}
