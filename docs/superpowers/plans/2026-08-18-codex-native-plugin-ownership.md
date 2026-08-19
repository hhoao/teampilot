# Codex 原生插件归属改造计划

## 目标

让 Codex 在每个会话自己的 `CODEX_HOME` 中通过 `codex plugin marketplace/add` 管理插件；TeamPilot 只负责准备插件源和调用原生安装流程。其他 CLI 继续使用现有的 TeamPilot 物化流程，并保留 workspace/session 的隔离层级。

## 设计

1. 在 `PluginCapability` 增加插件运行时归属声明。Codex 声明为原生管理，其余 CLI 默认仍为 TeamPilot 管理。
2. 增加可注入的原生插件安装器：
   - 从 TeamPilot 已安装插件目录生成会话外部 marketplace 源；
   - 使用当前工作机的 `HostOneShotRunner` 执行 `codex plugin marketplace add`、`codex plugin list` 和 `codex plugin add`；
   - 使用 `CODEX_HOME=<session runtime>`，因此 native/WSL/SSH 都沿用现有运行时上下文；
   - 仅在插件缺失或版本不匹配时安装，避免 resume 时反复覆盖 Codex 管理目录；同时迁移旧的 TeamPilot `local` 安装。
3. `ConfigProfileService` 在 Codex 分支调用原生安装器，不再调用 Codex 当前的 `copyTree` 到 `$CODEX_HOME/plugins` 的逻辑；非 Codex 分支保持原调用链。启动 manifest 的暂存阶段只写 marketplace 源，`SessionConnectOrchestrator` 的真实 flush 完成后才执行原生命令；不能只依赖 `prepare*` 包装方法，因为正常连接路径直接调用 `stage*`。
4. `SessionLifecycleService` 将工作机 runner 和 CLI executable 传入配置服务；未注入自定义 resolver 时使用 CLI 默认 executable。已有的 per-session `CODEX_HOME` 路径和继承架构不改。
5. 用单元测试覆盖：Codex 原生命令和环境、幂等跳过、其他 CLI 不受影响、Codex 不再直接物化 managed plugins。再运行相关 Flutter 测试和静态分析。

## 验证标准

- 新启动和 resume 都能在目标 session 的 `CODEX_HOME` 里看到并加载插件技能；
- TeamPilot 日志不再出现 Codex `CODEX_HOME/plugins` 的直接复制；
- 不同 session 的 Codex 原生安装状态互不污染；
- WSL/SSH 路径通过既有 `HostOneShotRunner`，不新增一套远程执行逻辑。
