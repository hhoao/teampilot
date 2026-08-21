import 'dart:async';
import 'install_cancel_policy.dart';
import 'install_job_context.dart';
import 'install_job_key.dart';

final class InstallJobSpec<T> {
  const InstallJobSpec({
    required this.key,
    required this.title,
    this.subtitle,
    this.workspaceId,
    required this.cancelPolicy,
    required this.run,
    this.onSucceeded,
    this.onFailed,
    this.historyTitle,
    this.historyMessageFor,
  });

  final InstallJobKey key;
  final String title;
  final String? subtitle;
  final String? workspaceId;
  final InstallCancelPolicy cancelPolicy;
  final Future<T> Function(InstallJobContext ctx) run;
  final FutureOr<void> Function(T result)? onSucceeded;
  final FutureOr<void> Function(Object error)? onFailed;
  final String? historyTitle;
  final String? Function(T result)? historyMessageFor;
}
