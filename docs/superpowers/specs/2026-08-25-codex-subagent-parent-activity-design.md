# Codex 子 Agent 父会话活动状态设计

## 目标

当 Codex 父会话并行委派多个子 agent 时，只要仍有任一子 agent 运行，父
terminal 必须保持 `working`，不得因父端 `Stop`、PTY 静默或其中一个子 agent
完成而变为空闲并触发 terminal reclaim。

## 范围

本变更只处理 TeamPilot 的 agent-status 状态归约与 terminal 回收保护，不改变
Codex 的任务调度、TeamBus 协议或 PTY 输出判定。

## 设计

每个父 seat（`sessionId + memberId`）维护一个由子 agent id 去重的活动集合，
以及一个 `parentStopPending` 标记。

- `SubagentStart`：将该 id 加入活动集合，并使 seat 为 `working`。
- `SubagentStop`：移除该 id；若集合仍非空，seat 保持 `working`；若集合清空且
  已收到父 `Stop`，seat 才变为 `done`。
- 父 `Stop` / `StopFailure`：集合为空时立即变为 `done`；否则仅记录
  `parentStopPending`，seat 保持 `working`。
- 普通无子 agent 的 turn 保持现有语义：`Stop` 立即完成。
- `UserPromptSubmit`、显式 seat/session 清除会清理子 agent 活动状态，避免旧状态
  泄漏到后续 turn。活动子 agent 存在时不适用 30 分钟 attention TTL；宁可保守地
  保持 terminal，也不能在一个无输出的长任务中回收它。

Codex agent-status hook 需要订阅 `SubagentStart` 与 `SubagentStop`，使上述事件能
到达状态处理器。处理器应继续按 seat 隔离事件，且重复的 start/stop 不得改变
正确状态。

## Terminal reclaim

terminal reclaim 继续使用现有的 `sessionBusyFromAttention` 保护条件。由于 seat
在活动子 agent 存在时始终为 `working`，reclaim watcher 不会开始该 terminal 的
空闲计时；最后一个子 agent 结束且父任务已完成后，才恢复原有回收行为。

## 验证

添加状态归约测试，覆盖：

1. 两个子 agent 运行时收到父 `Stop`，seat 仍为 `working`；
2. 第一个子 agent 完成时，seat 仍为 `working`；
3. 最后一个子 agent 完成后，延迟的父完成状态变为 `done`；
4. 无子 agent 的 `Stop` 仍立即为 `done`；
5. 重复 lifecycle 事件和 seat 清理不残留活动状态。
6. 活动子 agent 在通常 attention TTL 之后仍保持父 seat 为 `working`。
