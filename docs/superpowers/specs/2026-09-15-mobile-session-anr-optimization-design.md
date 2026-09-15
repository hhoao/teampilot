# 移动端会话历史 ANR 优化设计（P0）

## 目标

解决 Android 打开会话后因历史全量加载导致的界面冻结、触摸无响应和 ANR。

当前日志显示的 P0 高风险路径是：

- Claude 历史分页读取失败后退回 full parse，单次加载约 59 秒；Debug 模式下大历史解析仍可能运行在 UI isolate。

成功标准是：打开会话时 UI isolate 不执行不可中断的大历史解析；后台任务失败不会清空已经显示的历史。

## 范围

包含：

1. Claude 及其他支持 full parse 的历史加载任务的 worker 化和取消/过期处理。
2. `page-first miss` 后的非阻塞 fallback 行为。
3. 历史 full parse 的阶段耗时日志与测试。

不包含：

- session manifest 全量扫描和 `sessions-index.json` 优化（后续 P1）。
- SSH 批量元数据读取和索引后台重建（后续 P1/P2）。
- 修改 SSH 协议或远端 CLI 的 transcript 格式。
- 改变历史消息去重语义。
- 删除用户 session 数据或自动清理历史文件。
- 重新设计聊天页面的视觉交互。

## 方案比较

### 方案 A：每次请求创建一次 isolate

让大 bundle 直接走现有 `Isolate.run`，并为每次请求增加超时和过期结果检查。

优点是改动小；缺点是现有代码已经记录过 Linux/Android Debug 下冷启动 isolate 可能不返回，且 worker 启动开销会重复发生。若超时后回退 UI 同步解析，仍会复现 ANR，因此不作为最终方案。

### 方案 B：常驻历史 worker（推荐）

新增可复用的历史解析 worker，所有大于阈值的 full parse 都通过 worker 执行。

优点是直接隔离 UI 与 CPU 重任务，同时覆盖 Debug、Profile 和 Release；worker 可复用并支持超时、取消和过期结果丢弃。代价是需要定义 worker 的消息协议并增加测试。

### 方案 C：UI isolate 分片解析

把 transcript 拆成小批次，在 UI isolate 每批之间主动让出事件循环。

优点是不依赖 isolate；缺点是需要改造所有 adapter 的解析接口，且在大文件上仍会消耗 UI 预算，只能作为 worker 不可用时的小文件或受控降级方案。

## 核心设计

### 1. 历史解析隔离

新增 `HistoryParseWorker`，生命周期由历史服务管理：

- 首次需要时启动，后续请求复用同一 isolate；
- 解析请求携带 request ID、adapter ID、transcript token 和 bundle；
- 结果返回 parsed messages、可选的 tool-result index 和阶段耗时；
- worker 启动和请求均有超时；
- 页面、session 或 token 变化后，调用方丢弃旧 request 的结果；
- worker 不可用时保留旧缓存并返回可展示的非阻塞错误，不能在 UI isolate 回退执行大文件 full parse。

小文件可以继续在调用 isolate 解析，但阈值必须以 bundle 字节数为准，且需要覆盖 Debug、Profile、Release。大文件无论构建模式都不能回退到 UI isolate 同步解析。

`page-first miss` 后的行为调整为：先发布已有缓存或加载状态，再将 full index 任务交给 worker。full index 完成后再通过 generation 检查发布结果。分页读取本身仍优先使用尾部范围读取，避免为了首次绘制传输整个 transcript。

### 2. 刷新与并发控制

- 同一 session/member 的 full parse 只允许一个在途请求；
- live refresh 在 full index 任务进行时合并为一次后续刷新；
- 页面离开、seat 变化或 token 过期后，旧任务结果不可覆盖当前 seat；
- 读取失败或短暂空结果保留当前非空历史和附件；
- full index 任务进行时，live refresh 只排队，不重复启动 full parse。

### 3. 可观测性

为冷加载输出 bundle 字节数和以下阶段耗时：`locate`、`read`、`parse`、`enrich`、`inflate`、`merge`。

所有超过 1 秒的历史阶段记录 warning 或 debug 诊断，但不输出完整消息内容或敏感 transcript。

## 错误处理

- worker 超时：丢弃 worker、保留现有缓存，并允许下一次刷新重新建立 worker。
- worker 解析错误：显示非阻塞历史错误状态，不影响终端和输入框。
- SFTP 暂时断开：沿用现有 transport failure 语义，不把断开误判为空历史。
- 结果过期：通过 request generation、session ID、member ID 和 token 检查后静默丢弃。

## 测试和性能门槛

新增或调整以下测试：

1. 大 bundle 在 Debug 模式不会调用 UI isolate 上的同步 full parse；worker 超时不会阻塞或清空已有消息。
2. worker 结果在 session/member/token 变化后不会发布到旧 seat。
3. page-first miss 后先维持可交互状态，后台 full index 完成后历史数量正确。
4. 运行相关单元测试、页面测试和一次完整测试套件。

性能目标：

- 打开会话期间 UI isolate 不进行超过 100 ms 的连续大历史解析；
- full parse 不重复读取同一个 transcript；
- 后台失败不造成空白会话。

## 分阶段实施

### P0：止住 ANR

实现历史 full parse 的 worker 隔离、超时、过期结果保护和非阻塞 fallback，并保留已有内容。
