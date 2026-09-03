import 'package:flutter/material.dart';

import '../../../models/floating_workspace_tab.dart';
import '../../../models/git_compare.dart';
import '../floating_surface.dart';

/// 浮动面板中的 Git Compare 页。payload 通常是 [GitCompareSpec.tabId]
/// 字符串（浮动面板只持久化 id，见 `resolveFloatingTabForId`），也可以直接
/// 是一个 [GitCompareSpec]（opener 直传场景）；两种情况 [createTab] 都能还原
/// 出同一个 spec。允许每仓库开多个对比标签（allowMultipleTabs）。
class GitCompareFloatingSurface extends FloatingSurface {
  GitCompareFloatingSurface();

  static const String surfaceId = 'gitCompare';

  @override
  String get id => surfaceId;

  @override
  FloatingEmptyAction? get emptyAction => null;

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final spec = _resolveSpec(payload);
    return FloatingTab(
      id: spec?.tabId ?? '$surfaceId:',
      surfaceId: surfaceId,
      title: spec?.tabTitle() ?? 'Compare',
      payload: spec,
    );
  }

  static GitCompareSpec? _resolveSpec(Object? payload) {
    if (payload is GitCompareSpec) return payload;
    if (payload is String) return GitCompareSpec.tryParseTabId(payload);
    return null;
  }

  @override
  Widget build(BuildContext context, FloatingTab tab) {
    final spec = tab.payload;
    if (spec is! GitCompareSpec) return const SizedBox.shrink();
    // TODO(task-7/8): swap for GitComparePane + BlocProvider<GitCompareCubit>.
    return Center(child: Text(spec.tabTitle()));
  }

  @override
  Future<void> activate(FloatingTab tab) async {}
}
