import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:xterm/xterm.dart';

import '../cubits/team_cubit.dart';
import '../models/team_config.dart';

class UiWarmup extends StatefulWidget {
  const UiWarmup({required this.child, super.key});

  final Widget child;

  @override
  State<UiWarmup> createState() => _UiWarmupState();
}

class _UiWarmupState extends State<UiWarmup> {
  final Terminal _terminal = Terminal(
    maxLines: 100,
    platform: defaultTargetPlatform == TargetPlatform.macOS
        ? TerminalTargetPlatform.macos
        : TerminalTargetPlatform.linux,
  );

  var _stage = 0;
  var _done = false;
  Timer? _warmupTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmupTimer = Timer(const Duration(milliseconds: 80), _runWarmup);
    });
  }

  Future<void> _runWarmup() async {
    if (!mounted) return;
    setState(() => _stage = 1);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _stage = 2);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() {
      _stage = 0;
      _done = true;
    });
  }

  @override
  void dispose() {
    _warmupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_done && _stage != 0)
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: TickerMode(
                  enabled: false,
                  child: Opacity(
                    opacity: 0,
                    child: _WarmupStage(stage: _stage, terminal: _terminal),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WarmupStage extends StatelessWidget {
  const _WarmupStage({required this.stage, required this.terminal});

  final int stage;
  final Terminal terminal;

  @override
  Widget build(BuildContext context) {
    final team = context.select<TeamCubit, TeamConfig?>(
      (cubit) => cubit.state.selectedTeam,
    );
    if (team == null) return const SizedBox.shrink();

    return SizedBox(
      width: 1200,
      height: 700,
      child: switch (stage) {
        1 => _SettingsWarmup(team: team),
        2 => TerminalView(
          terminal,
          backgroundOpacity: 0.92,
          padding: const EdgeInsets.all(6),
          textStyle: const TerminalStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['monospace'],
          ),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _SettingsWarmup extends StatelessWidget {
  const _SettingsWarmup({required this.team});

  final TeamConfig team;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _WarmupNavTile(title: 'Team', subtitle: 'Settings'),
                  _WarmupNavTile(title: 'Members', subtitle: 'Roles'),
                  _WarmupNavTile(title: 'LLM', subtitle: 'Models'),
                  _WarmupNavTile(title: 'Layout', subtitle: 'Panels'),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView.builder(
                itemCount: team.members.length.clamp(0, 4) + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WarmupHeading(),
                        SizedBox(height: 14),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            _WarmupSizedField(label: 'Team name'),
                            _WarmupSizedField(label: 'Working directory'),
                          ],
                        ),
                        SizedBox(height: 14),
                        TextField(
                          minLines: 2,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Extra arguments',
                            prefixIcon: Icon(Icons.terminal_outlined),
                          ),
                        ),
                        SizedBox(height: 18),
                        Text(
                          'Member launch order',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 10),
                      ],
                    );
                  }
                  final member = team.members[index - 1];
                  return _WarmupLaunchRow(
                    index: index,
                    name: member.name,
                    command: 'flashskyai --member ${member.name}',
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarmupHeading extends StatelessWidget {
  const _WarmupHeading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Team Settings', style: TextStyle(fontWeight: FontWeight.w800)),
        SizedBox(height: 4),
        Text('Edit team defaults and member launch order.'),
      ],
    );
  }
}

class _WarmupSizedField extends StatelessWidget {
  const _WarmupSizedField({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.badge_outlined),
        ),
      ),
    );
  }
}

class _WarmupNavTile extends StatelessWidget {
  const _WarmupNavTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WarmupLaunchRow extends StatelessWidget {
  const _WarmupLaunchRow({
    required this.index,
    required this.name,
    required this.command,
  });

  final int index;
  final String name;
  final String command;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text('$index')),
          Expanded(child: Text(name)),
          const Icon(Icons.open_in_new),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
