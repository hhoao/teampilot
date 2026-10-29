# Token 用量表与时间范围选择器设计

日期：2026-10-29
状态：已确认

## 背景

Token 用量页（`client/lib/pages/usage/`）当前有三处限制：

1. 明细表是手写 `Row` 布局，只能固定列、不能排序、不能换列序、不能隐藏列。
2. 时间范围只有 `今天 / 近7天 / 近30天 / 全部` 四个 `ChoiceChip`，没有 24 小时、14 天和自定义起止时间。
3. 顶部筛选把时间、CLI、分组混在一排 Chip 里；CLI 显示文字，表格附近没有分组入口。

本次改造目标：

- 在 `shared_ui` 新增可复用的 `TpDataTable`，替换用量明细表。
- 表格支持点击列头排序、列头拖拽换位、列显示/隐藏、固定首列、工具栏插槽。
- 顶部只保留时间范围触发器和 CLI 图标按钮（tooltip 显示名称）；分组按钮移到表格头部。
- 时间选择改为 cc-switch 风格的“预设 + 开始/结束日期时间 + 日历 + 跟随当前时刻”，复用 TP 的日历与时间输入组件。
- 列顺序和显示状态按表 ID 持久化。

参考实现：

- cc-switch 的 `UsageDateRangePicker.tsx`、`RequestLogColumnsMenu.tsx`、`usageTable.ts`（交互与视觉）。
- PlutoGrid / DataTable2 的列模型、宽度策略、固定列与横向滚动做法（只借鉴设计，不引入依赖）。

## 非目标

- 不引入第三方表格包。
- 不改动其他页面的表格。
- 不做列宽拖拽调整（本次只做列顺序拖拽）。
- 不做多列排序。
- 不改趋势图、热力图、成本卡和摘要卡的数据口径。
- 不做 provider/model 级联筛选（cc-switch 有，本次不搬）。

## 关键决策

| 决策 | 结果 |
|------|------|
| 表组件层级 | `shared_ui` 新增 `TpDataTable`，用量页接入 |
| 列偏好持久化 | `AppSettingsRepository` 的 `tableStates`，按表 ID 存 |
| 首列 | 锁定：固定左侧、不可隐藏、不可拖拽 |
| 拖拽触发 | 表头悬停显示拖拽柄，拖拽柄换位；点击列名只排序 |
| 时间范围 | `当天 / 近24小时 / 近7天 / 近14天 / 近30天 / 全部` + 自定义 |
| 自定义上限 | 30 天 |
| 跟随当前时刻 | 支持；面板内每秒刷新，应用后每分钟重算 |
| 表格视觉 | 表头浅底、行高 40、首尾 16px、列间距 24px、所有列左对齐、等宽数字 |
| 排序 | 单列；默认总 Token 降序；点击切换降序/升序，再点回到默认 |
| 窄屏 | 时间选择器改对话框；工具条换行；表格横向滚动 |
| 列状态存储内容 | 只存改过的顺序和隐藏项；排序不持久化 |

## 1. `TpDataTable`

目录：`client/packages/shared_ui/lib/src/components/table/`

### 1.1 列模型

```dart
class TpTableColumn<T> {
  const TpTableColumn({
    required this.id,
    required this.label,
    required this.cellBuilder,
    this.width,
    this.flex = 1,
    this.minWidth = 80,
    this.alignment = Alignment.centerLeft,
    this.sortValue,
    this.hideable = true,
    this.locked = false,
    this.draggable = true,
    this.groupStart = false,
  });

  final String id;
  final String label;
  final Widget Function(BuildContext context, T row) cellBuilder;
  final double? width;
  final int flex;
  final double minWidth;
  final Alignment alignment;
  final Comparable? Function(T row)? sortValue;
  final bool hideable;
  final bool locked;
  final bool draggable;
  final bool groupStart;
}
```

约束：

- `locked` 列必须排在默认顺序第一位；组件只支持一个锁定列。
- `sortValue == null` 表示该列不可排序。
- `hideable == false` 的列不出现在列设置菜单。
- `groupStart` 只影响表头/表体单元格的前置间距，不参与业务分组。

### 1.2 状态模型

