import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// tool/cursor_import/cursor_memsearch_import.py, run as BaoCode runs it:
/// Cursor's conversations copied into the project, each new turn told in
/// short (by a stand-in for Claude Code), added to the journals; run again,
/// nothing twice.
void main() {
  final script = p.absolute('tool/cursor_import/cursor_memsearch_import.py');
  late Directory temp;
  late String cursor, copy, cache, memory, claude;
  late Map<String, String> env;

  String line(String role, List<Map<String, Object?>> content) => jsonEncode({
    'role': role,
    'message': {'content': content},
  });
  Map<String, Object?> text(String text) => {'type': 'text', 'text': text};

  setUp(() {
    temp = Directory.systemTemp.createTempSync('baocode-cursor-history');
    final root = p.join(temp.path, 'proj');
    cursor = p.join(temp.path, 'cursor', 'agent-transcripts');
    copy = p.join(root, '.memsearch', 'cursor-transcripts');
    cache = p.join(root, '.memsearch', 'cursor-import-cache');
    memory = p.join(root, '.memsearch', 'memory');
    File(p.join(cursor, 's1', 's1.jsonl'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        [
          line('user', [
            text(
              '<timestamp>Monday, Nov 02, 2026, 3:04 PM (UTC+7)</timestamp>\n'
              '<user_query>Fix the build</user_query>',
            ),
          ]),
          line('assistant', [
            text('Fixed it.'),
            {
              'type': 'tool_use',
              'name': 'StrReplace',
              'input': {'path': '$root/lib/a.dart'},
            },
            {'type': 'tool_use', 'name': 'Shell', 'input': <String, Object?>{}},
            // As Cursor writes some: its input JSON text, cut short.
            {'type': 'tool_use', 'name': 'Grep', 'input': '{"path": "'},
          ]),
          // And a message with no content at all.
          jsonEncode({
            'role': 'assistant',
            'message': {'content': null},
          }),
          // No answer: nothing to tell.
          line('user', [
            text(
              '<timestamp>Monday, Nov 02, 2026, 3:10 PM (UTC+7)</timestamp>\n'
              '<user_query>Still there?</user_query>',
            ),
          ]),
          line('user', [
            text(
              '<timestamp>Tuesday, Nov 03, 2026, 9:00 AM (UTC+7)</timestamp>\n'
              '<user_query>And now?</user_query>',
            ),
          ]),
          line('assistant', [text('Now too.')]),
        ].join('\n'),
      );
    // A day the user has already: Claude Code's session, and a turn of s1
    // brought by hand before (`turn:line-`).
    File(p.join(memory, '2026-11-03.md'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '## Session 10:00\n\n### 10:00\n- Claude Code did things.\n',
      );
    final home = p.join(temp.path, 'home');
    File(
        p.join(
          home,
          '.claude/plugins/cache/memsearch-plugins/memsearch/1.0/prompts',
          'summarize.txt',
        ),
      )
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('Summarize {{AGENT_NAME}}.');
    // Its bullet: the turn's first line of the user's.
    claude = p.join(temp.path, 'claude');
    File(claude).writeAsStringSync(
      '#!/bin/sh\n'
      'q=\$(grep -m1 "^\\[User\\]:" | sed "s/^\\[User\\]: //")\n'
      'echo "- Told: \$q"\n',
    );
    Process.runSync('chmod', ['+x', claude]);
    env = {'HOME': home, 'CLAUDE_BIN': claude};
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<String> run(List<String> args) async {
    final result = await Process.run('python3', [
      '-I',
      script,
      ...args,
    ], environment: env);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    return '${result.stdout}';
  }

  List<String> dirs() => [cursor, copy, cache, memory];

  test('copied, told, added; run again, nothing twice', () async {
    expect(await run(['count', ...dirs()]), '2 turns\n');
    await run(['sync', cursor, copy]);
    expect(File(p.join(copy, 's1', 's1.jsonl')).existsSync(), isTrue);
    expect(
      await run(['summarize', ...dirs(), '--jobs', '2']),
      contains('done 2, failed 0'),
    );
    await run(['assemble', ...dirs()]);

    final day2 = File(p.join(memory, '2026-11-02.md')).readAsStringSync();
    expect(day2, contains('## Session 15:04 (Cursor)'));
    expect(day2, contains('- Told: Fix the build'));
    expect(day2, isNot(contains('Still there?')));
    expect(
      day2,
      contains(
        '<!-- session:s1 turn:L1 source:cursor '
        'transcript:${p.join(copy, 's1', 's1.jsonl')} -->',
      ),
    );
    // Cursor's turn before the Claude Code session of its day.
    final day3 = File(p.join(memory, '2026-11-03.md')).readAsStringSync();
    expect(day3.indexOf('- Told: And now?'), lessThan(day3.indexOf('10:00')));

    expect(await run(['count', ...dirs()]), '0 turns\n');
    expect(
      await run(['assemble', ...dirs()]),
      contains('wrote 0 turns into 0 days'),
    );
    expect(File(p.join(memory, '2026-11-03.md')).readAsStringSync(), day3);
  });

  test('a turn brought by hand before (turn:line-) is not told again; one '
      'new on a day with Cursor\'s already goes after them', () async {
    File(p.join(memory, '2026-11-02.md')).writeAsStringSync(
      '## Session 15:04 (Cursor)\n\n### 15:04\n'
      '<!-- session:s1 turn:line-1 transcript:x source:cursor -->\n'
      '- By hand.\n',
    );
    expect(await run(['count', ...dirs()]), '1 turns\n');
    await run(['sync', cursor, copy]);
    await run(['summarize', ...dirs()]);
    await run(['assemble', ...dirs()]);
    expect(
      File(p.join(memory, '2026-11-02.md')).readAsStringSync(),
      isNot(contains('Told')),
    );
    final day3 = File(p.join(memory, '2026-11-03.md')).readAsStringSync();
    expect(day3, contains('- Told: And now?'));

    // Cursor gone: the copy is read, its sessions kept.
    Directory(cursor).deleteSync(recursive: true);
    await run(['sync', cursor, copy]);
    expect(File(p.join(copy, 's1', 's1.jsonl')).existsSync(), isTrue);
    expect(await run(['count', ...dirs()]), '0 turns\n');
  });

  test('the limit reached: stopped, an error, what was told kept', () async {
    File(claude).writeAsStringSync(
      '#!/bin/sh\ncat >/dev/null\necho "You\'ve hit your limit · resets 5pm"\n',
    );
    final result = await Process.run('python3', [
      '-I',
      script,
      'summarize',
      ...dirs(),
    ], environment: env);
    expect(result.exitCode, 3);
    expect('${result.stdout}', contains('limit reached after 0 turns'));
  });
}
