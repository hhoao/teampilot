# CLI 传输胶囊与 ACP 范围放开 设计

日期：2026-11-02
状态：待实现

## 背景

ACP 与 PTY 的能力正在对齐，同时 ACP 的适用范围也从「仅个人 / 混合会话、仅桌面」放开
到「个人、原生团队、混合团队、远程成员」。当前设置页仍是旧假设：

- `client/lib/pages/config/cli_readiness_card.dart:666-682` 是
  `TpPreferenceRow`：标题「新建个人和混合会话使用 ACP」、副标题
  「原生团队和远程成员仍用终端」、右侧 `Switch`。
- 范围放开后副标题描述的例外不再成立，必须删除；删完这一行只剩一句标题 + 一个开关，
  占 60px 高度只为托一个 Switch。
- 后端门禁有三处，都要一起拆：
  - `client/lib/services/chat/launch/session/launch_acp_policy.dart:10-21`
    （`_personalAcpAllowed` 要求 `isPersonal`）
  - `client/lib/services/chat/launch/session/session_provisional_builder.dart:45-49`
    （`resolvedAcp` 要求 `trimmedTeam.isEmpty && isPersonal`）
  - `client/lib/services/chat/launch/session/member_acp_stamp.dart:14-25`
    （`_memberAcpGates` 要求 `teamMode == mixed` 且目标必须是
    `RuntimeKind.local`，原生团队与远程成员一律 false）
- 远程 ACP 的传输层已具备：`client/lib/services/acp/acp_ssh_transport.dart`、
  `client/lib/services/chat/launch/connect/acp_runtime_attach.dart:299`
  （`DartSsh2AcpChannel`）。
- 会话内已有同构控件：`client/lib/pages/chat/session_workbench_view_toggle.dart:45`
  的「对话 / 终端」两段图标胶囊。

结论：这个设置项从「试验性偏好」升级为「该 CLI 的默认传输方式」，属于卡片身份层级，
应该上移到 header；同时必须与后端门禁一起改，否则 UI 表达的是全局默认、代码只做个人会话。

## 目标

1. 删除设置页的 ACP 偏好行，改为 CLI 卡片 header 最右侧的图标胶囊。
2. 放开 ACP 适用范围：个人、原生团队、混合团队、远程成员统一跟随该 CLI 的偏好。
3. 清理随之失效的文案与命名。

## 非目标

- 不迁移已有会话：它们保持启动时的运行时。
- 不改 compose 页的 ACP 权限控制与 `CliLaunchSecurityCapability`。
- 不改存储 JSON 结构（只重命名 Dart API）。
- 不做 ACP / PTY 的能力对齐本身（权限卡、历史、工具调用等另属 parity 工作）。

## 决策

### 1. 控件形态：图标胶囊，放在徽章右侧

header 顺序：

```
[品牌图标 28] [标题 Expanded] [状态徽章] [胶囊 72×28]
```

- 复用 `TpSegmentedControl`（filled 变体），两段各 `36×28`、`minHeight: 28`，
  图标 `chat_bubble_outline_rounded` / `terminal_rounded`，与
  `session_workbench_view_toggle.dart:49-62` 完全一致——会话里切当前运行时、
  设置里选默认运行时，使用同一套视觉语言。
- 选中段 = 该 CLI 的默认传输（chat 段 = ACP）。
- 胶囊固定宽度、不参与压缩；标题是唯一可压缩项（`Expanded` + 省略号）。
- 胶囊右缘与下方「重置 / 定位」共用同一条右边界，header 多出一条统一操作列。
  徽章退回纯信息位（只报告状态），胶囊独占交互位，避免两个彩色块并排。

尺寸依据：`TpSegmentedControl` 的文字段最小宽度是
`tpSegmentedControlMinSegmentWidth = 72`（每段左右各 20px padding），文字胶囊两段约
144px；360dp 手机上 header 预算约 32 padding + 28 图标 + 10 + 标题 + 144 + 徽章，
会溢出。图标段 `36` 可把整枚胶囊压到 72px。

### 2. 渲染条件

| 条件 | 行为 |
|---|---|
| `canChooseTransport == false` | 整枚胶囊不渲染（Gemini / CodeBuddy 等 ACP-only CLI） |
| CLI 或适配器未就绪 | 仍渲染且可点，未就绪交给状态徽章表达 |
| Android | 不渲染——`resolveLaunchAcp` 仍拒绝 Android ACP，避免出现点了不生效的控件 |
| 远程工作区 | 渲染；远端适配器是否就绪由状态徽章与 ACP 路径行表达 |

不放灰色 / 不可点的控件：header 上摆一个永远点不动的控件是最差选项。

### 3. 后端门禁放开

- `launch_acp_policy.dart`：删除 `isPersonal` 判定，仅保留 `canChooseTransport`
  能力检查与 Android 平台判定；`resolveLaunchAcp` 去掉 `isPersonal` 参数，
  保留 `isAndroidOverride`（测试注入）。
- `session_provisional_builder.dart:45-49`：改为
  `resolvedAcp = (acp ?? false) || launchesAcpOnly(identity?.cli ?? cli)`，
  不再要求 `trimmedTeam.isEmpty && isPersonal`。
- `member_acp_stamp.dart`：`_memberAcpGates` 去掉 `teamMode` 与 `targetId` 判定，
  只保留 Android、`cli != null`、`AcpCapability` 三项；`resolveMemberBindingAcp`
  与 `shouldAttachMemberAcp` 相应去掉 `teamMode` / `targetId` 参数。
  ACP-only CLI 仍短路为 true。
