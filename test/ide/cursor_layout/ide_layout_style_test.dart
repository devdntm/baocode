import 'dart:io';

import 'package:baocode/ide/cursor_layout/ide_layout_style.dart';
import 'package:baocode/ide/cursor_layout/layout_contribution.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/settings/pages/general_page.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../workbench/fake_files.dart';

/// `workbench.ide.layout`: BaoCode's grid unless settings.json says
/// Cursor's, chosen in Settings → General or switched from the palette.
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  UserSettings settingsIn(Directory temp, [String json = '{}\n']) {
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

  Directory tempDir() {
    final temp = Directory.systemTemp.createTempSync('baocode-ide-layout');
    addTearDown(() => temp.deleteSync(recursive: true));
    return temp;
  }

  /// Waits for [settings] to have [key] as [value], written and read back.
  Future<void> until(
    WidgetTester tester,
    UserSettings settings,
    String key,
    Object? value,
  ) async {
    for (var i = 0; i < 100 && settings[key] != value; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(settings[key], value);
  }

  test('unset or unknown is the default; cursor is Cursor\'s', () {
    expect(IdeLayoutStyle.parse(null), IdeLayoutStyle.standard);
    expect(IdeLayoutStyle.parse('grid'), IdeLayoutStyle.standard);
    expect(IdeLayoutStyle.parse(3), IdeLayoutStyle.standard);
    expect(IdeLayoutStyle.parse('default'), IdeLayoutStyle.standard);
    expect(IdeLayoutStyle.parse('cursor'), IdeLayoutStyle.cursor);
    expect(IdeLayoutStyle.of(null), IdeLayoutStyle.standard);
  });

  test('the default is not written', () async {
    final settings = settingsIn(tempDir(), '{\n  // mine\n}\n');
    await IdeLayoutStyle.select(settings, IdeLayoutStyle.cursor);
    expect(settings[IdeLayoutStyle.settingKey], 'cursor');
    expect(File(settings.path).readAsStringSync(), contains('// mine'));
    await IdeLayoutStyle.select(settings, IdeLayoutStyle.standard);
    expect(settings[IdeLayoutStyle.settingKey], isNull);
    expect(
      File(settings.path).readAsStringSync(),
      isNot(contains(IdeLayoutStyle.settingKey)),
    );
  });

  testWidgets('Toggle Cursor Layout switches the setting both ways', (
    tester,
  ) async {
    final settings = settingsIn(tempDir());
    await pumpWorkbench(tester, {'a.txt': 'a'}, settings: settings);
    final state = tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));
    final toggle = state.commandsById[CursorLayoutContribution.toggleId]!;
    expect(toggle.label, contains('Toggle Cursor Layout'));

    toggle.invoke();
    await until(tester, settings, IdeLayoutStyle.settingKey, 'cursor');
    toggle.invoke();
    await until(tester, settings, IdeLayoutStyle.settingKey, null);
  });

  testWidgets('Settings → General shows it and writes the choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = settingsIn(tempDir());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GeneralSettingsPage(settings: settings)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('IDE layout'), findsOneWidget);
    expect(find.text('BaoCode'), findsWidgets);

    // The row's dropdown, its current choice shown.
    final row = find.ancestor(
      of: find.text('IDE layout'),
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'SettingsRow',
      ),
    );
    await tester.tap(
      find.descendant(of: row.first, matching: find.text('BaoCode')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cursor').last);
    await until(tester, settings, IdeLayoutStyle.settingKey, 'cursor');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: row.first, matching: find.text('Cursor')),
      findsOneWidget,
    );
  });
}
