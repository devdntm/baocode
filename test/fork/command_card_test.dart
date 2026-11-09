import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/step_folds.dart';
import 'package:baocode/chat/widgets/code_citation.dart';
import 'package:baocode/chat/widgets/command_step.dart';
import 'package:baocode/chat/widgets/shell_highlight.dart';
import 'package:baocode/fork/command_card.dart';
import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _command = "cd /work && python3 - <<'EOF'\nimport json\nprint(1)\nEOF";

Future<void> _pump(
  WidgetTester tester, {
  String output = '',
  CommandStatus status = CommandStatus.succeeded,
  bool expanded = false,
  VoidCallback? onToggle,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 600,
        child: CommandStep(
          command: _command,
          description: 'Inspect the goods',
          output: output,
          status: status,
          expanded: expanded,
          onToggle: onToggle ?? () {},
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() => ChatLook.current.value = ChatLook.cursor);
  tearDown(() => ChatLook.current.value = ChatLook.baocode);

  test('the programs a command runs, a heredoc\'s lines not among them', () {
    expect(shellPrograms(_command), ['cd', 'python3']);
    expect(
      shellPrograms('cd a && .venv/bin/python run.py | tail -3; echo done'),
      ['cd', '.venv/bin/python', 'tail', 'echo'],
    );
    expect(shellPrograms('FOO=1 sleep 5 && cat log && tail -n 2 log'), [
      'sleep',
      'cat',
      'tail',
    ]);
  });

  test('commands are cards of their own, not folded as quick steps', () {
    const item = TerminalItem(command: 'ls', output: '');
    expect(isQuickStep(item), isFalse);
    ChatLook.current.value = ChatLook.baocode;
    expect(isQuickStep(item), isTrue);
  });

  testWidgets('running with nothing printed: its header alone', (tester) async {
    await _pump(tester, status: CommandStatus.running);
    expect(find.byType(CursorCommandCard), findsOneWidget);
    expect(find.text('cd, python3'), findsOneWidget);
    expect(find.textContaining('import json'), findsNothing);
    expect(find.textContaining('\$ '), findsNothing);
  });

  testWidgets('printed: its last lines under the header; a tap opens it', (
    tester,
  ) async {
    var toggled = 0;
    await _pump(
      tester,
      output: [for (var i = 1; i <= 9; i++) 'line $i'].join('\n'),
      onToggle: () => toggled++,
    );
    expect(find.text('Inspect the goods'), findsOneWidget);
    final tail = find.textContaining('line 9');
    expect(tail, findsOneWidget);
    expect(find.textContaining('line 6'), findsOneWidget);
    expect(find.textContaining('line 5'), findsNothing);
    // In the theme's text color, faint, as Cursor's.
    expect(tester.widget<Text>(tail).style?.color, CursorCommandCard.faint);
    expect(
      tester.widget<Text>(find.text('cd, python3')).style?.color,
      CursorCommandCard.faint,
    );
    await tester.tap(tail);
    expect(toggled, 1);
  });

  testWidgets('open: the command colored and all it printed', (tester) async {
    await _pump(
      tester,
      output: [for (var i = 1; i <= 9; i++) 'line $i'].join('\n'),
      expanded: true,
    );
    expect(find.textContaining('import json'), findsOneWidget);
    expect(find.textContaining('line 1\n'), findsOneWidget);
  });

  testWidgets('open: the command in the editor theme\'s colors, by its '
      'shell grammar', (tester) async {
    const themed = Color(0xFF123456);
    String? asked;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: CodeCitationScope(
            colorizeBlock: (language, code) async {
              asked = language;
              return [
                for (final line in code.split('\n'))
                  [
                    TextSpan(
                      text: line,
                      style: const TextStyle(color: themed),
                    ),
                  ],
              ];
            },
            child: const CommandStep(
              command: 'cd /work && ls',
              description: 'List the work',
              output: 'a',
              expanded: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(asked, 'bash');
    final colored = tester.widgetList<RichText>(find.byType(RichText)).expand((
      rich,
    ) {
      final spans = <TextSpan>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'cd /work && ls') {
          spans.add(span);
        }
        return true;
      });
      return spans;
    });
    expect(colored.single.style?.color, themed);
  });

  testWidgets('BaoCode\'s look keeps its step', (tester) async {
    ChatLook.current.value = ChatLook.baocode;
    await _pump(tester, output: 'done');
    expect(find.byType(CursorCommandCard), findsNothing);
  });
}
