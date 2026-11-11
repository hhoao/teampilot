# 按级别分目录的文件日志 + latest.log 滚动

## 背景

`AppLogger` 把所有级别写进同一个滚动文件：

`{appDataRoot}/logs/app_YYYY-MM-DD.log`

超过 5MB 时改开 `app_YYYY-MM-DD_<stamp>.log`。应用内日志查看器（设置 → 关于 → 查看日志）列出该目录下全部 `.log` / `.jsonl`，再用行过滤按 DEBUG / INFO / WARNING / ERROR 筛。Release 构建不把 DEBUG 落盘；debug 构建会。

另有 `ErrorLogService` 把结构化、按天去重的错误写到 `{appDataRoot}/logs/errors.jsonl`。这和 `AppLogger.e()` 的纯文本不是同一份文件。

混在一个文件里时，排障要在大量 debug/info 里翻 error/warn；`tail` 路径也不稳定（日期、滚动戳都会变）。

## 目标

1. 文本日志按四个级别目录落盘：`error/`、`warn/`、`info/`、`debug/`。
2. **级联写入**：更严重的级别也出现在更宽松的目录里，所以打开 `info/` 能看到当天除 debug 外的完整脉络，`error/` 仍然很短。
3. 每个级别目录的当前文件永远叫 `latest.log`；按大小（5MB）和按天滚动到 `app_YYYY-MM-DD.log`。
4. 查看器的级别下拉改为切目录，默认打开该目录的 `latest.log`。
5. `logs/errors.jsonl` 位置和格式不变。

## 非目标

- 不改任何 `AppLogger.d/i/w/e` 调用方。
- 不改 `ErrorLogService` 的 JSONL 格式、去重、路径。
- 不改控制台输出、ANSI 颜色、log4j 单行格式。
- 不改 ACP frame 日志开关；打开后仍走同一套文件日志，只是按级别进对应目录。
- 不在 `logs/` 根目录再留一份总日志。
- 不迁移已有的 `logs/app_*.log`。
- 不做压缩、远程上报、按模块分子目录。

## 布局

```
{appDataRoot}/logs/
  errors.jsonl                         # ErrorLogService，不动
  error/latest.log
  error/app_YYYY-MM-DD.log             # 已滚动的归档
  error/app_YYYY-MM-DD_<stamp>.log     # 同一天多次滚动
  warn/…
  info/…
  debug/…                              # 仅 kDebugMode；release 不创建、不写入
```

目录名固定为 `error`、`warn`、`info`、`debug`（不是 `warning`）。查看器下拉仍显示 `WARNING`，映射到 `warn/`。

根目录不再新建 `app_*.log`。旧的 `logs/app_*.log` 留在根上，按 7 天规则清掉；查看器不再列出它们。

## 级联写入

一个 `AppLogger`、一个带级别过滤的 `Logger`、一个扇出 `LogOutput`。扇出下面为每个启用的级别目录挂一个现有的 `_FlushingFileOutput`（写该目录的 `latest.log`）。缓冲、异步 flush（200ms）、写失败回调保持现状。

| 一条日志 | 写入的目录 |
|---|---|
| debug | debug |
| info | debug, info |
| warn | debug, info, warn |
| error | debug, info, warn, error |

实现：对每个 sink，若 `event.level >= sink.minLevel` 则写入。Release 没有 debug sink，DEBUG 事件被现有 `_FileLogFilter` 丢掉（与现在一致：debug 构建落盘 DEBUG，release 只落盘 INFO+）。

控制台过滤不变：debug 构建全量，release 只打 warn/error。

init 完成前的记录仍进同一份 pending 列表；init 后按级联刷到各 `latest.log`。

`currentLogFilePath` 指向**完整时间线**目录的 `latest.log`：debug 构建是 `logs/debug/latest.log`，release 是 `logs/info/latest.log`。复制路径、测试、滚动后的当前文件都用这个。

## latest.log 滚动

每个目录独立滚动，当前文件永远是 `latest.log`。

**何时滚**

- 大小：该目录 `latest.log` > 5MB。
- 日期：日历日与打开这份 `latest.log` 时记录的日期不同。启动时若已有 `latest.log` 且 `lastModified` 不是今天，或大小已超 5MB，先归档再新建。

检查频率仍约每 5 秒一次（所有启用中的目录都查），避免每行 stat。

**怎么滚**

1. flush 并关掉该目录当前的 `_FlushingFileOutput`。
2. 把 `latest.log` 改名为 `app_YYYY-MM-DD.log`，日期用**这份 `latest.log` 打开时记下的那一天**（跨日滚动时归档名是昨天，不是今天）。目标已存在则用 `app_YYYY-MM-DD_<milliseconds>.log`。
3. 创建新的空 `latest.log` 并挂上新的 `_FlushingFileOutput`。
4. 把该目录的「打开日期」更新为今天。

