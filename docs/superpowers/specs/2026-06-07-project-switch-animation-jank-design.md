# 项目切换动画卡顿优化 — 设计

- 日期: 2026-06-07
- 分支: feat/workspace-project-isolation
- 状态: 已批准设计,待实现

## 问题

切换项目时用户感知到动画"发涩/卡顿"。经确认:**内容出现得很快,卡顿仅出现在切换动画本身**,与文件 IO、终端重建、session 重新加载无关(切换不读磁盘,终端进程在 `WorkspaceTerminalRegistry` 中保活)。

## 根因

切换项目时,`ChatPage` 的 `childAnimationKey`(基于新 active tab id)变化,触发 `WorkspaceShellFadeSlideIn` 以新 key 重建并播放 280ms 淡入+滑入动画,包裹整棵 `ChatWorkbench` 子树(终端/编辑器/文件树)。

`client/lib/pages/workspace_shell/workspace_shell_layout.dart` 中 `WorkspaceShellFadeSlideIn` 的 builder 每帧返回一个 `Opacity`:

```dart
builder: (context, value, child) {
  final opacity = Curves.easeOut.transform(value);
  return Opacity(
    opacity: opacity,
    child: FractionalTranslation(
      translation: Offset(0.025 * (1 - value), 0),
      child: child,
    ),
  );
},
```

只要 opacity ≠ 1.0(即整个 280ms 全程),`Opacity` 必然 `saveLayer`。代价不在 saveLayer 本身,而在于**每帧把这棵又大又重的子树重新 paint 进离屏层**。这是 Flutter 中"对复杂子树做透明度动画 → 掉帧"的经典反模式。`FractionalTranslation` 是图层级 transform,成本可忽略 —— 卡顿来自 `Opacity` 部分。

## 方案(已选 A:保留动画 + RepaintBoundary)

把传给 `TweenAnimationBuilder` 的 `child` 包一层 `RepaintBoundary`,使子树被一次性栅格化为自己的合成图层并缓存。之后 280ms 内 `Opacity` 仅对该缓存图层应用 alpha(`OpacityLayer` 持有 retained child layer,child 不脏即不重 paint),引擎不再逐帧重绘整棵子树的绘制指令。

### 改动

只动 `client/lib/pages/workspace_shell/workspace_shell_layout.dart` 的 `WorkspaceShellFadeSlideIn` 一个 widget:

```dart
return TweenAnimationBuilder<double>(
  key: key,
  tween: Tween(begin: 0, end: 1),
  duration: const Duration(milliseconds: 280),
  curve: Curves.easeOutCubic,
  child: RepaintBoundary(child: child),   // 唯一改动:缓存子树栅格
  builder: (context, value, child) {
    final opacity = Curves.easeOut.transform(value);
    return Opacity(
      opacity: opacity,
      child: FractionalTranslation(
        translation: Offset(0.025 * (1 - value), 0),
        child: child,
      ),
    );
  },
);
```

### 不变

- 动画观感完全保留:同样的 280ms 淡入 + 轻微右滑。
- 逻辑、状态、路由、终端生命周期零改动。

## 风险与边界

- 若新终端在这 280ms 内正好有大量流式输出,会让 RepaintBoundary 缓存失效、退回重绘 —— 但仍严格优于现状,且切换瞬间新终端通常静止,可接受。
- 纯渲染层优化,不引入新状态或新依赖。

## 验证

- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- `cd client && flutter test --exclude-tags integration`(纯渲染优化,逻辑零改动,应无回归)
- 手动 golden-path(渲染性能无法做有意义的自动化断言,按 AGENTS.md 约定记为手测项):
  - DevTools 开 performance overlay 或 "Highlight repaints",切换项目;
  - 预期:动画期间不再出现整棵 workbench 子树的重绘热区,无掉帧。

## 被否决的备选

- **B 去掉淡入只留滑入**:最彻底地消除 jank 源(删掉 `Opacity`),但损失淡入质感。用户希望保留动画观感,故未选。
- **C 缩短/延后动画**:治标,主要针对首帧构建成本;本场景"内容出现快",首帧非主因,收益不如 A。
