# 自动生成团队 Session 生命周期与命名设计

日期：2026-09-11

## 背景

自动生成团队会创建一个供 Team Builder 使用的临时 Builder Session。当前流程中，Builder Session 使用固定的“Team Builder”标题，并在团队创建完成、目标团队 Session 交接后由 cleanup 流程删除。

这会带来两个问题：

1. Builder Session 的标题与普通 Session 的首条用户输入命名规则不一致。
2. 需要排查生成过程时，Builder Session 会在交接后被立即清理，用户无法查看完整过程。

## 目标与非目标

### 目标

- Builder Session 默认继续在团队创建完成后立即删除，保持现有正常用户体验。
- 在“生成并启动设置”中提供一个持久化的排错选项，用于保留 Builder Session。
- 保留选项开启时，目标团队 Session 仍然打开并切换为当前 Session。
- Builder Session 使用用户原始需求的首行作为标题，复用普通 Session 的标题截断规则。
- 配置变更不会影响已经启动的生成任务。
- 保留 Builder Session 时仍撤销生成流程的授权并完成任务归档，避免留下可继续调用 Team Composer 的工作流。

### 非目标

- 不改变目标团队 Session 的创建、提示词交接或成员启动逻辑。
- 不增加定时删除或新的自动归档策略。
- 不将 Builder Session 转换为普通 Session；它仍保留 `teamGeneration` 身份用于安全边界和历史识别。
- 不改变用户手动删除 Session 的能力。

## 方案选择

考虑过三种方案：

1. 在生成设置中增加“保留团队构建 Session”开关，默认关闭，并把值快照到生成任务。
2. 将保留行为绑定到全局开发/日志模式。
3. 每次生成完成后弹窗询问是否保留。

采用方案 1。它同时满足默认体验、排错可发现性和任务生命周期一致性；方案 2 对普通用户不可见，方案 3 会打断正常完成流程。

## 设计

### 配置模型与快照

在 `TeamGenerationSettings` 增加布尔配置 `retainBuilderSession`，默认值为 `false`。

- 配置写入现有团队生成设置 JSON。
- 旧配置文件缺少该字段时按 `false` 解码，保持向后兼容。
- 设置对话框增加开关及说明，明确它是排错用途。
- `TeamGenerationSettingsSnapshot` 同步携带该值。
- `TeamGenerationJob` 创建时保存快照值，后续 cleanup 只读取任务快照，不读取当前全局设置。

这样可以保证：任务启动后，即使用户修改设置，该任务仍遵循启动时确定的生命周期策略。

### Builder Session 命名

普通 Session 的标题来源是首条用户输入的首行，并经过现有长度限制和省略号处理。团队生成 Builder Session 的内部 kickoff 文本包含系统工作指令，因此不能直接用 kickoff 文本作为标题。

在 Builder Session 已创建并可更新元数据后，以生成任务的 `originalPrompt` 调用与普通 Session 相同的首条输入标题逻辑：

- 取原始需求第一行；
- 压缩连续空白并去除首尾空白；
- 使用普通 Session 的最大长度限制；
- 只在 Session 尚未有自定义标题时写入。

如果标题写入失败，不阻塞 kickoff；错误通过现有诊断日志记录。这样标题失败不会破坏生成任务，且列表标题仍可回退到本地化的 Builder 标题。

### 完成与 cleanup 数据流

团队生成成功时保持现有顺序：

1. 提交生成的团队配置。
2. 创建或打开目标团队 Session。
3. 选择目标团队 Session，并交付原始用户需求。
4. 根据任务快照决定 Builder Session 的处理方式。

当 `retainBuilderSession == false`：

- 继续执行现有的交付完成、Builder 空闲等待、Builder 删除、授权撤销和任务 tombstone 归档流程。

当 `retainBuilderSession == true`：

- 不等待 Builder 空闲，也不删除 Builder Session。
- 记录一个明确的“Builder 已保留”完成 receipt，使 cleanup/recovery 可幂等判断。
- 撤销 Team Generation 授权，使保留的 Session 只作为历史排错记录，不能继续调用受保护的 Team Composer 流程。
- 将任务归档为 complete；目标 Session 与 Builder Session 都保持可见。

目标 Session 的选择时机不变，因此保留模式不会让用户停留在 Builder Session；完成后当前 Session 始终是新创建的团队 Session。

### 取消与恢复

- 生成尚未完成时的 cancel 行为不变，仍删除 Builder Session。
- 失败任务的 retry 继续使用该任务已经保存的生命周期策略。
- 应用重启后的 recovery 使用 Job 中的配置快照，不重新解析当前设置。
- 已完成且保留 Builder 的任务不应被恢复流程再次删除。

## 错误处理

- 设置文件读取失败或字段类型不正确时，使用默认值 `false`，沿用现有设置 store 的容错策略。
- Builder 标题写入失败只记录诊断日志，不影响生成流程。
- 保留模式下授权撤销失败应遵循现有 cleanup 的错误处理和重试语义，不能为了保留 Session 而跳过安全清理。
- 删除模式的原有三道 cleanup gate 和 Builder 身份校验保持不变。

## 实现边界

预计修改以下区域：

- `client/lib/models/team_generation_settings.dart`：配置字段、JSON、快照。
- `client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart`：排错开关和保存逻辑。
- `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`：开关标题及说明。
- `client/lib/services/team_generation/team_generation_coordinator.dart`：创建任务时携带配置快照。
- `client/lib/services/team_generation/team_generation_cleanup_service.dart`：按快照分支处理 Builder。
- `client/lib/services/team_generation/team_generation_session_port.dart` 及 Cubit 适配器：复用普通 Session 标题写入能力。
- 相关生成模型、恢复/cleanup 测试。

不修改工作区路径、CLI 注册表、目标团队 Session 创建逻辑及无关的 Session 删除流程。

## 测试策略

### 单元测试

- 默认设置和旧 JSON 缺字段均解析为 `retainBuilderSession == false`。
- 开关值能正确序列化、反序列化，并进入任务快照。
- 普通需求文本生成的 Builder 标题与普通 Session 标题规则一致；多行、长文本和空白输入覆盖边界。
- 默认 cleanup 仍删除 Builder Session、撤销授权并完成归档。
- 保留模式 cleanup 不删除 Builder、不等待 idle，但会撤销授权、写入保留 receipt 并完成归档。
- cleanup 重试和 recovery 对两种模式都保持幂等。
- 目标 Session 在两种模式下都被选中。

### 验证

遵循仓库测试约定：先运行 `flutter analyze`，针对修改的测试文件使用 `dart run tool/run_tests.dart`，完成前运行完整 analyze 和完整测试套件；禁止直接调用 `flutter test`。

## 验收标准

- 新安装或未配置用户的行为与当前一致：生成完成后 Builder Session 被删除。
- 用户打开排错开关后，生成完成时看到新团队 Session，Builder Session 仍在 Session 列表中。
- 两个 Session 的当前选择结果正确：新团队 Session 为当前 Session。
- Builder Session 标题显示用户原始需求首行，而不是“Team Builder”或内部 kickoff 指令。
- 关闭排错开关后，新任务恢复立即删除行为。
- 生成任务重启恢复、失败重试和手动取消没有引入未授权 Team Composer 调用或误删目标 Session。
