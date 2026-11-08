import 'dart:io';

import 'package:baocode/ide/cursor_layout/agents_bar.dart';
import 'package:baocode/ide/cursor_layout/cursor_columns.dart';
import 'package:baocode/ide/cursor_layout/cursor_grid.dart';
import 'package:baocode/ide/cursor_layout/cursor_layout_service.dart';
import 'package:baocode/ide/cursor_layout/layout_contribution.dart';
import 'package:baocode/ide/git/commit_message.dart';
import 'package:baocode/ide/ide_columns.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/workbench/parts/grid.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../terminal/fake_pty.dart';
import '../terminal/fake_terminal.dart';
import '../workbench/fake_files.dart';

const _agentsKey = Key('test-agents');

final _agents = find.byKey(const ValueKey('ide-agents'));
final _chat = find.byKey(const ValueKey('ide-chat'));
final _editor = find.byKey(const ValueKey('ide-editor-column'));
final _sidebar = find.byKey(const ValueKey('ide-sidebar'));
final _activityBar = find.byKey(const ValueKey('ide-activity-bar'));

/// `workbench.ide.layout: cursor`: the project's chats and the chat on the
/// left, the editor, the side bar on the right under the activity bar's
/// row, the status bar under all.
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  UserSettings settingsWith(String json) {
    final temp = Directory.systemTemp.createTempSync('baocode-cursor-grid');
    addTearDown(() => temp.deleteSync(recursive: true));
    final settings = UserSettings(
      p.join(temp.path, 'User', 'settings.json'),
      debounce: Duration.zero,
    );
    addTearDown(settings.dispose);
    File(settings.path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(json);
    settings.loadSync();
    return settings;
  }

  /// The workbench in Cursor's layout, with the project's chats ([agents]).
  Future<IdeWorkspace> pumpCursor(
    WidgetTester tester, {
    Size size = const Size(1600, 900),
    bool agents = true,
    Widget? agentsBar,
    Map<String, Object?>? viewState,
    ValueChanged<Map<String, Object?>>? onViewState,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final settings = settingsWith('{"workbench.ide.layout": "cursor"}');
    final workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({inRoot('a.txt'): 'a'}),
    );
    addTearDown(() {
      workspace.dispose();
      tester.view.reset();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: IdeWorkbench(
          workspace: workspace,
          project: Project.at(testRoot),
          visible: true,
          chat: const SizedBox.expand(key: chatKey),
          agents:
              agentsBar ??
              (agents ? const SizedBox.expand(key: _agentsKey) : null),
          onBack: () {},
          commitMessage: _noModel,
          settings: settings,
          viewState: viewState,
          onViewState: onViewState,
          terminalBackend: TerminalBackend(
            launch: fakeTerminalLaunch,
            start: FakePty.starter([]),
            detectProfiles: fakeTerminalProfiles,
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return workspace;
  }

  group('CursorColumns', () {
    test('the chats give way first in a narrow window', () {
      double fit(double width, {bool sidebar = true}) => CursorColumns.fit(
        width,
        agents: 260,
        sidebar: sidebar,
        chat: true,
        editorHidden: false,
      );
      // 320 + 360 + 170 after them.
      expect(fit(1110), 260);
      expect(fit(1109), 0);
      // Without the side bar, less is needed after them.
      expect(fit(940, sidebar: false), 260);
      expect(
        CursorColumns.fit(
          2000,
          agents: null,
          sidebar: true,
          chat: true,
          editorHidden: false,
        ),
        0,
      );
      // Never narrower than their minimum.
      expect(
        CursorColumns.fit(
          2000,
          agents: 50,
          sidebar: true,
          chat: true,
          editorHidden: false,
        ),
        CursorLayoutService.minAgents,
      );
    });

    test('dragged, they follow the pointer, snapping shut past their '
        'minimum and stopping where the rest needs its room', () {
      expect(CursorColumns.drag(260, 40, 1600, after: 850), 300);
      expect(CursorColumns.drag(260, -70, 1600, after: 850), 200);
      expect(CursorColumns.drag(260, -100, 1600, after: 850), 0);
      expect(CursorColumns.drag(260, 900, 1600, after: 850), 750);
      // Shut, dragged out again.
      expect(CursorColumns.drag(0, 240, 1600, after: 850), 240);
      expect(CursorColumns.drag(0, 100, 1600, after: 850), 0);
    });
  });

  testWidgets('BaoCode\'s grid unless the setting says Cursor\'s, and the '
      'palette switches between them', (tester) async {
    final settings = settingsWith('{}');
    await pumpWorkbench(tester, {'a.txt': 'a'}, settings: settings);
    expect(find.byType(WorkbenchGrid), findsOneWidget);
    expect(find.byType(CursorWorkbenchGrid), findsNothing);

    tester
        .state<IdeWorkbenchState>(find.byType(IdeWorkbench))
        .commandsById[CursorLayoutContribution.toggleId]!
        .invoke();
    for (var i = 0; i < 100; i++) {
      if (find.byType(CursorWorkbenchGrid).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byType(CursorWorkbenchGrid), findsOneWidget);
    expect(find.byType(WorkbenchGrid), findsNothing);
  });

  testWidgets('left to right: the chats, the chat, the editor, the side bar '
      'under the views\' row; the status bar under all', (tester) async {
    await pumpCursor(tester);
    final agents = tester.getRect(_agents);
    final chat = tester.getRect(_chat);
    final editor = tester.getRect(_editor);
    final sidebar = tester.getRect(_sidebar);
    expect(agents.left, 0);
    expect(agents.width, CursorLayoutService.defaultAgents);
    expect(chat.left, agents.right);
    expect(chat.width, IdeColumns.defaultChat);
    expect(editor.left, chat.right);
    expect(sidebar.left, editor.right);
    expect(sidebar.right, 1600);
    expect(sidebar.width, IdeColumns.defaultSidebar);
    expect(find.byKey(_agentsKey), findsOneWidget);
    expect(find.byKey(chatKey), findsOneWidget);

    // The views' items in a row over the side bar.
    final bar = tester.getRect(_activityBar);
    expect(bar.left, sidebar.left);
    expect(bar.width, sidebar.width);
    expect(bar.top, sidebar.top);
    expect(bar.height, lessThan(60));

    final status = tester.getRect(find.byType(IdeStatusBar));
    expect(status.left, 0);
    expect(status.width, 1600);
    expect(status.bottom, 900);
    expect(chat.bottom, status.top);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without the chats given, no column for them', (tester) async {
    await pumpCursor(tester, agents: false);
    expect(_agents, findsNothing);
    expect(tester.getRect(_chat).left, 0);
  });

  testWidgets('in a narrow window the chats give way first, the side bar '
      'staying', (tester) async {
    await pumpCursor(tester, size: const Size(1000, 800));
    await tester.pump();
    expect(tester.getRect(_agents).width, 0);
    expect(tester.getRect(_sidebar).width, greaterThan(0));
    expect(tester.getRect(_chat).left, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sashes are mirrored: right grows the chat, left the side '
      'bar; the chats\' width is kept with the window', (tester) async {
    Map<String, Object?>? kept;
    await pumpCursor(tester, onViewState: (state) => kept = state);
    final chat = tester.getRect(_chat).width;
    await tester.drag(
      find.byKey(const ValueKey('ide-chat-sash')),
      const Offset(60, 0),
    );
    await tester.pump();
    expect(tester.getRect(_chat).width, chat + 60);

    final sidebar = tester.getRect(_sidebar).width;
    await tester.drag(
      find.byKey(const ValueKey('ide-sidebar-sash')),
      const Offset(-50, 0),
    );
    await tester.pump();
    expect(tester.getRect(_sidebar).width, sidebar + 50);

    await tester.drag(
      find.byKey(const ValueKey('ide-agents-sash')),
      const Offset(40, 0),
    );
    await tester.pump();
    expect(
      tester.getRect(_agents).width,
      CursorLayoutService.defaultAgents + 40,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(kept?[CursorLayoutService.agentsWidthKey], 300);
    // Shown, as by default: not written.
    expect(kept?.containsKey(CursorLayoutService.agentsKey), isFalse);

    // Dragged past their minimum, they snap shut, and are kept so.
    await tester.drag(
      find.byKey(const ValueKey('ide-agents-sash')),
      const Offset(-200, 0),
    );
    await tester.pump();
    expect(tester.getRect(_agents).width, 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(kept?[CursorLayoutService.agentsKey], isFalse);
    expect(kept?[CursorLayoutService.agentsWidthKey], 300);
  });

  testWidgets('the chats as the window was kept', (tester) async {
    await pumpCursor(
      tester,
      viewState: {CursorLayoutService.agentsWidthKey: 320},
    );
    expect(tester.getRect(_agents).width, 320);
  });

  testWidgets('the chat maximized has the editor\'s place, beside the '
      'chats', (tester) async {
    final workspace = await pumpCursor(tester);
    workspace.layout.resize(sidebar: false, chat: true, editorHidden: true);
    await tester.pump();
    await tester.pump();
    final chat = tester.getRect(find.byKey(chatKey));
    expect(chat.left, CursorLayoutService.defaultAgents);
    expect(chat.right, 1600);
    expect(_sidebar, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the title bar\'s toggles are on their parts\' sides', (
    tester,
  ) async {
    final workspace = await pumpCursor(tester);
    // The chat's on the left, the side bar's on the right.
    final chatToggle = find.byIcon(Codicons.layoutSidebarLeft);
    final sidebarToggle = find.byIcon(Codicons.layoutSidebarRight);
    expect(chatToggle, findsOneWidget);
    expect(sidebarToggle, findsOneWidget);
    expect(
      tester.getCenter(chatToggle).dx,
      lessThan(tester.getCenter(sidebarToggle).dx),
    );
    await tester.tap(chatToggle);
    await tester.pump();
    expect(workspace.layout.chat, isFalse);
    await tester.tap(sidebarToggle);
    await tester.pump();
    expect(workspace.layout.sidebar, isFalse);
  });

  testWidgets('the chats\' toggle in the title bar and the palette hide '
      'and show them', (tester) async {
    await pumpCursor(tester);
    final toggle = find.byKey(const ValueKey('cursor.agents.toggle'));
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.getRect(_agents).width, 0);
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.getRect(_agents).width, CursorLayoutService.defaultAgents);

    tester
        .state<IdeWorkbenchState>(find.byType(IdeWorkbench))
        .commandsById[CursorLayoutContribution.toggleAgentsId]!
        .invoke();
    await tester.pump();
    expect(tester.getRect(_agents).width, 0);
  });

  testWidgets('the project\'s chats: its agents only, by recency; one '
      'picked opens in the IDE\'s chat, a new one is made there, and the '
      'list folds away', (tester) async {
    final agentsWorkspace = Workspace.mock();
    final gateway = agentsWorkspace.threads
        .firstWhere((thread) => thread.title == 'Rate limit per API key')
        .project;
    final opened = <String>[];
    var made = 0;
    await pumpCursor(
      tester,
      agentsBar: IdeAgentsBar(
        workspace: agentsWorkspace,
        folder: gateway.path,
        project: gateway,
        onOpen: (thread) => opened.add(thread.title),
        onNew: () => made++,
      ),
    );
    final bar = find.byType(IdeAgentsBar);
    Finder inBar(Finder finder) => find.descendant(of: bar, matching: finder);
    expect(
      tester.widget<Sidebar>(inBar(find.byType(Sidebar))).grouping,
      SidebarGrouping.recent,
    );
    expect(inBar(find.text('Rate limit per API key')), findsOneWidget);
    expect(inBar(find.text('Optimize virtual list scrolling')), findsNothing);

    await tester.tap(inBar(find.text('Rate limit per API key')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opened, ['Rate limit per API key']);
    await tester.tap(inBar(find.text('New Chat')));
    await tester.pump();
    expect(made, 1);

    // Its own fold button, under the title bar.
    await tester.tap(inBar(find.byIcon(Codicons.layoutSidebarLeft)));
    await tester.pump();
    expect(tester.getRect(_agents).width, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<String> _noModel(
  IdeCommitMessagePrompt prompt, {
  Future<void>? cancel,
}) async => throw StateError('No commit message model in this test');
