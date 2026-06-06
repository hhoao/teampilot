import 'package:flutter/foundation.dart';

import 'project_icon_ref.dart';

@immutable
sealed class ProjectIconPickerResult {
  const ProjectIconPickerResult();
}

@immutable
final class ProjectIconPickerCancelled extends ProjectIconPickerResult {
  const ProjectIconPickerCancelled();
}

@immutable
final class ProjectIconPickerUploadRequested extends ProjectIconPickerResult {
  const ProjectIconPickerUploadRequested();
}

@immutable
final class ProjectIconPickerCommitted extends ProjectIconPickerResult {
  const ProjectIconPickerCommitted(this.icon);

  final ProjectIconRef icon;
}
