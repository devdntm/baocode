import 'dart:convert';
import 'dart:io';

import 'package:baocode/customize/customization_store.dart';
import 'package:baocode/integrations/claude_context/claude_context.dart';
import 'package:baocode/integrations/claude_context/claude_context_ui.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../ide/workbench/fake_files.dart';

const _server = {
  'command': '/opt/homebrew/bin/node',
  'args': ['/x/node_modules/@zilliz/claude-context-mcp/dist/index.js'],
};

Map<String, Object?> _report({
  bool exists = true,
  int indexed = 2488,
  int? project = 2488,
  int? missing = 0,
  String? status = 'completed',
  bool running = false,
  List<Map<String, Object?>> byDir = const [],
}) => {
  'exists': exists,
  'chunks': 19171,
  'indexedFiles': indexed,
  'projectFiles': project,
  'missing': missing,
  'missingByDir': byDir,
  'snapshot': {'status': status},
  'serverRunning': running,
};

/// The claude-context index: its state as the helper reads it, a run's
/// progress, where the IDE and the sidebar show it.
void main() {
  late List<List<String>> asked;
  late List<Map<String, Object?>> Function(List<String> args) answer;

  setUp(() {
    asked = [];
    answer = (_) => [];
    ClaudeContextIndex.enabled = true;
    ClaudeContextIndex.forgetAll();
    ClaudeContextOffer.forgetOffered();
    ClaudeContextIndex.runner = (args, server) {
      asked.add(args);
      return Stream.fromIterable(answer(args));
    };
  });
  tearDown(() {
    ClaudeContextIndex.enabled = false;
    ClaudeContextIndex.userServer = null;
    ClaudeContextIndex.forgetAll();
    KeybindingService.instance = KeybindingService();
  });

  test('its state, as the helper found it', () {
    ClaudeContextState of(Map<String, Object?> json) =>
        ClaudeContextReport.fromJson(json).state;
    expect(of(_report()), ClaudeContextState.complete);
    expect(
      of(_report(indexed: 2400, missing: 88)),
      ClaudeContextState.incomplete,
    );
    expect(
      of(_report(exists: false, status: null)),
      ClaudeContextState.notIndexed,
    );
    expect(
      of(_report(status: 'indexing', running: true)),
      ClaudeContextState.indexing,
    );
    // Left indexing by a server that is gone.
    expect(of(_report(status: 'indexing')), ClaudeContextState.interrupted);
    expect(of(_report(status: 'indexfailed')), ClaudeContextState.failed);
    final report = ClaudeContextReport.fromJson(
      _report(
        missing: 3,
        byDir: [
          {'dir': 'lib/ide', 'count': 2},
          {'dir': 'test', 'count': 1},
        ],
      ),
    );
    expect(report.missingByDir.first, (dir: 'lib/ide', count: 2));
  });

  test('its server: claude-context among the user\'s MCP servers', () async {
    final temp = Directory.systemTemp.createTempSync('baocode-cc-config');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = CustomizationStore(
      configDir: p.join(temp.path, '.claude'),
      homeDir: temp.path,
    );
    expect(await ClaudeContextIndex.serverIn(store, '/p'), isNull);
    File(p.join(temp.path, '.claude.json')).writeAsStringSync(
      jsonEncode({
        'mcpServers': {'claude-context': _server},
      }),
    );
    expect(await ClaudeContextIndex.serverIn(store, '/p'), _server);
  });

  test('only for a project on this machine, and where there is a server', () {
    expect(ClaudeContextIndex.of('/p', null), isNull);
    expect(ClaudeContextIndex.of('ssh://host/p', _server), isNull);
    final index = ClaudeContextIndex.of('/p', _server);
    expect(index, isNotNull);
    expect(ClaudeContextIndex.of('/p', _server), same(index));
  });

  test('looked at, then indexed: its progress, then what it is', () async {
    final index = ClaudeContextIndex.of('/p', _server)!;
    answer = (args) => switch (args.first) {
      'check' => [
        {'event': 'check', ..._report(indexed: 2400, missing: 88)},
      ],
      _ => [
        {'event': 'started'},
        {
          'event': 'progress',
          'rows': 120,
          'snapshot': {'status': 'indexing', 'percentage': 45},
        },
        {'event': 'done', ..._report()},
      ],
    };
    await index.check();
    expect(asked.single, ['check', '/p', '--json']);
    expect(index.state, ClaudeContextState.incomplete);

    final states = <(ClaudeContextState, double?)>[];
    index.addListener(() => states.add((index.state, index.percentage)));
    await index.index(force: true);
    expect(asked.last, ['index', '/p', '--json', '--force']);
    expect(states, contains((ClaudeContextState.indexing, 45.0)));
    expect(index.state, ClaudeContextState.complete);
    expect(index.busy, isFalse);
  });

  test('an error said is its error', () async {
    final index = ClaudeContextIndex.of('/p', _server)!;
    answer = (_) => [
      {'event': 'error', 'message': 'Milvus is not running'},
    ];
    await index.check();
    expect(index.state, ClaudeContextState.failed);
    expect(index.error, 'Milvus is not running');
  });

  testWidgets('the IDE\'s status bar: "Index 2488/2488"; clicked, what it '
      'misses and what to do; all again asked first', (tester) async {
    final serverOf = ClaudeContextIndex.serverOf;
    addTearDown(() => ClaudeContextIndex.serverOf = serverOf);
    ClaudeContextIndex.serverOf = (root) async => _server;
    answer = (args) => switch (args.first) {
      'check' => [
        {
          'event': 'check',
          ..._report(
            indexed: 2400,
            missing: 88,
            byDir: [
              {'dir': 'lib/ide', 'count': 80},
            ],
          ),
        },
      ],
      _ => [
        {'event': 'done', ..._report()},
      ],
    };
    await pumpWorkbench(tester, {'a.txt': 'a'});
    final shown = find.text('Index 2400/2488');
    for (var i = 0; i < 100 && shown.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Index 2400/2488'), findsOneWidget);

    await tester.tap(find.text('Index 2400/2488'));
    await tester.pumpAndSettle();
    expect(
      find.text('2400 of 2488 files indexed, 19171 chunks'),
      findsOneWidget,
    );
    expect(find.text('80 missing in lib/ide'), findsOneWidget);
    await tester.tap(find.text('Reindex All…'));
    await tester.pumpAndSettle();
    expect(find.text('Index the whole project again?'), findsOneWidget);
    await tester.tap(find.text('Reindex All'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && asked.length < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(asked.last, ['index', inRoot(''), '--json', '--force']);
    await tester.pump();
    expect(find.text('Index 2488/2488'), findsOneWidget);
  });

  testWidgets('a project with no index: offered; always, it is indexed and '
      'the next one is at once', (tester) async {
    final serverOf = ClaudeContextIndex.serverOf;
    addTearDown(() => ClaudeContextIndex.serverOf = serverOf);
    ClaudeContextIndex.serverOf = (root) async => _server;
    // A settings file of its own: the setting is not left to the others.
    final data = Directory.systemTemp.createTempSync('baocode-offer');
    final files = SettingsFiles.instance;
    SettingsFiles.instance = SettingsFiles(DataDirectory(data.path));
    addTearDown(() {
      SettingsFiles.instance = files;
      data.deleteSync(recursive: true);
    });
    final settings = SettingsFiles.instance.settings;
    answer = (args) => switch (args.first) {
      'check' => [
        {'event': 'check', ..._report(exists: false, project: null)},
      ],
      _ => [
        {'event': 'done', ..._report()},
      ],
    };
    await pumpWorkbench(tester, {'a.txt': 'a'});
    final offer = find.textContaining('not indexed for semantic code search');
    for (var i = 0; i < 100 && offer.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(offer, findsOneWidget);
    expect(asked, [
      ['check', inRoot(''), '--json'],
    ]);

    // The toast in, its sliding done.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Always Index'));
    for (var i = 0; i < 50 && asked.length < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(asked.last, ['index', inRoot(''), '--json']);
    for (
      var i = 0;
      i < 50 && settings[ClaudeContextOffer.settingKey] != true;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(settings[ClaudeContextOffer.settingKey], isTrue);

    // Another project with none: indexed, not offered.
    final other = ClaudeContextIndex.of('/elsewhere', _server)!;
    await tester.pump();
    final context = tester.element(find.text('Index 2488/2488'));
    await tester.runAsync(() async {
      asked.clear();
      await other.check();
      await offerClaudeContextIndex(context, IdeNotifications(), other);
    });
    expect(asked.last, ['index', '/elsewhere', '--json']);
  });

  testWidgets('a project\'s menu in the sidebar: its state, to index', (
    tester,
  ) async {
    ClaudeContextIndex.userServer = _server;
    answer = (_) => [
      {'event': 'check', ..._report()},
    ];
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
    const project = Project('p', '/p');
    final index = ClaudeContextIndex.of('/p', _server)!;
    claudeContextProjectItems(context, project);
    for (var i = 0; i < 100 && index.busy; i++) {
      await tester.pump();
    }
    final items = claudeContextProjectItems(context, project);
    expect(
      [for (final item in items) item.label],
      ['', 'Index for Search', 'Reindex All…'],
    );
    expect(items[1].detail, 'Index 2488/2488');
    ClaudeContextIndex.userServer = null;
    expect(
      claudeContextProjectItems(context, const Project('q', '/q')),
      isEmpty,
    );
  });
}
