import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../cubits/app_provider_cubit.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../services/app/platform_utils.dart';
import '../../home_workspace_global_section.dart';
import '../../home_workspace_route.dart';
import '../../../llm_config/llm_config_routes.dart';

/// Closes preset dialogs and opens the provider configuration surface.
void openCliPresetProviderConfig(
  BuildContext context, {
  required CliTool cli,
  int dialogPops = 1,
}) {
  final router = GoRouter.of(context);
  final navigator = Navigator.of(context);
  final usePush = useAndroidHubNavigation(context);
  final homeProviders = HomeGlobalView.providers.homeLocation;
  final path = usePush ? llmCliRoute(cli) : homeProviders;

  for (var i = 0; i < dialogPops; i++) {
    if (!navigator.canPop()) break;
    navigator.pop();
  }

  void finishNavigate(String target) {
    if (usePush) {
      router.push(target);
    } else {
      router.go(target);
    }
    _selectProviderCli(router, cli);
  }

  final current = router.state.uri.toString();
  if (usePush && current == path) {
    _selectProviderCli(router, cli);
    return;
  }

  if (!usePush &&
      HomeWorkspaceRoute.homeGlobalView(current) == HomeGlobalView.providers) {
    // GoRouter ignores identical go() — bounce so re-open always works.
    router.go('/home-v2');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      finishNavigate(homeProviders);
    });
    return;
  }

  finishNavigate(path);
}

void _selectProviderCli(GoRouter router, CliTool cli) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = router.routerDelegate.navigatorKey.currentContext;
    if (ctx == null) return;
    final cubit = ctx.read<AppProviderCubit>();
    if (cubit.state.selectedCli != cli) {
      cubit.setSelectedCli(cli);
    }
  });
}
