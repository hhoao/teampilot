# TeamPilot Linux 卡死调查记录（2026-08-11）

> 三次同构卡死的完整证据链、原始堆栈、锁关系图，以及候选根因分析。
> 相关 issue: https://github.com/dart-lang/sdk/issues/64018

## 1. 现象

- Flutter Linux debug 应用（`flutter run -d linux`，Dart 3.12.2 / Flutter 3.44.3，引擎 `a4ce257c68`）
- 症状：界面完全无响应，日志停更，VM service / agent-status HTTP 全部无响应
- 复发模式：**会话（PTY）连接后**发生；机器重负载（load 8-20）下更容易触发
- 三次实例：

| 时间 | 进程 | 卡死前最后日志 |
|------|------|----------------|
| 10:38 | 3475078 | `[terminal] started CLI` |
| 16:23 | 1734509 | `tab-prep done`（会话连接） |
| （另有两次同构复现于 08-10 日志尾） | — | — |

## 2. 抓栈方法

- `sudo sysctl kernel.yama.ptrace_scope=0` 后 `gdb -p <pid> -batch -ex "thread apply all bt 40"`
- 锁 owner 读取：pthread_mutex_t 布局 `__lock(+0) __count(+4) __owner(+8) __nusers(+12) __kind(+16)`，`__owner` 即持有者 TID
- 关键验证：**1 小时后复读锁状态完全不变**（owner 相同）→ 永久死锁，非瞬时竞争

## 3. 原始证据（第三次，LWP 1734509）

### 3.1 主线程（UI / VM service 冻结的根源）

```
#4  __GI___futex_abstimed_wait_cancelable64 (futex_word=0x5d48b3d7d56c, abstime=0x0)  ← 无超时
#6  ___pthread_cond_wait (cond=<optimized out>, mutex=0x5d48b3d7d518)
#7  0x...4f5f503 libflutter_linux_gtk.so   ← VM 消息循环 wait（MessageHandler）
#8  0x...511274f libflutter_linux_gtk.so
#9  0x...5112b3e libflutter_linux_gtk.so
#10 0x...50a7ae9 libflutter_linux_gtk.so
#11 0x779500102f63  ← JIT 过渡帧（Dart 代码进入 VM）
```

### 3.2 dart:io EventHandler（IO 断流根源）

```
#0  futex_wait (futex_word=0x5d48b3d493b0, expected=2)
#3  ___pthread_mutex_lock (mutex=0x5d48b3d493b0)      ← 锁 X
#4  0x...5089f6c libflutter_linux_gtk.so              ← 事件投递入口
#5  0x...5382747 kDartVmSnapshotInstructions
```

### 3.3 DartWorker 2913260 —— 持锁永久挂起（核心症结）

```
#4  __GI___futex_abstimed_wait_cancelable64 (futex_word=0x7794b800e998, abstime=0x0)  ← 无超时
#6  ___pthread_cond_wait (cond=<optimized out>, mutex=0x7794b800e948)  ← 条件 C
#7-#10 与主线程完全相同的消息循环帧（0x4f5f503 / 0x511274f / 0x5112b3e / 0x50a7ae9）
实测：锁 W (0x77933c028828) 的 __owner = 2913260 —— 它在 cond_wait 的同时持有 W
```

### 3.4 DartWorker 2771203 —— 持锁 X 等锁 W

```
#3  ___pthread_mutex_lock (mutex=0x77933c028828)      ← 等锁 W
#4  0x...4ff10d1 libflutter_linux_gtk.so              ← VM 运行时
#8  0x7795001030b4                                    ← JIT 帧（在跑 Dart 任务）
```

### 3.5 DartWorker 2913261 —— 持锁 Y 等锁 X

```
#3  ___pthread_mutex_lock (mutex=0x5d48b3d493b0)      ← 等锁 X
#4  0x...5089f6c  ← 与 EventHandler 同一入口函数
```

### 3.6 锁状态表（gdb 实测，两次读取相隔 >1 小时，完全一致）

| 锁 | 地址 | 区域 | owner（持锁线程） | 等它的人 |
|----|------|------|-------------------|----------|
| X | 0x5d48b3d493b0 | glibc 主堆（VM 全局） | 2771203 (DartWorker) | EventHandler、2913261、4×teampilot 线程 |
| W | 0x77933c028828 | 独立堆（isolate/worker 级） | 2913260 (DartWorker) | 2771203 |
| Y | 0x5d48b379ee58 | glibc 主堆（VM 全局） | 2913261 (DartWorker) | 2840052、2892248、2913015 |
| C | 0x7794b800e948 | 独立堆 | —（cond_wait 已释放） | 2913260 无超时等待，永无 signal |

## 4. 锁关系图（修正版：链式阻塞，非标准环形）

```
2913260: 持 W + 永久等条件 C（无超时 cond_wait）       ← 核心异常：持锁永久挂起
   ↑ 2771203: 等 W（自身持 X，正在跑 Isolate.run 任务，栈带 JIT 帧）
      ↑ EventHandler: 等 X → dart:io 事件流断 → 定时器/socket 全部停
         ↑ 主线程: MessageHandler 等消息 → UI/VM service/日志全冻结
2913261: 持 Y 等 X（另一条被 X 阻塞的路径）
```

影响：`pthread_cond_wait` 释放其参数 mutex（0x7794b800e948），但**不会**释放外层持有的 W → 2913260 持有 W 永久等待。

## 5. 三次复现的对照

三次死锁的 libflutter 帧偏移族完全一致（如 `9f6c / 3bc5 / 22ba`、`f503 / 274f / 2b3e / 7ae9`、`10d1 / a048 / 1669 / 23fe`）→ 同一代码路径、同一锁序缺陷，属确定性 bug 而非随机竞争。