日期变化时所有启用中的目录都滚。`errors.jsonl` 不滚。

**失败**

- 任一目录写入触发存储错误 → 整份文件日志停掉（与现在相同：磁盘满时不要只死一个级别）。
- `latest.log` 改名失败 → 继续写当前 `latest.log`，控制台打一条 warn。不丢正在写的日志。

## 保留策略

每个级别目录独立计算：

- 保留当前 `latest.log`（不删）。
- 归档（`app_*.log`）按 `lastModified` 新→旧排序后：超过 7 天的删掉；剩下的只留最新 5 个。
- 根上的 `errors.jsonl` 不删。
- 根上遗留的 `app_*.log` 只按 7 天删，不计入某个级别目录的 5 个配额。

「清除旧日志」走同一套规则。

## 查看器

级别下拉改为切目录，**不再按行过滤级别**（`filterLogLines` 的 `selectedLevel` 对级别不再砍行；搜索、紧凑视图仍有效）。

| 下拉 | 目录 | 何时出现 |
|---|---|---|
| ALL | 完整时间线：debug 构建 `debug/`，release `info/` | 始终 |
| DEBUG | `debug/` | 仅 debug 构建 |
| INFO | `info/` | 始终 |
| WARNING | `warn/` | 始终 |
| ERROR | `error/` | 始终 |

文件下拉只列当前目录的 `.log`：`latest.log` 置顶，其余按修改时间新→旧。打开查看器或切换级别时，默认选中该目录的 `latest.log`。

`errors.jsonl` 不出现在列表里。

`listLogFiles` / `getLogFiles` 增加 `AppLogLevel? level`。每次只列**一个**目录：传入 `error`/`warning`/`info`/`debug` 列对应目录；省略（查看器的 ALL）列完整时间线目录。没有「一次列出四个目录」的 API。

## API 与调用方

对外 `AppLogger.d/i/w/e` 不变。内部替换：

- 单个 `_fileLogOutput` / `_logFile` → 每目录一个 output + 一份 `latest.log` 路径。
- `_logDirPath` 仍为 `{appDataRoot}/logs`。
- `listLogFiles({String? appDataRoot, AppLogLevel? level})`。
- `currentLogFilePath` 语义见上。
- 测试用 `flushFileLogging()` 刷新全部启用中的 output。

`app_error_utils` 把存储错误识别里的 `/logs/app_` 扩成也匹配 `/logs/error/`、`/logs/warn/`、`/logs/info/`、`/logs/debug/`、`/logs/latest.log`，避免把日志 IO 失败误报成要记录的应用错误。

## 文档

- `docs/workspace-storage-layout.md`：顶层补上 `logs/`（含四个级别目录和 `errors.jsonl`）。
- `docs/DEBUGGING.md`：ACP frame 日志写入 `{appDataRoot}/logs/{level}/latest.log`。
- `docs/PERFORMANCE_ANALYSIS.md`：`tail -F` 改为 `logs/info/latest.log`（查 DEBUG 用 `logs/debug/latest.log`）。

## 测试

先改测试再改实现。

`client/test/utils/logging/logger_utils_test.dart`：

- init 后存在 `logs/{error,warn,info}/latest.log`；debug 构建再多 `logs/debug/latest.log`。
- info 只出现在 debug + info 的 `latest.log`，不进 warn/error。
- error 出现在所有已启用目录的 `latest.log`。
- `listLogFiles(level: error)` 只返回 `logs/error/` 下的文件，且 `latest.log` 排第一。
- `currentLogFilePath` 以 `latest.log` 结尾，且位于完整时间线目录。
- 把滚动阈值降到很小（测试注入）：超过后该目录出现 `app_*.log`，之后的写入进新的 `latest.log`。
- 模拟日期变化（测试注入「今天」）：启用中的目录都把当天 `latest.log` 归档。

`client/test/pages/system/log_viewer_test.dart`：

- 选 ERROR 时文件列表来自 `error/`，默认 `latest.log`。
- 切到 INFO 会重新列 `info/` 的文件。
- 列表不含 `errors.jsonl`。
- 切换级别只换目录、不按行藏级别；`error/` 下列出的文件路径都在 `logs/error/` 下。

`client/test/utils/logging/app_error_utils_test.dart`：若现有用例覆盖日志路径识别，补上新路径。

## 主要改动文件

- `client/lib/utils/logging/logger_utils.dart` — 扇出、latest.log、按目录滚动/清理/列举
- `client/lib/pages/system/log_viewer_panel.dart` — 切级别时按目录列文件
- `client/lib/pages/system/log_viewer_filter.dart` — 级别不再按行过滤
- `client/lib/pages/system/log_viewer_toolbar.dart` — release 隐藏 DEBUG
- `client/lib/utils/logging/app_error_utils.dart` — 日志路径识别
- 上述测试与三份文档
