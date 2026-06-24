import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/ssh_profile_cubit.dart';
import '../models/ssh_profile.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/ssh/ssh_profile_connection_tester.dart';
import '../services/terminal/terminal_transport_factory.dart';
import '../widgets/app_dialog.dart';
import 'ssh_profile_setup_page.dart';
import 'ssh_profiles/ssh_profile_form_dialog.dart';
import 'ssh_profiles/ssh_profiles_section.dart';

/// Full-page host for SSH profile management.
class SshProfilesPage extends StatelessWidget {
  const SshProfilesPage({super.key, this.embedded = false});

  /// When true, omits [Scaffold] so the settings shell supplies the app bar.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    const body = SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: SshProfilesSection(),
    );
    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('SSH Profiles')),
      body: body,
    );
  }
}

Future<void> openSshProfileEditor(
  BuildContext context, {
  SshProfile? profile,
}) async {
  if (Platform.isAndroid) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SshProfileSetupPage(
          profileRepository: context.read<SshProfileRepository>(),
          credentialStore: context.read<SshCredentialStore>(),
          initialProfile: profile,
          connectionTester: SshProfileConnectionTester(
            clientFactory: context
                .read<TerminalTransportFactory>()
                .sshClientFactory,
          ),
          onProfileSaved: () {
            context.read<SshProfileCubit>().load();
            Navigator.of(context).maybePop();
          },
        ),
      ),
    );
    return;
  }
  await showSshProfileFormDialog(context, profile: profile);
}

Future<void> confirmDeleteSshProfile(
  BuildContext context,
  SshProfile profile,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppDialogHeader(title: '删除 SSH Profile'),
          const SizedBox(height: 16),
          Text('确定删除 ${profile.name} 吗？保存的凭据也会一并删除。'),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await context.read<SshProfileCubit>().deleteProfile(profile.id);
}
