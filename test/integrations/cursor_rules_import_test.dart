import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/integrations/cursor_import/cursor_import.dart';
import 'package:baocode/integrations/cursor_import/cursor_import_dialog.dart';
import 'package:baocode/integrations/cursor_import/cursor_import_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A project's Cursor setup brought over: its rules as Claude Code's, its
/// MCP servers into .mcp.json, nothing the project has overwritten.
void main() {
  group('a rule', () {
    test('always applied: its text alone', () {
      final (text, alwaysNow) = convertCursorRule(
        '---\nalwaysApply: true\n---\n# Rule\n\nDo it.\n',
      );
      expect(text, '# Rule\n\nDo it.\n');
      expect(alwaysNow, isFalse);
    });

    test('for some files: its globs as paths', () {
      final (text, _) = convertCursorRule(
        '---\ndescription: Dart\nglobs: lib/**/*.dart, test/**\n'
        'alwaysApply: false\n---\nUse lints.\n',
      );
      expect(
        text,
        '---\npaths:\n  - "lib/**/*.dart"\n  - "test/**"\n---\n\nUse lints.\n',
      );
    });

    test('applied where relevant, by its description: read always now', () {
      final (text, alwaysNow) = convertCursorRule(
        '---\ndescription: When writing SQL\n---\nQuote names.\n',
      );
      expect(text, 'Quote names.\n');
      expect(alwaysNow, isTrue);
    });

    test('.cursorrules, no front matter: as it is', () {
      expect(convertCursorRule('Be brief.\n'), ('Be brief.\n', false));
    });
  });

  test('a server: Cursor\'s env references as Claude Code\'s; a URL\'s '
      'is an http one', () {
    expect(
      convertCursorServer({
        'command': 'npx',
        'args': ['-y', 'srv', r'--token=${env:TOKEN}'],
        'env': {'KEY': r'${env:API_KEY}'},
      }),
      {
        'command': 'npx',
        'args': ['-y', 'srv', r'--token=${TOKEN}'],
        'env': {'KEY': r'${API_KEY}'},
      },
    );
    expect(convertCursorServer({'url': 'https://x/mcp'}), {
      'type': 'http',
      'url': 'https://x/mcp',
    });
  });

  group('a project', () {
    late Directory temp;
    late String root;
    late String oldHome;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('baocode-cursor-import');
      root = p.join(temp.path, 'my_project');
      oldHome = CursorProject.home;
      CursorProject.home = p.join(temp.path, 'home');
      void write(String path, String text) => File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
      write(
        p.join(root, '.cursor', 'rules', 'style.mdc'),
        '---\nalwaysApply: true\n---\nStyle.\n',
      );
      write(
        p.join(root, '.cursor', 'rules', 'db', 'sql.mdc'),
        '---\nglobs: "**/*.sql"\n---\nSQL.\n',
      );
      write(p.join(root, '.cursorrules'), 'Old rules.\n');
      write(p.join(root, '.claude', 'rules', 'style.md'), 'Mine.\n');
      write(
        p.join(root, '.cursor', 'mcp.json'),
        jsonEncode({
          'mcpServers': {
            'db': {
              'command': 'db-mcp',
              'env': {'T': r'${env:T}'},
            },
            'web': {'url': 'https://w/mcp'},
          },
        }),
      );
      write(
        p.join(root, '.mcp.json'),
        jsonEncode({
          'mcpServers': {
            'web': {'type': 'http', 'url': 'https://mine/mcp'},
          },
          'other': 1,
        }),
      );
      for (final session in ['s1', 's2']) {
        write(
          p.join(
            CursorProject.folderOf(root),
            'agent-transcripts',
            session,
            '$session.jsonl',
          ),
          '{}\n',
        );
      }
    });
    tearDown(() {
      CursorProject.home = oldHome;
      temp.deleteSync(recursive: true);
    });

    test('found in Cursor\'s folder of it, its path dashed', () {
      expect(
        p.basename(CursorProject.folderOf('/Users/me/Downloads/flipping_ai')),
        'Users-me-Downloads-flipping-ai',
      );
      expect(CursorProject.seen(root), isTrue);
      expect(CursorProject.seen(p.join(temp.path, 'nothing')), isFalse);
      expect(CursorProject.seen('ssh://host/p'), isFalse);
    });

    test('what it has, and nothing of its own overwritten', () async {
      final project = await CursorProject.read(root);
      expect(
        [
          for (final rule in project.rules)
            (p.relative(rule.target, from: root), rule.exists),
        ],
        [
          ('.claude/rules/db/sql.md', false),
          ('.claude/rules/style.md', true),
          ('.claude/rules/cursorrules.md', false),
        ],
      );
      expect(project.servers.keys, ['db']);
      expect(project.servers['db']!['env'], {'T': r'${T}'});
      expect(project.serversHad, ['web']);
      expect(project.sessions, 2);

      final written = await project.importRules(project.rules);
      expect(written, hasLength(2));
      expect(
        File(p.join(root, '.claude', 'rules', 'style.md')).readAsStringSync(),
        'Mine.\n',
      );
      expect(
        File(p.join(root, '.claude', 'rules', 'db', 'sql.md'))
            .readAsStringSync(),
        startsWith('---\npaths:\n  - "**/*.sql"\n---'),
      );

      await project.importServers(project.servers.keys);
      final mcp = jsonDecode(
        File(p.join(root, '.mcp.json')).readAsStringSync(),
      ) as Map<String, Object?>;
      expect((mcp['mcpServers']! as Map).keys, containsAll(['web', 'db']));
      expect((mcp['mcpServers']! as Map)['web'], {
        'type': 'http',
        'url': 'https://mine/mcp',
      });
      expect(mcp['other'], 1);
    });

    testWidgets('the dialog: the parts, a rule\'s text shown, imported', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      // Open until closed: not waited for.
      unawaited(CursorImport.open(context, root));
      for (
        var i = 0;
        i < 50 && find.byType(CursorImportDialog).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump();
      expect(find.text('Rules: 2 → .claude/rules'), findsOneWidget);
      expect(
        find.textContaining('MCP servers: 1 → .mcp.json (db)'),
        findsOneWidget,
      );
      expect(find.text('Already in .mcp.json: web'), findsOneWidget);
      expect(find.text('Conversations: 2 → memsearch memory'), findsOneWidget);
      expect(find.text('exists, kept'), findsOneWidget);

      await tester.tap(find.text('sql.md'));
      await tester.pump();
      expect(find.textContaining('"**/*.sql"'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cursor.import.run')));
      for (
        var i = 0;
        i < 50 && find.textContaining('Imported:').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('Imported: 2 rules, 1 MCP servers.'), findsOneWidget);
      expect(
        File(p.join(root, '.claude', 'rules', 'cursorrules.md')).existsSync(),
        isTrue,
      );
    });

    test('a notice put off is not shown again', () async {
      expect(await CursorImportNotice.putOff(root), isFalse);
      await CursorImportNotice.putOffFor(root);
      expect(await CursorImportNotice.putOff(root), isTrue);
    });
  });
}