```dart
class TpTableSort {
  const TpTableSort({required this.columnId, required this.ascending});
  final String columnId;
  final bool ascending;
}

class TpTableState {
  const TpTableState({
    this.order = const [],
    this.hidden = const {},
    this.sort,
  });

  final List<String> order;
  final Set<String> hidden;
  final TpTableSort? sort;

  TpTableState copyWith({
    List<String>? order,
    Set<String>? hidden,
    TpTableSort? sort,
    bool clearSort = false,
  });

  Map<String, dynamic> toJson();
  factory TpTableState.fromJson(Map<String, dynamic> json);
}
```

解析规则：

- 未知列 ID 忽略。
- `order` 中缺失的列（后续版本新增）按默认顺序插入到下一个已知列之前；没有下一个已知列时追加到末尾。
- `hidden` 只保存覆盖默认值的项；恢复默认即清空。
- 坏 JSON / 类型不匹配时返回默认状态，不抛异常。

### 1.3 组件

```dart
class TpDataTable<T> extends StatefulWidget {
  const TpDataTable({
    required this.columns,
    required this.rows,
    required this.rowKey,
    required this.state,
    required this.onStateChanged,
    this.toolbar,
    this.footer,
    this.emptyState,
    this.rowHeight = 40,
    this.headerHeight = 36,
    this.minTableWidth = 720,
    this.labels = const TpDataTableLabels(),
    super.key,
  });
}
```

`TpDataTable` 是**受控组件**：列顺序、隐藏项、排序状态都由调用方通过 `state` 传入；表头点击、列设置、拖拽只回调新的 `TpTableState`，不自己改内部状态。这样分页、持久化和表格渲染共用同一份状态，不会出现“表内排序了但分页没排序”的问题。

`TpDataTableLabels` 提供列设置菜单和排序提示文案，默认英文；`shared_ui` 不依赖 app l10n。

### 1.4 布局与滚动

- 外层：`Column(toolbar, divider, table, footer)`。
- 表头 + 表体放在同一个 `LayoutBuilder` 里。
- 列宽计算顺序：
  1. 固定宽列取 `width`；
  2. 剩余宽度按 `flex` 分配；
  3. 每列不低于 `minWidth`；
  4. 总宽小于 `minTableWidth` 时取 `minTableWidth`，触发横向滚动。
- 锁定列单独放在左侧，不参与横向滚动；滚动区只包含其余列。
- 行高固定 `rowHeight`，表头固定 `headerHeight`，固定列和滚动区行高天然对齐。
- 行悬停状态由 `TpDataTable` 统一记录，固定列和滚动区同时应用背景色。
- 横向滚动使用 `Scrollbar` + `SingleChildScrollView`，滚动条只在溢出时显示。

### 1.5 排序

- 列头点击只计算下一个 `TpTableSort` 并回调 `onStateChanged`：
  - 当前不是排序列 → 按该列降序。
  - 当前是降序 → 升序。
  - 当前是升序 → `sort = null`（回到调用方默认顺序）。
- 排序由调用方执行：调用方根据 `sortValue` 排序后再分页，把当前页 `rows` 传给 `TpDataTable`。
- 排序稳定：相同 `sortValue` 保持原始顺序。
- 排序列头显示 `arrow_downward` / `arrow_upward`；不可排序列头不显示箭头。
- `TpDataTable` 只负责渲染箭头和回调，不直接改 `rows` 顺序。

### 1.6 列拖拽

- 每个可拖拽列头右侧在 hover 时显示 `Icons.drag_indicator`。
- 拖拽柄使用 `Draggable<String>` + `DragTarget<String>`，拖动时显示浮层列头。
- 目标位置显示 2px 主色插入线；松开后调用 `onStateChanged` 更新 `order`。
- 锁定列不渲染拖拽柄，也不接受 drop。
- 列拖拽不触发排序；列名区域只处理 tap。

### 1.7 列显示/隐藏

- `TpDataTable` 提供独立的 `TpTableColumnMenu` 组件，调用方放进 `toolbar`。
- `TpTableColumnMenu(columns, state, onChanged, labels)`：
  - 菜单项：所有 `hideable` 列 + 分隔线 + “恢复默认”。
  - 勾选即时回调新的 `TpTableState`。
