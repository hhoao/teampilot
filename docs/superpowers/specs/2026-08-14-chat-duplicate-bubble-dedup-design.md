# 单条消息双气泡：兜底去重与取证日志设计

**日期:** 2026-08-14
**状态:** 已确认（2026-08-14 与用户逐项确认）

## 背景与现象

opencode 会话页面上**间歇性**出现"单条 assistant 消息显示成两个气泡"：

- 终端（opencode TUI）看是单条记录；
- 页面出现两个气泡，内容相同、状态不同（如 `question` 工具 pending 版 + completed 版，或同一 prose 的 3 步 CoT 版 + 10 步 CoT 版）；
- **重新打开页面（全量历史加载）后消失**——重复存在于 live 增量刷新路径，全量解析自愈；
- 普通消息也会出现（非父子会话混合，用户已排除该假设）。

用户提供两份页面导出 HTML（`Attachments/26bbaa7e...html`、`6b92e246...html`），其来源会话为
`68bc8f14-6d7e-430e-9f0e-ab1f9e485dd1`（seat session `ses_002017e4affeeNZPn21rejm1AB`）。

## 根因调查摘要（已完成，全部排除）

| 层 | 验证方式 | 结果 |
|---|---|---|
| 真实 DB 行结构 | 68bc8f14 question 消息 `msg_ffe09087b` 单行单 part，`prt_ffe09414c` created 10:10:47 → updated 10:12:12（原地更新） | ✅ 单行 |
| 全量解析 + seed | 真实 adapter 解析 → 18 条，prose 出现 1 次 | ✅ 干净 |
| 增量 refresher | 重放 pending→completed（独立消息 / 被合并进大消息 / 同批次新行组合） | ✅ 无重复 |
| 行级一致性 | 全部行 `data.id == null`（id 恒等于行 id），无重写 | ✅ 干净 |
| runtime `setMessages` | 整体替换语义 | ✅ 干净 |
| viewport 渲染 | widget 测试（同 id 原地更新 + turn 增长） | ✅ 干净 |
| seat 合并 | `mergeTimeline` 已按 id 去重 | ✅ 干净 |

**结论**：当前代码 + 当前 DB 终态无法构造该重复；HTML 导出于 10:17，而 DB 该消息只有一行
（completed），页面却同时显示 pending/completed 两个版本且持续 5+ 分钟。最可能机制：
opencode 在特定写库时序（如 `question` 工具暂停/恢复、流式 step 边界）短时写入同内容多行
（或同 id 被重复解析），随后自清理；应用侧 live 增量状态在清理前的窗口内同时持有两个版本。
由于页面两个气泡的内容状态不同、且 seat 已按 id 去重，**重复大概率以"同文本、不同 id"形态
存在**。在无法现场抓取的条件下，采用「兜底去重 + 取证日志」双保险，下次复现时从日志定位真凶。

## 方案

### 1. 兜底：seat 发布前消息去重

**位置**：`client/lib/cubits/ai_history_seat.dart`，`_applyMessages` 与 `_applySoftReloadMessages`
两处拿到合并后列表、写入 `_allMessages` 之前，统一过 `_dedupeLiveMessages()`。

**规则**（依次）：

1. **同 id**：保留最后一次出现（内容最新）。适用于所有角色——防御任何来源的同 id 瞬态重复。
2. **assistant 且文本 part 完全相同的任意对**（按 `AiTextPart.text` 拼接比较，不含 reasoning/tool；
   全列表扫描，不限于相邻——HTML 场景中两条同文本消息之间可能隔着 user 行）：
   - **工具状态不对称**：按 `toolCallId` 对齐逐工具比较，一条的 `result != null` 数量严格多于另一条
     → 保留结果更全的一条；
   - **part 超集**：一条的非文本 part 集合包含另一条（相同文本下）→ 保留超集；
   - **完全相同**（同文本、同 parts、同工具状态）→ 保留第一条（真重复，无保留价值）。
3. **user 消息**：不做文本去重——"没问题"×2 这类跨时间的合法重复必须保留。

**判定用文本拼接（question 2 确认）**，不用 `messageContentIdentity`（含工具状态，对
pending/completed 双份太敏感）。

**影响范围**：seat 层全局，所有 CLI 生效（question 1 确认）；日志携带 `cli` 字段，必要时收敛。

### 2. 取证日志

**位置**：与去重同处（seat），`_dedupeLiveMessages` 检测到重复时打日志（question 3 确认 `w` 级）。

**内容**（`appLogger.w`，`[ai-history] duplicate-messages` 前缀）：
- `sessionId` / `memberId` / `cli` / 路径（`applyMessages` | `applySoftReloadMessages`）
- 重复对：两条消息的 `id`、`role`、文本前 80 字符、工具状态摘要
- 去重动作：`deduped`（保留哪个 id）或 `kept-both`（规则不命中，仅记录）

**防刷屏**：同一 seat 连续两轮重复且 id 组合相同 → 只打一次（记录上次日志指纹，跳过相同指纹）。

### 3. 数据流与改动点

```
loader（full parse / incremental）→ seat._cliMessages
  → buildConversationTimeline（mailbox 合并，已按 id 去重）
  → _dedupeLiveMessages()（新增：内容级兜底 + 取证日志）
  → _allMessages → _visibleSlice → runtime.setMessages → 页面
```

改动文件：
- `client/lib/cubits/ai_history_seat.dart`（新增 `_dedupeLiveMessages` + 两处调用 + 日志指纹字段）

不改 loader / refresher / viewport（已证明干净，避免动到已验证路径）。

### 4. 测试计划

新增 `client/test/cubits/ai_history_seat_test.dart`（或既有 seat 测试文件）：

1. **同 id 去重**：列表含同 id 两条（前 pending 后 completed）→ 发布结果仅一条，保留后者。
2. **同文本不同 id、工具状态不对称**：question pending + question completed → 保留 completed。
3. **part 超集**：同文本 3 步版 + 10 步版 → 保留 10 步版。
4. **完全相同**：两条一字不差 → 保留第一条。
5. **合法 user 重复不误删**：两条"没问题"user 消息 → 都保留。
6. **日志触发**：场景 2 下断言 `appLogger` 记录出现（mock logger 或捕获）。
7. **防刷屏**：相同重复对连续两轮 → 只打一次日志。

## 验收标准

- 上述 7 项测试全绿；`flutter analyze` 无新增问题。
- 用户下次复现时提供日志（`[ai-history] duplicate-messages`），日志内容足以定位真凶
  （消息 id / 文本 / 工具状态 / 来源路径）。
