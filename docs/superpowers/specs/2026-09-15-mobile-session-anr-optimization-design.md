# 移动端会话 ANR 优化设计

## 目标

解决 Android 打开会话后因历史加载和 session 元数据扫描导致的界面冻结、触摸无响应和 ANR。

当前日志显示两个高风险路径：

- Claude 历史分页读取失败后退回 full parse，单次加载约 59 秒；Debug 模式下大历史解析仍可能运行在 UI isolate。
- `_readManifest(indexOnly: false)` 为 176 个 session 串行读取元数据，单次扫描约 87 秒；本地文件系统路径还包含同步目录和文件读取。

成功标准是：打开会话时 UI isolate 不执行不可中断的大历史解析或全量 session 扫描；后台任务失败不会清空已经显示的历史。

## 范围

包含：

1. Claude 及其他支持 full parse 的历史加载任务的 worker 化和取消/过期处理。
2. `sessions-index.json` 优先的 session ID 和侧边栏元数据读取。
3. 索引失效时的后台懒重建，以及 Android SSH 读取的并发上限。
4. 历史加载、索引读取和 ANR 风险路径的阶段耗时日志与测试。

不包含：

- 修改 SSH 协议或远端 CLI 的 transcript 格式。
- 改变历史消息去重语义。
- 删除用户 session 数据或自动清理历史文件。
- 重新设计聊天页面的视觉交互。

## 方案比较

### 方案 A：最小修补

删除本地同步扫描，并尽量让 Debug 走现有 `Isolate.run`。

优点是改动小；缺点是现有代码已经记录过 Linux/Android Debug 下冷启动 isolate 可能不返回，仍可能出现僵尸任务或回退到 UI 同步解析。因此不作为最终方案。

### 方案 B：常驻历史 worker + 索引优先（推荐）

新增可复用的历史解析 worker，所有大于阈值的 full parse 都通过 worker 执行；会话 manifest 读取优先使用 `sessions-index.json`，索引修复放到后台。

优点是直接隔离 UI 与 CPU/IO 重任务，同时覆盖本地和 SSH 场景；worker 可复用并支持超时、取消和过期结果丢弃。代价是需要定义 worker 的消息协议并增加测试。

### 方案 C：远端批量元数据接口

通过一次远端 shell 命令或专用协议批量返回 session 元数据。

远端性能最好，但会扩大 SSH 层和权限处理范围，不适合作为本次 ANR 修复的第一步。

## 核心设计

### 1. 历史解析隔离

新增 `HistoryParseWorker`，生命周期由历史服务管理：

- 首次需要时启动，后续请求复用同一 isolate；
- 解析请求携带 request ID、adapter ID、transcript token 和 bundle；
- 结果返回 parsed messages、可选的 tool-result index 和阶段耗时；
- worker 启动和请求均有超时；
- 页面、session 或 token 变化后，调用方丢弃旧 request 的结果；
- worker 不可用时保留旧缓存并返回可展示的非阻塞错误，不能在 UI isolate 回退执行大文件 full parse。

小文件可以继续在调用 isolate 解析，但阈值必须以 bundle 字节数为准，且需要覆盖 Debug、Profile、Release。

`page-first miss` 后的行为调整为：先发布已有缓存或加载状态，再将 full index 任务交给 worker。full index 完成后再通过 generation 检查发布结果。分页读取本身仍优先使用尾部范围读取，避免为了首次绘制传输整个 transcript。

### 2. Session 索引优先

调整 session 元数据读取层：

- `_readManifest` 在只需要 workspace folders、placement 或 session ID 时，不读取所有 `session.json`；
- 优先读取 `sessions-index.json`，并通过一次目录列表检查 ID 集合是否一致；
- 索引命中时只解码一个小文件；
- 索引缺失、损坏或不一致时返回可用的当前数据，并启动一次后台 rebuild；
- rebuild 使用有上限的并发读取，避免 Android SSH 上逐个串行 `stat + read`；
- 本地文件系统不再在 UI isolate 使用 `listSync`、`readAsStringSync` 扫描 session；
- 已有的 known workspace 或 index-only 数据优先复用，避免会话打开期间重复读取 manifest。

索引仍是派生数据，`session.json` 保持事实来源。创建、重命名、删除和必要的 placement 更新继续同步维护索引；后台 rebuild 用于修复外部变更或旧版本遗留的不一致。

### 3. 刷新与并发控制

- 同一 session/member 的 full parse 只允许一个在途请求；
- live refresh 在 full index 任务进行时合并为一次后续刷新；
- 页面离开、seat 变化或 token 过期后，旧任务结果不可覆盖当前 seat；
- 读取失败或短暂空结果保留当前非空历史和附件；
- 不因 workspace manifest 的 placement 更新重新扫描所有 session。

### 4. 可观测性

为冷加载输出 bundle 字节数和以下阶段耗时：`locate`、`read`、`parse`、`enrich`、`inflate`、`merge`。

session 元数据日志增加 filesystem 类型、索引命中/失效、读取数量和 rebuild 状态。所有超过 1 秒的阶段记录 warning 或 debug 诊断，但不输出完整消息内容或敏感 transcript。

## 错误处理

- worker 超时：丢弃 worker、保留现有缓存，并允许下一次刷新重新建立 worker。
- worker 解析错误：显示非阻塞历史错误状态，不影响终端和输入框。
- SFTP 暂时断开：沿用现有 transport failure 语义，不把断开误判为空 session 或空历史。
- 索引损坏：忽略索引并后台重建；重建失败不覆盖旧索引。
- 结果过期：通过 request generation、session ID、member ID 和 token 检查后静默丢弃。

## 测试和性能门槛

新增或调整以下测试：

1. 大 bundle 在 Debug 模式不会调用调用 isolate 上的同步 full parse；worker 超时不会阻塞或清空已有消息。
2. worker 结果在 session/member/token 变化后不会发布到旧 seat。
3. session index 命中时不读取任何 `session.json`；索引失效时只启动一次 rebuild。
4. 176 个 session 的远端模拟读取使用并发上限，不进行串行 176 次读取。
5. page-first miss 后先维持可交互状态，后台 full index 完成后历史数量正确。
6. 运行相关单元测试、页面测试和一次完整测试套件。

性能目标：

- 打开会话期间 UI isolate 不进行超过 100 ms 的连续历史解析或 session 扫描；
- 索引命中路径只读取 manifest、sessions-index 和一次目录列表；
- full parse 不重复读取同一个 transcript；
- 后台失败不造成空白会话。

## 分阶段实施

### P0：止住 ANR

先实现历史 full parse 的 worker 隔离、超时和过期结果保护，并保留已有内容。

### P1：缩短会话打开链路

让 `_readManifest` 和 placement 更新走 index-only/index-first 路径，移除 UI 同步扫描，补充索引命中和失效测试。

### P2：完善后台修复和诊断

加入有上限的 SSH 并发 rebuild、阶段耗时日志和性能回归测试。