- 至少保留一个非锁定可见列；尝试隐藏最后一列时禁用该项。

### 1.8 样式

- 表头：`surfaceContainerHighest` 或 `workspaceInset` 浅底，12px `onSurface` 56% 文字。
- 表体：行高 40，`border-bottom` 使用 `outlineVariant` 35%。
- 首尾单元格 16px 内边距，列间 24px；`groupStart` 列前置 40px。
- 数字列使用 `FontFeature.tabularFigures()`。
- 悬停行背景 `surfaceContainerHighest` 40%。
- 空状态占满表体最小高度 160。

## 2. `TpDateTimeRangePicker`

目录：`client/packages/shared_ui/lib/src/components/date_range/`

### 2.1 模型

```dart
class TpDateTimeRange {
  const TpDateTimeRange({
    required this.start,
    required this.end,
    this.liveEnd = false,
  });

  final DateTime start;
  final DateTime end;
  final bool liveEnd;
}

class TpDateTimeRangePreset {
  const TpDateTimeRangePreset({required this.id, required this.label});
  final String id;
  final String label;
}

class TpDateTimeRangePickerLabels {
  const TpDateTimeRangePickerLabels({
    this.start = 'Start time',
    this.end = 'End time',
    this.confirm = 'Confirm',
    this.cancel = 'Cancel',
    this.hint = 'Date and time, up to 30 days',
    this.liveEnd = 'End time follows now',
    this.invalidOrder = 'Start time cannot be later than end time',
    this.tooLong = 'Range cannot exceed 30 days',
  });
}
```

### 2.2 组件

```dart
class TpDateTimeRangePicker extends StatefulWidget {
  const TpDateTimeRangePicker({
    required this.firstDate,
    required this.lastDate,
    required this.triggerBuilder,
    required this.labels,
    this.value,
    this.onChanged,
    this.maxDuration,
    this.presets = const [],
    this.selectedPresetId,
    this.onPresetSelected,
    this.panelWidth = 620,
    this.controller,
    super.key,
  });

  final ValueChanged<TpDateTimeRange?>? onChanged;
  final ValueChanged<String>? onPresetSelected;
  final TpPopoverController? controller;
}
```

- `maxDuration` 为 null 表示不限制；用量页传 30 天。
- `presets` 为空时不渲染预设行。
- `selectedPresetId` 只用于高亮当前预设。
- `onPresetSelected` 调用后组件自行关闭；父组件负责应用预设。
- `triggerBuilder(context, isOpen)` 与现有 `TpDatePicker` / `TpDateRangePicker` 保持一致。

### 2.3 打开方式

- `LayoutBuilder` 宽度 >= 720：`TpPopover`，`panelWidth` 默认 620，最大不超过屏幕宽 - 32。
- 宽度 < 720：`showTpDialog`，内容与 popover 相同，适配滚动。
- 打开时把 `value` 拷贝到草稿；关闭不保存草稿。

### 2.4 面板内容

```text
┌──────────────────────────────────────────────────────────┐
│ [当天] [近24小时] [近7天] [近14天] [近30天] [全部]        │
├────────────────────────────┬─────────────────────────────┤
│ 支持日期与时间，最长 30 天  │  ‹       2026年9月       ›  │
│                            │  日 一 二 三 四 五 六        │
│ ┌ 开始时间 ──────────────┐ │   ... 日历 ...               │
│ │ 2026/09/29   22 : 38   │ │                             │
│ └────────────────────────┘ │                             │
│ ┌ 结束时间 ──────────────┐ │                             │
│ │ 2026/10/29   22 : 38   │ │                             │
│ └────────────────────────┘ │                             │
│ ☐ 结束时间跟随当前时刻     │                             │
│ [取消]           [确定]    │                             │
└────────────────────────────┴─────────────────────────────┘
```

