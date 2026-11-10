import 'dart:io';

import 'package:baocode/fork/project_switcher.dart';
import 'package:baocode/ide/git/commit_message.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_menu.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../ide/terminal/fake_pty.dart';
import '../ide/terminal/fake_terminal.dart';
import '../ide/workbench/fake_files.dart';

/// Switch Project: the IDE's projects in one list, the button in the title
/// bar of Cursor's layout and ⌃R there opening it.
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  test('those open first (the window in front first), then the recent '
      'ones; not the current one, none twice', () {
    expect(
      ProjectSwitcher.order(
        current: '/p/a',
        open: ['/p/b', '/p/a', '/p/c'],
        recent: ['/p/a', '/p/c', '/p/d', '/p/b/'],
      ),
      [
        (path: '/p/b', open: true),
        (path: '/p/c', open: true),
        (path: '/p/d', open: false),
      ],
    );
  });

  testWidgets('the pick: open and recent under their headings, the status '
      'said; one picked is opened', (tester) async {
    final opened = <String>[];
    late IdeQuickPick pick;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pick = ProjectSwitcher.pick(
              context,
              projects: [
                (path: '/p/b', open: true),
                (path: '/p/d', open: false),
              ],
              statusOf: (path) =>
                  path == '/p/b' ? ThreadStatus.running : ThreadStatus.idle,
              onOpen: opened.add,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    final entries = pick.items;
    expect(
      [
        for (final entry in entries)
          switch (entry) {
            IdeQuickPickSeparator(:final label) => '-- $label',
            IdeQuickPickItem(:final label) => label,
          },
      ],
      ['-- Open', 'b', '-- folders', 'd'],
    );
    final b = entries[1] as IdeQuickPickItem;
    expect(b.description, contains('/p'));
    expect(b.badge, isNotNull);
    expect((entries[3] as IdeQuickPickItem).badge, isNull);
    pick.onDidAccept!(b);
    expect(opened, ['/p/b']);
  });

  testWidgets('the dropdown: the current one ticked, open ones, recent '
      'ones, Open Folder…; one picked is opened', (tester) async {
    final opened = <String>[];
    var folder = 0;
    late List<IdeMenuEntry> entries;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            entries = ProjectSwitcher.menu(
              context,
              current: '/p/a',
              projects: [
                (path: '/p/b', open: true),
                (path: '/p/d', open: false),
              ],
              statusOf: (_) => ThreadStatus.idle,
              onOpen: opened.add,
              onOpenFolder: () => folder++,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      [
        for (final entry in entries)
          switch (entry) {
            IdeMenuSeparator() => '--',
            IdeMenuAction(:final label, :final checked) =>
              checked ? '✓ $label' : label,
          },
      ],
      ['✓ a', '--', 'b', '--', 'd', '--', 'Open Folder…'],
    );
    expect((entries.first as IdeMenuAction).onSelected, isNull);
    expect((entries[2] as IdeMenuAction).keybinding, '/p');
    (entries[4] as IdeMenuAction).onSelected!();
    (entries.last as IdeMenuAction).onSelected!();
    expect(opened, ['/p/d']);
    expect(folder, 1);
  });

  testWidgets('the project\'s button: its name, and where it is when '
      'pressed', (tester) async {
    Rect? at;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: ProjectSwitchButton(
              name: 'customs_ai',
              tooltip: 'switch',
              onPressed: (rect) => at = rect,
            ),
          ),
        ),
      ),
    );
    expect(find.text('customs_ai'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fork.switchProject')));
    expect(at, isNotNull);
    expect(
      at,
      tester.getRect(find.byKey(const ValueKey('fork.switchProject'))),
    );
  });

  group('in the IDE', () {
    UserSettings settingsWith(String json) {
      final temp = Directory.systemTemp.createTempSync('baocode-switcher');
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

    Future<List<String>> pump(
      WidgetTester tester, {
      required String layout,
    }) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      final settings = settingsWith('{"workbench.ide.layout": "$layout"}');
      final workspace = IdeWorkspace(
        testRoot,
        files: TreeFiles({inRoot('a.txt'): 'a'}),
      );
      addTearDown(() {
        workspace.dispose();
        tester.view.reset();
      });
      final ran = <String>[];
      IdeCommand command(String id) =>
          IdeCommand(id: id, label: id, run: () => ran.add(id));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: IdeWorkbench(
            workspace: workspace,
            project: Project.at(testRoot),
            visible: true,
            chat: const SizedBox.expand(),
            onBack: () {},
            commitMessage: _noModel,
            settings: settings,
            commands: [
              command('workbench.action.openRecent'),
              command(ProjectSwitcher.commandId),
            ],
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
      return ran;
    }

    Future<void> controlR(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('Cursor\'s layout: ⌃R opens it; the title bar is as it '
        'was, the project\'s name over its chats instead', (tester) async {
      final ran = await pump(tester, layout: 'cursor');
      expect(find.byKey(const ValueKey('fork.switchProject')), findsNothing);
      await controlR(tester);
      expect(ran, [ProjectSwitcher.commandId]);
    });

    testWidgets('VS Code\'s: no button, ⌃R is Open Recent', (tester) async {
      final ran = await pump(tester, layout: 'default');
      expect(find.byKey(const ValueKey('fork.switchProject')), findsNothing);
      await controlR(tester);
      expect(ran, ['workbench.action.openRecent']);
    });
  });
}

Future<String> _noModel(
  IdeCommitMessagePrompt prompt, {
  Future<void>? cancel,
}) async => throw StateError('No commit message model in this test');
