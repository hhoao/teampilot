# Onboarding CLI Row Narrow Layout + TpBreakpoints

## Problem

引导「检测 CLI 工具」页的 `OnboardingCliRow` 用单行排布：图标 + 固定宽名称 + 状态图标 + 路径输入框 + 安装按钮。窄屏上输入框被挤到几乎不可见。

同时，项目内断点数字散落（840 shell、768 包默认、720/820 compact、本地魔法数），缺少与前端一致的命名刻度。

## Decisions

### 1. `TpBreakpoints` in `shared_ui`（Tailwind-aligned）

| Token | px | Mobile first `up` | Desktop first `down` | Only band |
|-------|-----|-------------------|----------------------|-----------|
| `sm` | 640 | `width >= 640` | `width < 640` | `[640, 768)` |
| `md` | 768 | `width >= 768` | `width < 768` | `[768, 1024)` |
| `lg` | 1024 | `width >= 1024` | `width < 1024` | `[1024, 1280)` |
| `xl` | 1280 | `width >= 1280` | `width < 1280` | `[1280, 1536)` |
| `xxl` (`2xl`) | 1536 | `width >= 1536` | `width < 1536` | `width >= 1536` |

边界按 Tailwind / CSS `min-width` 惯例：`up` 用 `>=`，`down` 用 `<`，`only` 半开区间，避免刚好落在刻度时双边命中。

API（示意）：

```dart
enum TpBreakpoint { sm, md, lg, xl, xxl }

abstract final class TpBreakpoints {
  static const double sm = 640;
  static const double md = 768;
  static const double lg = 1024;
  static const double xl = 1280;
  static const double xxl = 1536;

  static double of(TpBreakpoint b);
  static bool up(double width, TpBreakpoint b);   // mobile first
  static bool down(double width, TpBreakpoint b); // desktop first (<token)
  static bool only(double width, TpBreakpoint b); // @token band
}
```

可选：`TpBreakpointBuilder`（薄封装 `LayoutBuilder`）。本需求 CLI row 可直接用 `LayoutBuilder` + `down`。

**不做：** CSS 风格「按 variant 切换 child」的完整工具类组件（以后需要再加）。

### 2. Shell 840 保持独立

`WorkspacePanePolicy.narrowBreakpointWidth = 840` 是 shell / 抽屉 / 对话框产品断点，**不并入** Tailwind 刻度，本次不改。内容密度用 `TpBreakpoints`；壳层继续用 840。

### 3. CLI row 布局

- **`TpBreakpoints.down(width, TpBreakpoint.sm)`（`<sm`）：**
  - 第一行：图标 + 名称（取消固定 110 宽）+ 状态图标
  - 第二行：路径 `TextField`（`Expanded`）+（可选）安装按钮
- **否则：** 保持现有单行

## Scope

| 做 | 不做 |
|----|------|
| `shared_ui`：`TpBreakpoints` + 单测 + README 短节 | 迁移既有 720/820/840 调用方 |
| `OnboardingCliRow` 窄/宽布局 | `CliExecutablePathSettingsRow` |
| 窄/宽 widget 测试 | 改 `cli_step` 业务逻辑 |

## Files

- `client/packages/shared_ui/lib/src/theme/tokens/tp_breakpoints.dart`（新建）
- `client/packages/shared_ui/lib/shared_ui.dart`（export）
- `client/packages/shared_ui/test/.../tp_breakpoints_test.dart`（新建）
- `client/packages/shared_ui/README.md`（短节）
- `client/lib/pages/onboarding/steps/onboarding_cli_row.dart`
- `client/test/pages/onboarding/...`（窄/宽布局测）

## Testing

- `TpBreakpoints`：边界值（639/640/767/768/…）覆盖 `up` / `down` / `only`
- CLI row：宽 viewport（如 800）单行；窄（如 390）双行且输入框可用宽度明显大于挤扁态