- 左侧字段卡：点击选中“当前编辑端”，边框使用主色 + 1px ring。
- 日期显示为 `yyyy/MM/dd`；时间用 `TpTimePicker`（小时/分钟）。
- 右侧使用 `TpCalendar` 单日选择，`selected` 为当前编辑端的日期。
- 选择日期时保留该端原来的时间；`开始 > 结束` 时把结束日期推到开始日期。
- 选完开始日期自动切到结束端；结束端选中早于开始端的日期时，把该日期当作新的开始端。
- 勾选“跟随当前时刻”：
  - 结束端字段禁用并显示为 50% 透明度；
  - 面板内启动 1 秒 `Timer.periodic`，刷新草稿结束时间；
  - 取消勾选时保留当前草稿时间，恢复可编辑。
- 预设按钮点击后立即回调 `onPresetSelected` 并关闭面板，不再执行“确定”。

### 2.5 校验

- 开始时间晚于结束时间：字段下方显示 `labels.invalidOrder`，不关闭。
- `maxDuration != null` 且跨度超过上限：显示 `labels.tooLong`，不关闭。
- 校验通过后调用 `onChanged(TpDateTimeRange(...))` 并关闭。

## 3. 用量页接线

### 3.1 顶部筛选条

新文件 `pages/usage/widgets/usage_filter_bar.dart`：

- 左侧：`UsageDateRangePicker`（包装 `TpDateTimeRangePicker`）。
- 竖分隔线。
- `全部` 文字按钮。
- `CliTool.values` 图标按钮：`CliBrandIcon(cli, size: 20, showBorder: false)` 放在 28×28 的按钮里，tooltip 用 `usageCliLabel(cli)`；选中项 `surfaceContainerHighest` 背景。
- 移除原 `UsageToolbar` 里的时间 Chip、CLI 文字 Chip、分组 Chip。

### 3.2 时间范围包装

新文件 `pages/usage/widgets/usage_date_range_picker.dart`：

- 预设定义：

```dart
const usageRangePresets = <UsageRange>[
  UsageRange.today,
  UsageRange.last24Hours,
  UsageRange.sevenDays,
  UsageRange.fourteenDays,
  UsageRange.thirtyDays,
  UsageRange.all,
];
```

- 预设文案来自 l10n。
- `value`：预设时用当前范围解析出的起止；`custom` 时用 state 里的 custom 值。
- 打开面板时的草稿回退：
  - `all`：起点取 `now - 30 天`，终点取 `now`，避免日历跳到 1970。
  - `today`：起点取本地零点，终点取 `now`。
  - 其余预设：起点按 `usageRangeBounds` 计算，终点取 `now`。
- `onPresetSelected`：`UsageRange.tryParse(id)`，非空时 `cubit.setRange(...)`。
- `onChanged`：`cubit.setCustomRange(startMs, endMs, liveEnd: value.liveEnd)`。
- 触发器文案：预设用对应 l10n；自定义用 `MM/dd HH:mm – MM/dd HH:mm`，超长省略。

### 3.3 表格工具条

新文件 `pages/usage/widgets/usage_table_toolbar.dart`：

- 左侧：
  - `N 组 · 按 X 分组`（现有 l10n 文案）。
  - `TpSegmentedControl`（outlined，height 28）显示会话/成员/模型/CLI；窄屏包一层横向 `SingleChildScrollView`。
- 右侧：
  - 搜索框：现有 `AppKeys.sessionUsageSearchField`，宽 240，窄屏占满一行。
  - 列设置：`TpIconButton(icon: Icons.view_column_outlined, tooltip: l10n.sessionUsageColumnSettings)` 打开 `TpTableColumnMenu`。
- 布局：`LayoutBuilder` + `Wrap`；宽屏一行，窄屏分组/搜索分两行。

### 3.4 表格列定义

新文件 `pages/usage/widgets/usage_table_columns.dart`：

| id | 标题 | 宽度 | 可排序 | 默认可见 |
|----|------|------|--------|----------|
| `group` | 当前分组名 | flex 3 | 是（按 label） | 是，locked |
| `total` | 总 Token | 100 | 是 | 是 |
| `input` | 输入 | 90 | 是 | 是 |
| `output` | 输出 | 90 | 是 | 是 |
| `cache` | 缓存 | 100 | 是 | 是 |
| `cost` | 成本 | 110 | 是 | 是 |
| `requests` | 请求 | 80 | 是 | 是 |
| `sessions` | 会话数 | 90 | 是 | 是 |
| `share` | 占比 | 120 | 是 | 是 |

