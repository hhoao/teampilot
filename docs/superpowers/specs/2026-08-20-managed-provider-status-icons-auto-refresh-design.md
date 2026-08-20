# Managed Provider 状态栏图标、总开关与自动刷新设计

日期：2026-08-20

状态：已确认（延续 2026-08-20 官方登录与用量查询）

## 背景

用量已出现在左下角状态条，但辨识度不够：一律钱包图标，列表/弹出层图标与两行文字整体居中，看起来不跟第一行名称对齐。官方 Codex 用量 5 分钟即标过期并显示警告，桌面窗口一直开着时又没有定时轮询，只能靠手动刷新。编辑页的启用开关藏在「高级」里，用户找不到；同时需要一个总开关：关掉后既不出现在左下角，也不再查询。

对照：Orca 默认 15 分钟后台轮询、约 30 分钟才丢快照；cc-switch 可配自动查询（默认 5 分钟，0 表示关闭）。TeamPilot 采用 **一个总开关 + 10 分钟自动刷新**，不拆成「只隐藏、后台仍刷」。

## 目标

1. `enabled` 作为总开关：关 = 左下角不出现 + 不自动查询 + 不参与 `refreshAll`；开 = 出现在左下角并参与用量查询。
2. 总开关在编辑页基础信息、管理列表暂停按钮、左下角弹出层每行都能改，三处写同一字段。
3. 打开的 Provider 每 10 分钟 `ensureFresh`；官方 Codex/Claude 的 `staleAfter` 改为 10 分钟，与轮询对齐。
4. 列表、左下角、弹出层使用现有 `ProviderBrandIcon` 品牌图，不再用通用钱包图标。
5. 两行排版的图标与第一行名称顶部对齐。

## 非目标

- 独立的「自动查询间隔」字段或「只隐藏仍后台刷」。
- 编辑页图标上传 / 从图库挑选。
- 远程图标下载失败的精细重试与缓存策略。
- Gemini / Copilot 等新官方适配器。
- 失败后加快轮询（避免打爆官方接口）。

## 总开关

沿用 `ManagedProvider.enabled` 和 `ManagedProviderState.enabledProviders`。不新增 JSON 字段。

| 打开 | 关闭 |
|---|---|
| 左下角状态条与弹出层列出 | 立刻从两者移除 |
| 参与 10 分钟自动刷新、resume 过期检查、`refreshAll` | 不发请求；取消该 id 的在途查询 |
| 管理页列表仍显示（徽章为已启用） | 管理页列表仍显示（徽章为已停用），可再打开 |

编辑页：启用开关从「高级」挪到 **基础信息**（名称下面），基础信息默认展开。高级区不再重复该开关。

左下角弹出层：每行一个开关（与列表暂停同一语义）。不必进管理页即可关掉某个 Provider。

管理列表：保留现有暂停 / 启用按钮。

## 自动刷新

只对 `enabledProviders` 调用 `ManagedProviderUsageCubit.ensureFresh`。

| 触发 | 行为 |
|---|---|
| 启用后的周期 | 每 **10 分钟** 对每个已启用 Provider 跑 `ensureFresh` |
| 应用回到前台 | 保留现有 `AppLifecycleState.resumed` 过期检查 |
| 快照未过期 | `ensureFresh` 不发网络请求 |
| 关闭某个 Provider | `cancelForProvider`，并从下一轮周期中排除 |
| 查询失败 | 保持快照错误态；**不**缩短下一轮间隔 |

官方适配器 `staleAfter`：Codex / Claude 从 5 分钟改为 **10 分钟**。过期前状态条不因 stale 显示警告。自定义 HTTP 若未声明 `staleAfter`，行为不变。

定时器挂在 app shell / usage cubit 生命周期上：控制面关闭时取消；storage context 切换时先 `invalidateForStorageContextChange`，再只刷新新 home 下已启用的 Provider。

左下角弹出层的手动刷新按钮仍调用 `refreshAll`（仅已启用）。查询失败不弹全局 toast（列表与弹出层已有错误展示）。

## 图标

复用 `ProviderBrandIcon` 与 `assets/providers/*.svg`，不新增图标体系。

解析顺序（一处 helper，列表 / 状态条 / 弹出层共用）：

1. `official-codex-subscription` → bundled `openai`
2. `official-claude-subscription` → bundled `claude`
3. `http-json` 且 endpoint host 为 `api.deepseek.com`（或名称大小写不敏感等于 `DeepSeek`）→ bundled `deepseek`
4. 合法 `brand.iconUrl` → 远程图
5. 否则 `ProviderBrandIcon` 名称首字母

不在 JSON 里新增图标字段。自定义不强制填图标。

### 状态条

- 0 个已启用：保持现有空态文案（添加入口），无品牌图标墙。
- 1 个：该 Provider 品牌图标 + 用量数字。
- 多个：并排小品牌图标 + 数量，不用钱包图标。

### 列表与弹出层

每行左侧用品牌图标替换 `CircleAvatar` / `Icons.account_balance_outlined`。

## 对齐

两行文字（名称 + 副标题）旁的图标：

- `CrossAxisAlignment.start`
- 图标高度接近第一行：列表约 20px，弹出层约 15px
- 图标 top 与名称 top 对齐（测试允许 1px 误差），不再对两行块垂直居中

状态条只有一行：图标与数字 `CrossAxisAlignment.center`。

## 数据流

```
AppShell
  10min timer + onResume
    → usage.ensureFresh(id) for each enabledProviders
        → coordinator（缓存未过期则跳过 HTTP）

UI toggle enabled
  → ManagedProviderCubit.save
    → enabledProviders 变化
      → 状态条/弹出层立刻过滤
      → 若关闭：usage.cancelForProvider(id)
```

## 错误处理

- 自动刷新失败：写入该 Provider 快照的 typed error，不 `AppToast`。
- 远程 `iconUrl` 加载失败：回退首字母，不阻塞用量查询。
- 未知 adapter：首字母回退，不得抛错。

## 测试

- 关闭后：状态条与弹出层找不到该行；`refreshAll` / 定时 `ensureFresh` / resume 不调用其 adapter。
- 打开后：重新出现在状态条；进入下一轮 `ensureFresh`。
- 编辑页基础信息、列表暂停、弹出层开关读写同一 `enabled`。
- 10 分钟后对已过期快照发请求；未过期不发。官方 `staleAfter` 为 10 分钟，过期前无 stale 警告。
- 关闭时取消在途请求。
- Codex / Claude / DeepSeek 行渲染 bundled 品牌图，不出现钱包图标。
- 自定义无 `iconUrl` 时为首字母。
- 列表与弹出层：图标 top 与名称 top 差 ≤ 1px。
- 多个已启用时状态条出现多个品牌图标。

不测：远程图标网络失败矩阵、图标上传 UI、隐藏但仍后台查询。
