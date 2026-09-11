# Configurable Minimum Members for Generated Teams

## Goal

让“生成并启动”创建的团队默认至少包含 3 个不同成员/角色，并允许用户在设置中配置更大的最少成员数，同时移除当前生成协议中固定的 5 人上限。

本设置按生成计划中的成员条目数统计，不按 `replicas` 展开的最终席位数统计。例如，`team-lead`、`developer`、`reviewer` 是 3 个成员条目；某个成员的 `replicas` 不会改变最少成员数判断。

## Scope and non-goals

范围仅限“生成并启动”流程：设置、生成任务快照、Builder 上下文、计划校验和相关文案/测试。

不修改已经生成的团队，不改变普通团队配置页的成员增删规则，也不引入独立的最大成员数配置。生成计划仍受已有 payload 大小、模型池、目标探测和终端启动能力等系统约束保护，但不再有固定的 `memberCountMax: 5` 约束。

## User-facing behavior

- “生成并启动设置”新增“最少团队成员数”数字输入项。
- 默认值为 `3`。
- 输入必须是大于等于 `3` 的整数；空值、非数字和小于 `3` 的值不能保存，并显示本地化校验提示。
- 用户可以输入大于 5 的值，例如 8 或 10。
- 旧设置文件没有该字段时按 `3` 读取。
- 生成开始时读取并冻结该值；生成过程中用户修改设置不会影响当前任务。

## Architecture and data flow

### Settings model

在 `TeamGenerationSettings` 中增加 `minimumMemberCount`：

- factory 默认值为 `3`；
- `fromJson` 缺省值为 `3`；
- `normalized()` 将无效值规范化为至少 `3`；
- `toJson()` 持久化该字段；
- equality/hashCode 纳入该字段。

`TeamGenerationSettingsSnapshot` 同样携带 `minimumMemberCount`，并将其纳入 snapshot JSON、相等判断和 revision 计算。这样 job 持久化的设置快照是生成流程的唯一约束来源。

### Generation context

`teamGenerationContextPayload` 在 `constraints` 中返回：

```json
{
  "memberCountMin": 3
}
```

移除 `memberCountMax`。`GeneratedTeamPlan.wireSchema` 的成员数说明改为“至少使用上下文提供的 `memberCountMin`”，不再写死 `2..5`。

Builder skill 的两份来源文件（Dart 内置字符串和磁盘 Markdown）同步更新：Builder 必须读取冻结上下文，并生成不少于 `memberCountMin` 个不同成员条目；不得假设或传播固定最大值。

### Validation

`GeneratedTeamPlanValidator` 保留计划非空和 leader 唯一性检查，将现有 `2..5` 判断改为：

```text
plan.members.length >= input.settings.minimumMemberCount
```

低于设置值时返回新的明确 issue code：`member_count_below_minimum`，并携带实际值与要求值的 detail。移除固定最大值导致的 `member_count_out_of_range` 上限分支；其它重复 ID、角色冲突、replicas、placement、资源和工作区漂移校验保持不变。

## Error handling and localization

- 设置输入错误只在设置对话框内展示本地化提示，不写入无效配置。
- 生成计划不满足最少成员数时，通过已有 Builder MCP 校验响应返回 `member_count_below_minimum`，让 Builder 修正计划。
- 若 Builder 多次无法满足要求，沿用现有生成失败链路；新增 issue code 的用户可见映射使用现有生成失败/计划无效文案体系，诊断 detail 保留在日志和工具响应中。
- 不新增未本地化的用户可见错误字符串；只编辑 `app_en.arb` 和 `app_zh.arb`。

## Compatibility

- 旧 `teamGenerationSettings.json` 可继续读取；缺少 `minimumMemberCount` 时使用 3。
- 已存在的 generation job 若其 settings snapshot 缺少该字段，反序列化时同样使用 3。
- 已生成的 `TeamProfile`、普通团队配置和既有会话不受影响。
- 计划 JSON wire schema 仍维持现有字段结构，不增加成员字段；只放宽成员条目数量的固定上限并增加冻结的最小值约束。

## Testing

覆盖范围包括：

1. settings 默认值、旧 JSON 缺省值、非法值规范化、JSON round-trip、相等性和 snapshot revision。
2. generation context 包含正确的 `memberCountMin` 且不包含固定 `memberCountMax`。
3. validator 对低于最少值的计划返回 `member_count_below_minimum`。
4. validator 对恰好达到和超过最少值的计划接受成员数，不因超过 5 而失败。
5. Builder skill Dart 字符串与磁盘 Markdown 仍 byte-identical，并包含新的无固定上限规则。
6. 设置对话框可以加载、编辑、拒绝非法值并保存最少成员数。

验证遵循仓库规则：先运行 `flutter analyze`，单文件测试通过 `cd client && dart run tool/run_tests.dart ...` 执行，完成前运行完整 analyze 和测试套件。
