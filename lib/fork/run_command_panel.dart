// The approve-blocked mod's question (docs/fork.md), auto mode's
// classifier having refused a command, as Cursor asks to run one
// (`chat.look: cursor`): "Run command: npm", the command, Ask Every Time or
// Allowlist 'npm' at the left, Skip and Run ⏎ at the right. The mod's own
// options are what it answers: the logic stays the mod's, which a terminal
// asks as a plain question.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/floating/floating_placement.dart';
import '../chat/panels/interaction_panel.dart' show PanelButton;
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/shell_highlight.dart';
import '../kernel/kernel_types.dart';
import '../sidebar/sidebar_menu.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';

/// The mod's question about one command, read off its [QuestionRequest].
class BlockedCommandAsk {
  const BlockedCommandAsk({
    required this.question,
    required this.command,
    required this.run,
    required this.skip,
    this.allowlist,
    this.reason,
  });

  /// The question's text: the answer goes under it.
  final String question;
  final String command;

  /// The mod's options: allow once, refuse, allow and keep the program.
  final String run;
  final String skip;
  final String? allowlist;

  /// What the classifier said, `[Remote Shell Writes]`.
  final String? reason;

  /// As the mod asks it (`header: 'Auto mode'`, its first options
  /// `Разрешить` and `Отклонить`); null for any other question.
  static BlockedCommandAsk? of(InteractionRequest request) {
    if (request is! QuestionRequest || request.questions.length != 1) {
      return null;
    }
    final question = request.questions.single;
    final labels = [for (final option in question.options) option.label];
    if (question.header != 'Auto mode' ||
        labels.length < 2 ||
        labels[0] != 'Разрешить' ||
        labels[1] != 'Отклонить') {
      return null;
    }
    final prompt = question.prompt;
    final fenced = RegExp(r'```bash\n([\s\S]*?)\n```').firstMatch(prompt);
    final command =
        fenced?.group(1) ??
        switch (prompt.split('\n\n')) {
          final parts when parts.length >= 3 =>
            parts.sublist(1, parts.length - 1).join('\n\n'),
          _ => null,
        };
    if (command == null || command.trim().isEmpty) return null;
    final reason = RegExp(r'\[[^\]\n]+\]').firstMatch(prompt.split('\n').first);
    return BlockedCommandAsk(
      question: prompt,
      command: command,
      run: labels[0],
      skip: labels[1],
      allowlist: labels.length > 2 ? labels[2] : null,
      reason: reason?.group(0),
    );
  }

  /// The program its card is titled by: the first but `cd`.
  String get program {
    final programs = shellPrograms(command);
    return programs.where((p) => p != 'cd').firstOrNull ??
        programs.firstOrNull ??
        command.trim().split(RegExp(r'\s+')).first;
  }
}

class RunCommandPanel extends StatefulWidget {
  const RunCommandPanel({super.key, required this.ask, required this.onAnswer});

  final BlockedCommandAsk ask;
  final ValueChanged<InteractionAnswer> onAnswer;

  @override
  State<RunCommandPanel> createState() => _RunCommandPanelState();
}

class _RunCommandPanelState extends State<RunCommandPanel> {
  final _focus = FocusNode(debugLabel: 'Run command');

  /// Allowlist picked in the menu: Run keeps the program allowed too.
  bool _allowlist = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _pick(String label) => widget.onAnswer(
    QuestionAnswer([
      [label],
    ]),
  );

  void _run() => _pick(
    _allowlist && widget.ask.allowlist != null
        ? widget.ask.allowlist!
        : widget.ask.run,
  );

  void _skip() => _pick(widget.ask.skip);

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _run();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _skip();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ask = widget.ask;
    final mono = AppFonts.uiCodeStyle(12).copyWith(height: 1.5);
    return Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bubbleFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.bubbleBorder()),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Run command: ${ask.program}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (ask.reason case final reason?)
                    TextSpan(
                      text: '  $reason',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                color: AppColors.text.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: SingleChildScrollView(
                child: Text.rich(
                  TextSpan(
                    style: mono,
                    children: [
                      TextSpan(
                        text: '\$ ',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                      ...highlightShell(ask.command),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ModeMenu(
                  allowlist: ask.allowlist,
                  picked: _allowlist,
                  onPick: (value) => setState(() => _allowlist = value),
                ),
                const Spacer(),
                PanelButton(label: 'Skip', onTap: _skip),
                const SizedBox(width: 6),
                PanelButton(label: 'Run ⏎', primary: true, onTap: _run),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Ask Every Time ⌄": or the mod's Allowlist 'npm', where it offers one.
class _ModeMenu extends StatelessWidget {
  const _ModeMenu({
    required this.allowlist,
    required this.picked,
    required this.onPick,
  });

  final String? allowlist;
  final bool picked;
  final ValueChanged<bool> onPick;

  static const askEveryTime = 'Ask Every Time';

  @override
  Widget build(BuildContext context) {
    final label = picked && allowlist != null ? allowlist! : askEveryTime;
    return SidebarMenu(
      placement: (side: FloatingSide.top, align: FloatingAlign.start),
      width: 200,
      items: () => [
        SidebarMenuItem(
          askEveryTime,
          checked: !picked,
          onSelected: () => onPick(false),
        ),
        if (allowlist case final allow?)
          SidebarMenuItem(
            allow,
            checked: picked,
            onSelected: () => onPick(true),
          ),
      ],
      builder: (context, menu) => HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: allowlist == null ? null : menu.open,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: hovered && allowlist != null ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                if (allowlist != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Codicons.chevronDown,
                    size: 12,
                    color: AppColors.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
