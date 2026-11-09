import 'package:baocode/fork/run_command_panel.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _command = "cd app && npm ci\necho 'done'";

/// As approve-blocked 0.2 asks it.
QuestionRequest _ask({
  List<String> options = const ['Разрешить', 'Отклонить', "Allowlist 'npm'"],
  String header = 'Auto mode',
  String? prompt,
}) => QuestionRequest(
  id: 'r1',
  title: 'Claude has a question',
  questions: [
    Question(
      prompt:
          prompt ??
          'Классификатор auto mode заблокировал вызов Bash '
              '[Remote Shell Writes]:\n\n```bash\n$_command\n```\n\n'
              'Разрешить его один раз?',
      header: header,
      options: [for (final label in options) QuestionOption(label)],
    ),
  ],
);

Future<List<List<String>>> _answered(
  WidgetTester tester,
  BlockedCommandAsk ask,
  Future<void> Function() act,
) async {
  List<List<String>>? picks;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 500,
            child: RunCommandPanel(
              ask: ask,
              onAnswer: (answer) => picks = (answer as QuestionAnswer).picks,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await act();
  await tester.pumpAndSettle();
  return picks!;
}

void main() {
  test('the mod\'s question read: its command whole, program, reason', () {
    final ask = BlockedCommandAsk.of(_ask())!;
    expect(ask.command, _command);
    expect(ask.program, 'npm');
    expect(ask.reason, '[Remote Shell Writes]');
    expect(ask.allowlist, "Allowlist 'npm'");
  });

  test(
    '0.1\'s question, without the fence: the text between its paragraphs',
    () {
      final ask = BlockedCommandAsk.of(
        _ask(
          options: const ['Разрешить', 'Отклонить'],
          prompt:
              'Классификатор заблокировал вызов Bash:\n\nls -la\n\n'
              'Разрешить его один раз?',
        ),
      )!;
      expect(ask.command, 'ls -la');
      expect(ask.allowlist, isNull);
    },
  );

  test('any other question is not one', () {
    expect(BlockedCommandAsk.of(_ask(header: 'Plugin')), isNull);
    expect(BlockedCommandAsk.of(_ask(options: const ['Yes', 'No'])), isNull);
  });

  testWidgets('Run command: npm; Enter runs it once', (tester) async {
    final ask = BlockedCommandAsk.of(_ask())!;
    final picks = await _answered(tester, ask, () async {
      expect(
        find.text('Run command: npm  [Remote Shell Writes]'),
        findsOneWidget,
      );
      expect(find.textContaining('npm ci'), findsOneWidget);
      expect(find.text('Ask Every Time'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    });
    expect(picks, [
      ['Разрешить'],
    ]);
  });

  testWidgets('Skip refuses it', (tester) async {
    final ask = BlockedCommandAsk.of(_ask())!;
    final picks = await _answered(
      tester,
      ask,
      () => tester.tap(find.text('Skip')),
    );
    expect(picks, [
      ['Отклонить'],
    ]);
  });

  testWidgets('Allowlist picked, Run keeps the program allowed', (
    tester,
  ) async {
    final ask = BlockedCommandAsk.of(_ask())!;
    final picks = await _answered(tester, ask, () async {
      await tester.tap(find.text('Ask Every Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Allowlist 'npm'").last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run ⏎'));
    });
    expect(picks, [
      ["Allowlist 'npm'"],
    ]);
  });
}
