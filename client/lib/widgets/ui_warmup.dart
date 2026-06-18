import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_text_styles.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/session_preferences_cubit.dart';
import '../cubits/team_cubit.dart';
import '../models/team_config.dart';
import 'warmup_glyphs.g.dart';

class UiWarmup extends StatefulWidget {
  const UiWarmup({required this.child, super.key});

  final Widget child;

  @override
  State<UiWarmup> createState() => _UiWarmupState();
}

class _UiWarmupState extends State<UiWarmup> {
  final TerminalEngine _engine = TerminalEngine(
    config: TerminalConfig.defaults().copyWith(
      scrolling: TerminalConfig.defaults().scrolling.copyWith(history: 100),
    ),
  );
  final TerminalController _controller = TerminalController();

  var _stage = 0;
  var _done = false;
  Timer? _warmupTimer;

  @override
  void initState() {
    super.initState();
    _controller.attach(_engine);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmupTimer = Timer(const Duration(milliseconds: 80), _runWarmup);
    });
  }

  Future<void> _runWarmup() async {
    if (!mounted) return;
    // Widget tests stub HTTP and often lack bundled Noto weights; skip font IO.
    final inTest = () {
      try {
        return Platform.environment.containsKey('FLUTTER_TEST');
      } on Object {
        return false;
      }
    }();
    if (!inTest) {
      try {
        await GoogleFonts.pendingFonts([
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w500),
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w600),
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w700),
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w800),
        ]);
      } on Object {
        // Missing bundled weights: see tool/sync_bundled_google_fonts.dart.
      }
      if (!mounted) return;
      try {
        _warmGlyphs();
      } on Object {
        // Font assets may be absent in dev trees without sync.
      }
    }
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

  /// Shapes every glyph the UI can render (from the l10n bundles) across the
  /// bundled Noto Sans SC weights, so the engine builds its HarfBuzz faces and
  /// glyph-layout cache here at startup instead of on the first project tab
  /// click. No [maxLines] — the whole set must wrap and shape, not truncate.
  void _warmGlyphs() {
    // Use the theme's already-resolved styles, NOT copyWith(fontWeight) on one
    // base: GoogleFonts registers each weight as a distinct fontFamily/face, so
    // copyWith would only ever warm the regular face. Iterating the real text
    // theme warms whatever family+weight the UI actually renders with.
    final textTheme = Theme.of(context).textTheme;
    final styles = <TextStyle?>[
      textTheme.displaySmall,
      textTheme.headlineMedium,
      textTheme.headlineSmall,
      textTheme.titleLarge,
      textTheme.titleMedium,
      textTheme.titleSmall,
      textTheme.bodyLarge,
      textTheme.bodyMedium,
      textTheme.bodySmall,
      textTheme.labelLarge,
      textTheme.labelMedium,
      textTheme.labelSmall,
    ];
    for (final style in styles) {
      if (style == null) continue;
      final painter = TextPainter(
        text: TextSpan(text: warmupGlyphs, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 1200);
      painter.dispose();
    }
  }

  @override
  void dispose() {
    _warmupTimer?.cancel();
    _controller.dispose();
    _engine.dispose();
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
                    child: _WarmupStage(
                      stage: _stage,
                      engine: _engine,
                      controller: _controller,
                    ),
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
  const _WarmupStage({
    required this.stage,
    required this.engine,
    required this.controller,
  });

  final int stage;
  final TerminalEngine engine;
  final TerminalController controller;

  @override
  Widget build(BuildContext context) {
    final team = context.select<TeamCubit, TeamIdentity?>(
      (cubit) => cubit.state.selectedTeam,
    );

    return SizedBox(
      width: 1200,
      height: 700,
      child: switch (stage) {
        1 => _SettingsWarmup(team: team),
        2 => TerminalView(
          engine,
          controller: controller,
          backgroundOpacity: 0.92,
          padding: const EdgeInsets.all(6),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _SettingsWarmup extends StatelessWidget {
  const _SettingsWarmup({required this.team});

  final TeamIdentity? team;

  @override
  Widget build(BuildContext context) {
    final executable = context
        .read<SessionPreferencesCubit>()
        .resolveExecutable();
    final members = team?.members ?? const <TeamMemberConfig>[];
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
                itemCount: members.length.clamp(0, 4) + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
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
                  final member = members[index - 1];
                  return _WarmupLaunchRow(
                    index: index,
                    name: member.name,
                    command: '$executable --member ${member.id}',
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
          prefixIcon: Icon(Icons.badge_outlined),
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
                Text(subtitle, style: AppTextStyles.of(context).caption),
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
          Icon(Icons.open_in_new),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(command, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
