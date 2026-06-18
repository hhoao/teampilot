import 'package:flutter/foundation.dart';

import 'workspace_icon_ref.dart';

@immutable
sealed class WorkspaceIconPickerResult {
  const WorkspaceIconPickerResult();
}

@immutable
final class WorkspaceIconPickerCancelled extends WorkspaceIconPickerResult {
  const WorkspaceIconPickerCancelled();
}

@immutable
final class WorkspaceIconPickerUploadRequested extends WorkspaceIconPickerResult {
  const WorkspaceIconPickerUploadRequested();
}

@immutable
final class WorkspaceIconPickerCommitted extends WorkspaceIconPickerResult {
  const WorkspaceIconPickerCommitted(this.icon);

  final WorkspaceIconRef icon;
}