- 默认排序：`total` 降序。
- `group` 列 `locked: true, hideable: false, draggable: false`。
- `share` 列 cell 保持百分比 + 4px 进度条。
- `cost` 列保持未定价 `*`。
- CLI badges 仍放在 `group` 列副标题里。

### 3.5 分页

从 `usage_detail_table.dart` 抽出 `usage_table_pagination.dart`，保持现有：

- `AppKeys.sessionUsagePageRange`
- `AppKeys.sessionUsagePageSize`
- `AppKeys.sessionUsagePrevPage`
- `AppKeys.sessionUsageNextPage`
- 10/20/50/100 每页条数

`usage_detail_table.dart` 持有当前的 `TpTableState`：

- 状态变化时先按 `state.sort` 对全量 `dashboard.rows` 排序（相同值保持原顺序），再按当前页切片。
- 把当前页数据传给 `TpDataTable`，把分页栏传给 `footer`。
- 列顺序、隐藏项变化时保存；排序变化只更新 UI，不持久化。

分页在排序后执行。

## 4. 数据模型与聚合

### 4.1 `UsageRange`

```dart
enum UsageRange {
  today('today'),
  last24Hours('last24Hours'),
  sevenDays('sevenDays'),
  fourteenDays('fourteenDays'),
  thirtyDays('thirtyDays'),
  all('all'),
  custom('custom');

  const UsageRange(this.value);
  final String value;

  static UsageRange? tryParse(String? value);
}
```

字符串值用于预设 ID 持久化/回调，避免用 `index`。

### 4.2 `UsageFilter` / `SessionUsageState`

新增字段：

```dart
final int? customStartMs;
final int? customEndMs;
final bool liveEnd;
```

`copyWith` 需要支持清空 custom 字段（`clearCustomRange`）。

### 4.3 聚合边界

```dart
({int? startMs, int? endMs}) usageRangeBounds({
  required UsageRange range,
  required int nowMs,
  int? customStartMs,
  int? customEndMs,
  bool liveEnd = false,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs).toLocal();
  final today = DateTime(now.year, now.month, now.day);
  return switch (range) {
    UsageRange.today => (startMs: today.millisecondsSinceEpoch, endMs: null),
    UsageRange.last24Hours => (
      startMs: nowMs - const Duration(hours: 24).inMilliseconds,
      endMs: null,
    ),
    UsageRange.sevenDays => (
      startMs: today.subtract(const Duration(days: 6)).millisecondsSinceEpoch,
      endMs: null,
    ),
    UsageRange.fourteenDays => (
      startMs: today.subtract(const Duration(days: 13)).millisecondsSinceEpoch,
      endMs: null,
    ),
    UsageRange.thirtyDays => (
      startMs: today.subtract(const Duration(days: 29)).millisecondsSinceEpoch,
      endMs: null,
    ),
    UsageRange.all => (startMs: null, endMs: null),
    UsageRange.custom => (
      startMs: customStartMs,
      endMs: liveEnd ? nowMs : customEndMs,
    ),
  };
}
```

`custom` 且 `customStartMs` 或 `customEndMs` 缺失时按 `all` 处理（两个边界都为 null），避免脏状态把表格过滤成空。

`buildUsageDashboard` 的过滤条件：

```dart
if (bounds.startMs != null && event.timestampMs < bounds.startMs!) return false;
if (bounds.endMs != null && event.timestampMs > bounds.endMs!) return false;
```

`liveEnd` 为 true 时，`endMs` 每次 `buildUsageDashboard` 都取 `nowMs`。

### 4.4 Cubit

```dart
void setRange(UsageRange range) {
  _updateFilter(range: range, clearCustomRange: true, liveEnd: false);
}

void setCustomRange({
  required int startMs,
  required int endMs,
  bool liveEnd = false,
}) {
  _updateFilter(
    range: UsageRange.custom,
    customStartMs: startMs,
    customEndMs: endMs,
    liveEnd: liveEnd,
  );
}

void setLiveEnd(bool value) {
  _updateFilter(liveEnd: value);
}

void refreshRangeNow() {
  if (!state.liveEnd) return;
  emit(state.copyWith(dashboard: _computeDashboard()));
}
```

