// A shell command as Cursor's conversation shows it (`chat.look: cursor`,
// docs/fork.md): a card headed ">_ what it does  cd, python3"; once it has
// printed, the last lines of that faded under the header; a click opens
// the command and all it printed.

import 'package:flutter/material.dart';

import '../base/smooth_scroll.dart';
import '../chat/chat_models.dart';
import '../chat/widgets/code_citation.dart' show CodeCitationScope;
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/shell_highlight.dart';
import '../chat/widgets/shimmer_text.dart';
import '../chat/widgets/step_header.dart';
import '../chat/widgets/terminal_output.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;

class CursorCommandCard extends StatelessWidget {
  const CursorCommandCard({
    super.key,
    required this.title,
    required this.command,
    required this.output,
    required this.status,
    this.background = false,
    this.backgroundLabel,
    this.expanded = false,
    this.onToggle,
    this.menu,
  });

  /// What it does: its description, or its first line.
  final String title;
  final String command;
  final String output;
  final CommandStatus status;
  final bool background;

  /// Said after the programs where it was left running on its own.
  final String? backgroundLabel;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Copy, move to the background: over the card's corner while open.
  final Widget? menu;

  /// The lines of output shown under the header, closed.
  static const tailLines = 4;

  /// The most an open card's command and output take before scrolling.
  static const maxBodyHeight = 260.0;

  static const radius = 10.0;

  /// Its colors, the theme's text's as Cursor's card has them: the title
  /// at 60%, the programs, the icon and the output's last lines at 36%
  /// (measured on its screenshots), what it printed, open, at 55%.
  static Color get titleColor => AppColors.text.withValues(alpha: 0.6);
  static Color get faint => AppColors.text.withValues(alpha: 0.36);
  static TextStyle get printedStyle =>
      stepMono.copyWith(color: AppColors.text.withValues(alpha: 0.55));

  bool get _running => status == CommandStatus.running && !background;

  /// The last [tailLines] lines [printed] has (not the blank ones at its
  /// end); none where it printed nothing.
  static List<String> tail(String printed) {
    final lines = printed.trimRight().split('\n');
    if (lines.length == 1 && lines.single.trim().isEmpty) return const [];
    return lines.length <= tailLines
        ? lines
        : lines.sublist(lines.length - tailLines);
  }

  @override
  Widget build(BuildContext context) {
    final printed = terminalOutput(output);
    final lines = expanded ? const <String>[] : tail(printed.text);
    return HoverBuilder(
      cursor: onToggle == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: _header(context, hovered),
            ),
            if (expanded)
              _body(printed)
            else if (lines.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: _tail(lines),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool hovered) {
    final programs = shellPrograms(command);
    final faint = CursorCommandCard.faint;
    final titleStyle = TextStyle(
      color: CursorCommandCard.titleColor,
      fontSize: 13,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(
            expanded
                ? Codicons.chevronDown
                : hovered && onToggle != null
                ? Codicons.chevronRight
                : Codicons.terminal,
            size: 14,
            color: faint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  flex: 3,
                  child: _running
                      ? ShimmerText(
                          title,
                          style: titleStyle,
                          ellipsis: false,
                          padding: EdgeInsets.zero,
                        )
                      : Text(
                          title,
                          style: titleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                if ([...programs, ?backgroundLabel].join(', ') case final more
                    when more.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 2,
                    child: Text(
                      more,
                      style: TextStyle(color: faint, fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (expanded && menu != null) ...[const SizedBox(width: 6), menu!],
        ],
      ),
    );
  }

  /// The last lines it printed, fading out towards the top.
  Widget _tail(List<String> lines) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
    child: ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33000000), Color(0xFF000000)],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: Text(
        lines.join('\n'),
        style: stepMono.copyWith(color: CursorCommandCard.faint),
        maxLines: tailLines,
        overflow: TextOverflow.clip,
        softWrap: false,
      ),
    ),
  );

  Widget _body(TerminalOutput printed) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    constraints: const BoxConstraints(maxHeight: maxBodyHeight),
    child: _BodyScroll(
      followEnd: _running,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ThemedCommand(command),
            if (printed.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              if (printed.styled)
                Text.rich(printed.span, style: printedStyle)
              else
                Text(printed.text, style: printedStyle),
            ],
          ],
        ),
      ),
    ),
  );
}

/// An open card's command and output, scrolling; at the end while it runs.
class _BodyScroll extends StatefulWidget {
  const _BodyScroll({required this.followEnd, required this.child});

  final bool followEnd;
  final Widget child;

  @override
  State<_BodyScroll> createState() => _BodyScrollState();
}

class _BodyScrollState extends State<_BodyScroll> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    child: SingleChildScrollView(
      controller: _controller,
      reverse: widget.followEnd,
      child: widget.child,
    ),
  );
}

/// `$ command` in the editor theme's colors, as a code block's (its shell
/// grammar, through [CodeCitationScope.colorizeBlock]); the terminal's
/// light coloring ([highlightShell]) until that comes, or where there is
/// none.
class _ThemedCommand extends StatefulWidget {
  const _ThemedCommand(this.command);

  final String command;

  @override
  State<_ThemedCommand> createState() => _ThemedCommandState();
}

class _ThemedCommandState extends State<_ThemedCommand> {
  List<List<TextSpan>>? _lines;
  String? _colored;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _color();
  }

  @override
  void didUpdateWidget(_ThemedCommand old) {
    super.didUpdateWidget(old);
    if (old.command != widget.command) _color();
  }

  void _color() {
    final command = widget.command;
    if (command == _colored) return;
    _colored = command;
    final colorize = CodeCitationScope.maybeOf(context)?.colorizeBlock;
    if (colorize == null) return;
    colorize('bash', command).then((lines) {
      if (!mounted || widget.command != command || lines == null) return;
      setState(() => _lines = lines);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '\$ ',
            style: TextStyle(color: AppColors.textFaint),
          ),
          if (lines == null)
            ...highlightShell(widget.command)
          else
            for (final (i, line) in lines.indexed) ...[
              if (i > 0) const TextSpan(text: '\n'),
              ...line,
            ],
        ],
      ),
      style: stepMono.copyWith(color: themeColors['editor.foreground']),
    );
  }
}
