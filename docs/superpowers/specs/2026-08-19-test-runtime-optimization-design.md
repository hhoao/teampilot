# Test Runtime Optimization Design

## Goal

降低 TeamPilot Flutter 测试的单文件启动成本，并消除 managed provider widget
测试失败后长时间不退出的问题，同时保持终端、搜索和集成测试的覆盖范围不变。

## Evidence and constraints

- `client/test` 当前约有 1267 个测试文件，默认测试命令已经排除 `integration` 标签。
- `client/test/flutter_test_config.dart` 对每个测试进程无条件加载
  `flutter_alacritty` Rust 动态库；只有终端或 native search 相关测试真正需要该库。
- 单独运行普通测试时，加载阶段通常占数秒；`--no-test-assets` 可进一步减少不需要资源包的测试启动时间。
- `pumpAndSettle` 的默认超时为 10 分钟，持续帧或后台异步任务会把测试失败放大成超时。
- `managed_provider_management_page_test.dart` 当前在缓存用例中找不到 `12.50 USD`，断言失败后仍不能及时退出。
- 工作区存在用户未提交改动；本设计只允许修改测试基础设施和相关测试，不覆盖其他改动。

## Chosen approach

采用四部分、低耦合的测试侧优化：

1. 全局测试配置只负责通用 timer 清理，不再初始化 Rust。
2. Rust 初始化改为测试文件级 `setUpAll`，并使 helper 在同一进程内可安全重复调用。
3. managed provider 页面测试显式等待页面启动的两个 Cubit，并关闭测试创建的 coordinator；页面交互等待改用确定性的 frame/状态等待。
4. 只替换已确认存在持续帧风险的高频 `pumpAndSettle`，不盲目全仓库机械替换。

## Detailed design

### 1. Test bootstrap

`client/test/flutter_test_config.dart` 保留 `testExecutable` 和 debounce/throttle
清理逻辑，但删除 `rust_lib_test_init.dart` 的导入和初始化调用。

`client/test/support/rust_lib_test_init.dart` 保留现有路径解析逻辑，并增加进程内
初始化 future 缓存。需要 Alacritty Rust API 的测试文件在 `main()` 顶层增加：

```dart
setUpAll(initRustLibForTests);
```

纯数据、Cubit、Repository 和不创建 Alacritty engine 的 widget 测试不初始化该库。
涉及 native search 的测试仍按其自身 native asset 要求运行，不能将 Alacritty 初始化
与 `teampilot_search` 初始化混为一谈。

### 2. Managed provider widget test lifecycle

`managed_provider_management_page_test.dart` 的页面 helper 在第一次 frame 执行页面
的 post-frame callback 后，显式等待 `ManagedProviderCubit.load()` 和
`ManagedProviderUsageCubit.load()`，然后只 pump 必需的 frame。这样测试验证的是已加载
状态，而不是依赖 `pumpAndSettle` 猜测异步工作何时结束。

测试 setup 保存 `ManagedProviderUsageCoordinator` 实例，并在 teardown 中关闭它；
Cubits 关闭后不再允许 coordinator 的后台 future 使用已销毁的测试状态。

页面缓存用例继续验证两件事：缓存 measure 可见、adapter 没有被调用。若 readiness
等待后仍找不到 measure，应修复页面/Cubit 状态传播，而不是放宽断言。

### 3. Bounded widget waiting

优先在高频且已知有路由、抽屉或虚拟列表动画的测试中，用项目已有的固定 frame
helper 或少量显式 `pump(Duration(...))` 替换 `pumpAndSettle`。等待异步状态时使用
明确的 Cubit 状态/控件存在性条件，并设置短上限；超时时报告具体条件。

不改变产品代码中的动画时长，也不把所有 `pumpAndSettle` 一次性替换为固定 sleep。

### 4. Test execution guidance

为不依赖 Flutter asset bundle 的纯测试记录并采用 `--no-test-assets`；需要资源的
widget 测试继续使用默认 asset 行为。CI 使用受控并发或 test sharding，避免把每个
Flutter test process 的内存成本叠加到机器上。

## Error handling

- Rust 动态库路径不存在或加载失败时，只有显式依赖 Rust 的测试失败，并保留现有清晰错误。
- readiness 等待超时必须报告等待条件，不使用无限等待。
- teardown 关闭资源时保持幂等，不能因为测试主体已失败而掩盖原始断言。
- 集成测试标签、Docker/PTY 前置条件和默认排除策略保持不变。

## Verification

按以下顺序验证：

1. managed provider 页面测试单文件运行，确认全部通过且失败不再拖到测试进程超时。
2. 一个纯测试文件运行，确认不再执行全局 Rust 初始化；一个终端相关测试文件运行，确认显式初始化后仍通过。
3. 高风险 widget 测试文件定向运行，确认没有 `pumpAndSettle` 超时。
4. 受影响测试集合运行：`flutter test --exclude-tags integration` 的定向子集及必要的
   `flutter analyze --no-fatal-infos --no-fatal-warnings`。
