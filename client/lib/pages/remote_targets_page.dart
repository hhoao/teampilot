import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/home_connection_cubit.dart';
import '../cubits/ssh_profile_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../repositories/ssh_profile_repository.dart';
import 'ssh_profiles/ssh_profiles_section.dart';

/// Target picker reached from the connection page's 「切换连接」.
///
/// Selecting a target connects it (on Android this switches the SSH home);
/// once the home reports connected this page pops so the app shell can resume.
class RemoteTargetsPage extends StatefulWidget {
  const RemoteTargetsPage({super.key});

  @override
  State<RemoteTargetsPage> createState() => _RemoteTargetsPageState();
}

class _RemoteTargetsPageState extends State<RemoteTargetsPage> {
  /// Optional until the shell wires the provider: absence means "no status".
  HomeConnectionCubit? _tryCubit(BuildContext context) {
    try {
      return context.read<HomeConnectionCubit>();
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      appBar: AppBar(title: Text(context.l10n.home.connectionSwitch)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: BlocBuilder<SshProfileCubit, SshProfileState>(
            builder: (context, state) {
              final cubit = context.read<SshProfileCubit>();
              return SshProfilesSection(
                profiles: state.profiles,
                onRefresh: () => cubit.load(),
                onDelete: cubit.deleteProfile,
                repository: context.read<SshProfileRepository>(),
                profileCubit: cubit,
                showRemoteConfig: false,
              );
            },
          ),
        ),
      ),
    );
    if (_tryCubit(context) == null) return content;
    return BlocListener<HomeConnectionCubit, HomeConnectionState>(
      listenWhen: (previous, next) =>
          previous.status != HomeConnectionStatus.connected &&
          next.status == HomeConnectionStatus.connected,
      listener: (context, _) {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
      },
      child: content,
    );
  }
}