- Android 平台门禁本次保留：远程 SSH exec 的适配器探活只有手工清单
  （`docs/remote-acp-adapter-smoke.md`），没有自动化覆盖，拆 gate 单独排期。

### 4. 文案

删除：

- `personalAcpSwitchLabel`、`personalAcpSwitchCaption`
- `claudePersonalAcpAndroidDisabled`、`codexPersonalAcpAndroidDisabled`

新增（zh / en 同步，只改 `app_zh.arb` / `app_en.arb`）：

| key | zh | en |
|---|---|---|
| `cliTransportDefaultChat` | 新会话默认使用对话（ACP） | New sessions default to chat (ACP) |
| `cliTransportDefaultTerminal` | 新会话默认使用终端（PTY） | New sessions default to the terminal (PTY) |

两条都用作胶囊分段的 tooltip，不新增可见正文——窄屏加一行说明会把省下的高度还回去。

### 5. 命名

范围放开后 `personalAcpDefaultFor` 里的 "Personal" 是错的：

- `SessionPreferences.personalAcpDefaultFor` → `acpDefaultFor`
- `SessionPreferences.withPersonalAcpDefault` → `withAcpDefault`
- `SessionPreferencesCubit.personalAcpDefaultFor` → `acpDefaultFor`
- `SessionPreferencesCubit.setPersonalAcpDefaultFor` → `setAcpDefaultFor`

存储字段 `personalAcpDefaults` 与 JSON key 保持不变，避免迁移。

## 架构与接线

| 文件 | 改动 |
|---|---|
| `client/lib/pages/config/cli_readiness_card.dart` | header `Row` 末尾插入胶囊；删除 `_buildAcpBlock` 里的 `TpPreferenceRow` 与 `showSwitch`；保留 ACP 路径行 |
| `client/lib/services/chat/launch/session/launch_acp_policy.dart` | 去掉 `isPersonal` 门禁与参数 |
| `client/lib/services/chat/launch/session/session_provisional_builder.dart` | `resolvedAcp` 不再受团队 / 个人限制 |
| `client/lib/services/chat/launch/session/member_acp_stamp.dart` | `_memberAcpGates` 去掉团队模式与目标判定 |
| `client/lib/services/chat/launch/pre_send/local_binary_requirements.dart` | 跟随 `resolveMemberBindingAcp` 签名 |
| `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` | 跟随 `shouldAttachMemberAcp` 签名 |
| `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` | 调用点去掉 `isPersonal` 实参（`resolveLaunchAcp`） |
| `client/lib/services/automation/automation_dispatcher.dart` | 同上 |
| `client/lib/pages/config/*`、`models/*`、`cubits/*` | 命名重命名（第 5 节） |
| `client/lib/l10n/app_zh.arb`、`app_en.arb` | 删 4 条、加 2 条 |

胶囊本身用一个私有 widget 实现（`_CliTransportPill`），不抽公共组件——目前只有这一处
消费，会话内那段绑定的是 `WorkbenchCubit`，强行合并只会造出多余参数。

## 测试

| 文件 | 覆盖 |
|---|---|
| `client/test/pages/config/cli_config_section_test.dart` | 胶囊存在；点击 chat / terminal 写入偏好；Gemini 无胶囊；旧的开关行文案不再渲染 |
| `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart` | 会话级、成员级放开的用例；Android 仍为 false；`buildWorkspaceConversationCreateRequest` 团队用例翻成 true |
| `client/test/services/chat/launch/session_provisional_builder_test.dart` | 团队会话 `acp` 可置 true；ACP-only CLI 在团队里同样 resolve 为 true |

`unbound_compose_*_acp_test.dart` 断言的是 compose 页上不存在设置卡片开关
（`findsNothing`），不受本次改动影响。

`AppKeys.personalAcpSwitchFor` 继续挂在新控件的 `KeyedSubtree` 上，现有按 key 查找的断言
无需改写；如需语义一致可另开一次改名。

## 风险

- 「默认」只影响新建会话。tooltip 与文档必须写「新会话」，否则用户会以为切换会改变
  已有会话的运行时。
- 团队 lead 变成 ACP 后，team bus 投递走 `seat_prompt_delivery` 的 ACP 分支
  （已有实现，见 `51c6244d8`），需在团队场景实测一条 user command 往返。
- Android 平台门禁本次保留（`resolveLaunchAcp` 与 `_memberAcpGates` 的 `_isAndroid`）。
  远程 SSH exec 的适配器探活只有手工清单（`docs/remote-acp-adapter-smoke.md`），无自动化
  覆盖；拆 gate、放开 Android 胶囊单独排期。
- 远程成员放开后，`shouldAttachMemberAcp` 不再按目标过滤，WSL 目标也会走 ACP。
  WSL 的 exec 通道与 SSH 不同，需在实现后单独确认一次；若不通，只在 gate 中保留
  `RuntimeKind.local` 以外的白名单即可。
- 胶囊是纯图标，手机上无 hover、看不到 tooltip。若实测发现不可读，再在窄屏补一行
  11px 说明（本设计不包含）。

## 验收

1. `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
2. 桌面：新建个人 Claude 会话 → 默认走 ACP（无终端）；同一 CLI 切到终端 → 新建走 PTY。
3. 桌面：新建原生 Claude 团队会话 → lead 与成员均走 ACP，无终端面板，用户指令能送达。
4. 远程：SSH 工作区新建个人会话与团队成员会话 → 均走远端 ACP；按
   `docs/remote-acp-adapter-smoke.md` 跑一遍适配器缺失、安装、首轮对话三项。
5. 设置页：360dp 宽度下 header 不溢出，标题省略，胶囊与徽章完整显示。
6. Android：胶囊不渲染，行为与改动前一致。
