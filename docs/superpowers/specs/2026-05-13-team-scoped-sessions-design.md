# Team 作用域会话设计

## 目标

新增一个可选的会话模式，让当前选中的 team 拥有可见的项目与会话工作区。
开启后，切换 team 时只显示该 team 关联的项目和会话；关闭后，应用保持当前
全局项目/会话列表的行为。

## 用户行为

- 新增会话设置 `scopeSessionsToSelectedTeam` 控制该模式。
- 该设置默认值为 `false`，保证旧版本数据和现有使用方式兼容。
- 开启后，新建 session 会写入当前选中的 `TeamConfig.id`。
- 左侧边栏只列出 `AppSession.sessionTeam` 与当前 team id 匹配的 session。
- 项目只有在当前 team 下存在可见 session 时才显示。
- 切换 team 时，可见项目/会话列表会立即按新的 team 重新过滤，但不会修改
  已保存的全局 session 数据。
- 旧的未归属 session 在全局模式下仍然可见；在 team 作用域模式下会被隐藏，
  直到后续增加迁移或显式重新归属功能。

## 数据模型

复用 `AppSession.sessionTeam` 表示 UI 层的稳定 team 归属。现有启动逻辑在
进程启动后会把临时 CLI team 目录名写入同一个字段。为了避免覆盖 UI 归属，
实现时新增一个单独的持久化字段保存启动用的 team 名：

- `AppSession.sessionTeam`：稳定的 UI 归属 team id。
- `AppSession.launchTeam`：用于启动或恢复 Shell 进程的临时 CLI team 目录名。

没有 `launchTeam` 的旧 session JSON 继续正常加载。已有 session 如果把旧的临
时启动名存到了 `sessionTeam`，除非它刚好匹配真实 team id，否则在新作用域
规则里会被视为未归属。

## 状态流

`SessionPreferences` 保存新的布尔设置，设置页以 switch 的形式展示。
`main.dart` 将偏好设置值和当前选中的 team 传入 `ChatCubit`。

`ChatCubit` 仍然从 `SessionRepository` 加载全部 projects 和 sessions，同时
追踪：

- 当前选中的 team id
- team 作用域模式是否开启

它对外提供派生后的可见列表；开启 team 作用域时按当前 team 过滤。侧边栏
读取这些派生列表，而不是直接读取全局原始状态。

## Session 创建

所有发生在选中 team 上下文里的 session 创建路径，都把当前 team id 传给
`SessionRepository.createSession`。包括：

- 在侧边栏项目下新建 session
- 为当前 workspace 创建默认的持久化 chat tab
- 新建项目时创建第一个 session

即使 team 作用域模式关闭，也可以继续给新 session 写入当前 team id。这样
用户之后开启该模式时，已有的新会话能立即出现在预期的 team 下。

## 错误处理

如果 team 作用域模式开启但当前没有选中 team，可见项目和 session 列表为空。
损坏的 session 文件继续由 repository 按现有逻辑跳过。

## 测试

增加聚焦测试覆盖：

- `SessionPreferences` 对新设置的 JSON、默认值和 `copyWith` 行为。
- `SessionPreferencesCubit` 对新设置的持久化行为。
- `SessionRepository.createSession` 会保存稳定的 session team id。
- `ChatCubit` 的可见 project/session 列表会按当前 team 过滤，并在选中 team
  或设置变化时更新。
- 侧边栏创建 session 时会通过 `ChatCubit` 传入当前 team id。