## 6. 触发条件（推断，按可信度排序）

1. 会话连接后历史加载：主 isolate 同步执行 opencode SQLite 拷贝/读取（40MB+）+ `Isolate.run` 解析（worker isolate）
2. 机器重负载（load 8-20，多进程抢 CPU）放大竞争窗口
3. `enable-dart-profiling=true`（debug 默认）的 profiler 采样信号
4. 主 isolate 的语义树 O(n²) 遍历（`isBlockingPreviousSibling`）加剧主 isolate 长时间忙碌

## 7. 候选根因假说

### 假说 A（主假说）：VM worker 持锁永久等待

一个 DartWorker（2913260）在 VM 内部路径上**持有锁 W 的同时进入无超时条件等待**（cond_wait 的条件 C 永不 signal）。W 由此永久不可获得，形成链式阻塞。与 Dart SDK `runtime/vm/thread_pool.cc` 的 `WorkerLoop` 结构吻合：`MutexLocker ml(&pool_mutex_)` 期间调用 `worker->Sleep(...)`（cond_wait 只释放 worker 自身 monitor，pool_mutex_ 保持持有）；而 `ScheduleTaskLocked` / `Wakeup` 同样需要 pool_mutex_ —— 一旦持锁者无法被唤醒，线程池整体瘫痪。

### 假说 B：Sleep 无超时路径 + 唤醒自锁

`Worker::Sleep` 的正常调用带 5s 超时（`FLAG_worker_timeout_millis=5000`），但实测 2913260 走的是**无超时** `pthread_cond_wait`（abstime=0x0）。若该 worker 因某种原因进入无超时等待（超时参数丢失/错误分支/引擎 flag 被设为 0），则持 pool_mutex_ 永睡，Wakeup 需要同一把 pool_mutex_ → 无人能唤醒它 → 死锁。三次复现中均观察到 worker 在退出路径（`call_tls_dtors`）和 `pthread_join` 死链，与 WorkerLoop 退出时的 `JoinDeadWorker(previous_dead_worker)` 吻合。

### 假说 C：多线程池交叉

锁 X/Y 在 glibc 主堆、W/C 在独立堆，暗示涉及两个不同的 VM 组件（如 isolate group 的 pool 与 registry）。不同组件间锁序未全局一致 → 特定交错下成环。

### 假说 R（新增，反汇编证据）：runtime entry 等待路径 / isolate 暂停

通过反汇编 libflutter_linux_gtk.so（objdump + .rodata 字符串解码）确认：

- 主线程与 2913260 栈的 #10 帧（0x50a7ae9）位于 **runtime_entry.cc** 的 runtime entry 区域，函数体引用字符串：
  `"InterruptOrStackOverflow"` `"SwitchableCallMiss"` `"NoSuchMethodFromPrologue"` `"NoSuchMethodFromCallStub"` `"InvokeNoSuchMethod"` `"InterpretedInstanceCallMissHandler"` `"NoSuchMethodError"` `"expected: %s"` `"!FLAG_precompiled_mode"` `"Dispatcher for %s should have been lazily created"` + assert `"unreachable code"` @ runtime_entry.cc:3769
- 即：**等待发生在「中断/栈溢出/OOB 消息处理」类 runtime entry 路径**（`InterruptOrStackOverflow` → `HandleInterrupts` → OOB 消息处理，可能进入 `Isolate::Pause` 的 monitor 等待），而非普通的"等任务/等消息"路径
- **触发关联**：真实 app 的语义树 O(n²) 深层递归（`isBlockingPreviousSibling`，实测栈深 93+）可能触发**栈空间检查/栈溢出** → 进入 InterruptOrStackOverflow → 等待路径 → 持锁 → 全链阻塞
- **这解释了 repro 为何难以复现**：repro 未模拟深层递归/栈溢出路径

## 7.5 反汇编方法（可复现）

```
# 定位函数：gdb bt 拿帧地址 → 减去引擎 base → objdump -d 反汇编
# 提取函数引用的 .rodata 字符串：objdump 的 lea rip+offset 注释 → 读 .so 文件偏移
# 例：0x24a7a00 区域（运行时 0x50a7ae9 - base 0x4f00000... 见正文）
```

## 8. 已排除的路径

- sqlite（文件锁/自有锁，栈中无相关帧；拷贝均在临时目录）
- flutter_pty_new / alacritty（tokio 线程全部空闲）
- 应用层 Dart 锁（package:sync 等；死锁线程栈无应用帧，等待的是 pthread 锁）
- 调试器暂停（VS Code 显示运行中；且 debugger pause 时 VM service 应响应，实测无响应）
- OOM/内存（swap 压力存在但锁状态稳定，非内存问题）

## 9. 复现尝试

| 尝试 | 环境 | 结果 |
|------|------|------|
| 纯 Dart 压力（4 个变体） | `dart run` JIT | 未复现 |
| Flutter 引擎 repro app（v3-v7） | 直接跑 debug binary | 未复现 |
| 环境对齐后（profiling+checked-mode+主 isolate 分配压力） | v6-v8 | 进行中 |
| 陷阱发现：`start-paused=true` 会导致无调试器时 PauseStart 卡死（非目标死锁），已在 v6+ 移除 | — | — |

## 10. 缓解建议（应用侧）

1. `ai_history_loader.dart:308` 与 `ai_transcript_tail_reader.dart:13` 的 `Isolate.run` → 受控 worker 池或调用方 isolate 解析（复用 `tree_sitter_worker_pool.dart` 模式）
2. 主 isolate 的 sqlite 读取移出主 isolate（减少主 isolate 长时间同步占用）
3. 语义树 O(n²)：`SemanticsBinding.instance.disableSemantics()`（桌面工具无需无障碍）或对动态内容区 `ExcludeSemantics`