页面在 `liveEnd == true` 时启动 1 分钟定时器调用 `refreshRangeNow`；`false` 时取消。测试注入 `now` 以保证确定性。

## 5. 持久化

### 5.1 `AppSettingsRepository`

新增：

```dart
Future<Map<String, dynamic>?> loadTableState(String tableId);
Future<void> saveTableState(String tableId, Map<String, dynamic> state);
```

`SharedPrefsAppSettingsRepository`：

- 存储 key：`teampilot.app_settings.v1` 下的 `tableStates`。
- 读取时校验 `Map`、`tableId` 为 `String`，失败返回 `null`。
- 保存时只写该 `tableId` 的子 map，保留其他表的状态。
- `InMemoryAppSettingsRepository` 同步实现，便于测试。

### 5.2 用量表接入

`UsageDetailTable`：

- 表 ID 常量 `usage.detail`。
- `initState` 读取 `context.read<AppSettingsRepository?>()?.loadTableState(...)`。
- 读取完成前用默认状态渲染，完成后 `setState`。
- `onStateChanged` 立即保存；保存前执行 `state.copyWith(clearSort: true)`，排序不持久化；保存失败只记 `AppLogger.w`，不影响 UI。
- 仓库为 null（测试/Embedded 场景）时全部使用默认状态。

## 6. l10n

只编辑：

- `client/lib/l10n/app_en.arb`
- `client/lib/l10n/app_zh.arb`

新增 key：

| key | en | zh |
|-----|----|----|
| `sessionUsageRangeLast24Hours` | Last 24 hours | 近 24 小时 |
| `sessionUsageRangeFourteenDays` | Last 14 days | 近 14 天 |
| `sessionUsageStartTime` | Start time | 开始时间 |
| `sessionUsageEndTime` | End time | 结束时间 |
| `sessionUsageLiveEnd` | End time follows now | 结束时间跟随当前时刻 |
| `sessionUsageRangeHint` | Date and time, up to 30 days | 支持日期与时间，最长 30 天 |
| `sessionUsageRangeInvalidOrder` | Start time cannot be later than end time | 开始时间不能晚于结束时间 |
| `sessionUsageRangeTooLong` | Range cannot exceed 30 days | 时间范围不能超过 30 天 |
| `sessionUsageColumnSettings` | Columns | 显示的列 |
| `sessionUsageColumnReset` | Reset to default | 恢复默认 |
| `sessionUsageSortDescending` | Sort descending | 降序 |
| `sessionUsageSortAscending` | Sort ascending | 升序 |

`shared_ui` 组件文案通过 `TpDateTimeRangePickerLabels` / `TpDataTableLabels` 注入，不直接读 l10n。

## 7. 文件改动

### 新增

```text
client/packages/shared_ui/lib/src/components/table/tp_table_column.dart
client/packages/shared_ui/lib/src/components/table/tp_table_state.dart
client/packages/shared_ui/lib/src/components/table/tp_table_column_menu.dart
client/packages/shared_ui/lib/src/components/table/tp_data_table.dart
client/packages/shared_ui/lib/src/components/table/tp_data_table_header.dart
client/packages/shared_ui/lib/src/components/table/tp_data_table_body.dart
client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range.dart
client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range_picker.dart
client/packages/shared_ui/lib/src/components/date_range/tp_date_time_range_panel.dart
client/lib/pages/usage/widgets/usage_filter_bar.dart
client/lib/pages/usage/widgets/usage_date_range_picker.dart
client/lib/pages/usage/widgets/usage_table_columns.dart
client/lib/pages/usage/widgets/usage_table_toolbar.dart
client/lib/pages/usage/widgets/usage_table_pagination.dart
```

### 修改

```text
client/lib/pages/usage/session_usage_page.dart
client/lib/pages/usage/widgets/usage_page_chrome.dart        // 移除 UsageToolbar
client/lib/pages/usage/widgets/usage_detail_table.dart       // 重写为 TpDataTable 接线
client/lib/models/session_usage_dashboard.dart
client/lib/services/usage/usage_aggregator.dart
client/lib/cubits/session_usage_cubit.dart
client/lib/repositories/app_settings_repository.dart
client/lib/l10n/app_en.arb
client/lib/l10n/app_zh.arb
client/packages/shared_ui/lib/shared_ui.dart                 // 导出新组件
```

