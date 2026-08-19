# Managed Provider 自适应编辑器设计

## 背景

当前 Managed Provider 编辑器把预设、请求协议、响应映射、凭据存储和显示覆盖全部平铺在一个长表单中。对于只想添加一个可查询余额的 Provider 的用户，必须理解 adapter、JSONPath、credentialRef 等内部概念，容易误配，也无法清晰判断哪些字段是必填项。

本次改造的目标是让“选择预设 → 补充凭据 → 保存并查询”成为默认路径，同时保留完整的自定义 HTTP 能力，并为后续新增 Provider 类型提供声明式扩展点。

## 目标与非目标

### 目标

- 新建 Provider 默认只展示当前类型真正需要填写的字段。
- 预设自动填充可复用的连接、凭据和响应映射配置。
- 保存后可自动执行首次余额查询，并明确显示缺少配置的原因。
- 自定义 HTTP Provider 仍支持完整请求/响应映射能力，但默认折叠。
- 页面不依赖具体 Provider 名称进行分支，新增预设主要通过 schema/config 扩展。
- 编辑已有 Provider 时保留现有数据兼容性，空 API Key 不覆盖已有密钥。

### 非目标

- 本次不把 Managed Provider 与各 CLI Provider 列表关联。
- 本次不重新设计余额查询适配器协议和安全存储协议。
- 本次不实现远程 Provider 市场或在线预设同步。

## 用户体验设计

### 默认新建流程

页面采用单页 body 内编辑，不创建全屏路由页面。顶部显示返回、标题和保存动作；正文按配置层级组织：

1. **快速预设**
   - 使用可搜索选择器列出 Codex、Claude Code、DeepSeek、OpenCode 等预设。
   - 选择预设后立即填充名称、Provider 类型、查询能力、凭据字段和默认映射。
   - 下方展示简短摘要，例如“DeepSeek · API 余额 · 保存后可查询”。

2. **基础信息**
   - Provider 名称。
   - 预设已经确定的类型和查询方式以只读摘要展示；只有自定义 Provider 才允许选择类型。
   - 凭据输入由当前 schema 生成。API Key/Token 默认遮罩，空值表示编辑时保留原密钥。
   - `credentialRef` 不作为普通用户字段展示；系统按 Provider 身份自动生成和维护。

3. **首次查询**
   - 新建保存默认执行一次查询。
   - 查询中显示明确状态，成功后返回列表并展示余额。
   - 没有必需凭据时阻止查询并把焦点定位到缺失字段，而不是展示底层 adapter 错误。

### 折叠区块

- **查询设置**：自定义 HTTP 类型显示 URL、HTTP 方法、请求体、响应路径、余额列表路径和字段映射。
- **凭据高级设置**：凭据字段名、Header/Query/Body 放置位置、前缀和 Header 名称。
- **显示覆盖**：货币、单位、小数位、百分比显示。默认值为空时由响应动态值决定。
- **高级**：adapter id、内部 credentialRef、启用状态和调试信息。默认折叠，Provider 预设场景只读或隐藏。

折叠状态只影响 UI，不丢失表单值。已有 Provider 如果包含非默认配置，相关区块自动展开并显示“已配置”标识，避免隐藏用户现有设置。

## 声明式扩展模型

编辑器不再通过 Provider 名称写条件分支，而是使用 `ManagedProviderEditorSchema` 描述 UI 能力：

- `kind`: API balance、subscription quota、custom HTTP 等能力类型。
- `sections`: 基础、查询、凭据、显示、高级区块的可见性和默认展开状态。
- `fields`: 字段 key、标签、输入类型、是否必填、默认值和安全属性。
- `credential`: 凭据字段、存储键、放置位置和前缀的声明。
- `query`: 是否支持保存后查询，以及缺少配置时的校验规则。

预设提供 schema 的初始值；适配器注册表提供能力约束和查询行为。UI 只负责渲染 schema、校验和生成 `ManagedProvider`，不识别具体的 DeepSeek/Codex 等名称。

现有 `ManagedProviderPreset` 可逐步扩展为携带 editor schema；旧 Provider JSON 没有 schema 时，根据现有 `kind`、`adapterId` 和 endpoint 配置推导兼容 schema。

## 数据流与保存语义

```text
Preset / existing Provider
        ↓
Editor schema + initial values
        ↓
Basic form validation
        ↓
Secure credential store ← secret value
        ↓
ManagedProvider JSON ← credentialRef only
        ↓
Provider repository upsert
        ↓
Optional first usage query
```

- API Key 永远不进入 Provider JSON、请求映射或快照。
- 新 Provider 的 credentialRef 由系统生成，编辑时沿用已有引用。
- 编辑时凭据输入为空表示保留已有密钥；显式输入新值才更新安全存储。
- 保存失败时保持编辑页和用户输入，展示本地化错误。若 Provider 持久化失败，保存流程必须恢复更新前的旧密钥；新 Provider 则删除本次新建的 credentialRef，避免产生孤儿密钥。
- 货币优先使用响应字段映射，显示配置中的 currency 只作为 fallback；小数位可由预设提供默认值。

## 验证策略

- Widget 测试：预设选择后只出现相关字段，通用高级区块默认折叠。
- Widget 测试：DeepSeek 只需填写 API Key 即可生成正确 Provider，并保留动态 currency 映射和两位小数默认值。
- Widget 测试：编辑时空 API Key 不覆盖已有安全存储值。
- Widget 测试：自定义 HTTP 展开后可编辑完整请求/响应映射。
- Service/adapter 测试：schema 生成不依赖具体页面分支，旧 Provider JSON 可以推导兼容 schema。
- 回归现有 CRUD、首次查询、错误状态和 body 内导航测试。

## 迁移与兼容性

- 不修改已有 Provider JSON 格式。
- 保留现有 adapter 和 credential store 接口。
- 已有自定义字段在首次打开时按照“非默认配置自动展开”策略呈现。
- 旧版本没有 `editor schema` 的 Provider 使用运行时推导，不需要迁移文件。