### 删除

无。`usage_detail_table.dart` 保留原路径重写，避免无谓的文件删除/新增。

## 8. 测试计划

### shared_ui

`test/components/table/tp_data_table_test.dart`

- 渲染列头和行。
- 点击列头排序：降序 → 升序 → 默认。
- 隐藏列后表头/表体都不再出现；恢复默认恢复。
- 拖拽柄换位后列顺序变化，`onStateChanged` 收到新顺序。
- 锁定列无拖拽柄、不可隐藏。
- 空状态显示 `emptyState`。
- `TpTableState.toJson/fromJson` 往返；未知 id 和坏 JSON 回退。

`test/components/date_range/tp_date_time_range_picker_test.dart`

- 点击预设回调 `onPresetSelected` 并关闭。
- 编辑开始/结束日期和时间，确认后 `onChanged` 值正确。
- 同日范围（开始 10:00，结束 12:00）合法。
- 开始晚于结束显示错误且不关闭。
- 超过 30 天显示错误。
- 勾选跟随当前时刻后结束字段禁用、草稿每秒刷新。
- 窄屏下打开对话框。

### client

`test/services/usage/usage_aggregator_test.dart`

- `last24Hours`、`fourteenDays`、`custom` 的边界。
- `custom + liveEnd` 结束取 `nowMs`。
- 现有 `today/sevenDays/thirtyDays/all` 断言保持。

`test/cubits/session_usage_cubit_test.dart`

- `setRange` 清空 custom 字段。
- `setCustomRange` 后 `dashboard` 按新边界计算。
- `setLiveEnd` / `refreshRangeNow`。
- `resetFilters` 回到 `all`。

`test/pages/usage/session_usage_page_test.dart`

- 顶部显示时间触发器、`全部`、CLI 图标按钮；CLI 名称通过 tooltip 可见。
- 分组按钮在表格卡片内，点击后 `cubit.state.groupBy` 变化。
- 列设置隐藏“占比”后表头不再出现。
- 点击“总 Token”列头后行顺序变化。
- 现有空状态、同步、自动同步、分页、窄屏测试保持通过。

`test/repositories/app_settings_repository_test.dart`

- `saveTableState` / `loadTableState` 往返。
- 两个表 ID 互不覆盖。
- 损坏 JSON 返回 null。

### 验证

```bash
cd client
flutter gen-l10n
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart
```

## 9. 风险与处理

| 风险 | 处理 |
|------|------|
| 固定列 + 横向滚动 + 行悬停同步 | 固定列和滚动区共用 `_hoveredRow` 状态，行高固定 |
| 拖拽与排序点击冲突 | 只有拖拽柄启动 drag，列名区域只处理 tap |
| 列配置被旧版本冻住 | 只存改过的顺序/隐藏项；新增列自动插入 |
| 自定义范围与 30 天上限 | 聚合层只过滤，不裁剪；校验在 picker 内完成 |
| liveEnd 频繁重算 | 面板内 1 秒只更新草稿；页面 1 分钟重算一次 |
| 窄屏 popover 溢出 | <720 改用 `showTpDialog` |
| 持久化读取阻塞首帧 | 默认状态先渲染，异步读取后更新 |
| `session_usage_page.dart` 超 500 行 | 筛选条、表格、工具条、分页全部拆文件 |

## 10. 验收标准

- 用量页表格可排序、可拖拽换列序、可隐藏/恢复列，刷新/重启后列顺序和显示状态保留。
- 首列始终固定左侧，不可隐藏、不可拖拽。
- 顶部只显示时间范围触发器和 CLI 图标按钮；CLI 名称通过 tooltip 可见。
- 分组按钮位于表格头部，切换分组后表格和“N 组”文案同步更新。
- 时间选择器支持 6 个预设和自定义起止日期时间，支持“结束时间跟随当前时刻”，最长 30 天。
- 宽屏 popover、窄屏对话框；表格窄屏横向滚动且首列固定。
- `flutter analyze` 无新增问题，相关测试和全量测试通过。
