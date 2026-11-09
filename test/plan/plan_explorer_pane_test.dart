import 'dart:io';

import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/ide/ide_panes.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/plan/plan_explorer_pane.dart';
import 'package:baocode/plan/project_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The project's plans in the IDE's Explorer, under Cursor's look.
void main() {
  late Directory temp;
  late String root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('baocode-explorer-plans');
    root = p.join(temp.path, 'project');
    File(p.join(root, '.cursor', 'plans', 'roadmap_1234abcd.plan.md'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '---\nname: Roadmap\ntodos:\n  - id: a\n    content: A\n'
        '    status: completed\n  - id: b\n    content: B\n'
        '    status: pending\n---\n# Roadmap\n',
      );
  });
  tearDown(() {
    ChatLook.current.value = ChatLook.baocode;
    temp.deleteSync(recursive: true);
  });

  Future<List<IdePane>> panes(WidgetTester tester, String? root) async {
    late List<IdePane> panes;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            panes = PlanExplorerPane.of(
              context,
              WorkbenchServices(),
              root: root,
              active: null,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return panes;
  }

  testWidgets('none under BaoCode\'s look, nor for a folder not here', (
    tester,
  ) async {
    expect(await panes(tester, root), isEmpty);
    ChatLook.current.value = ChatLook.cursor;
    expect(await panes(tester, null), isEmpty);
    expect(await panes(tester, 'ssh://host/project'), isEmpty);
  });

  testWidgets('a pane "Plans" listing them, open from the start', (
    tester,
  ) async {
    ChatLook.current.value = ChatLook.cursor;
    final [pane] = await panes(tester, root);
    expect(pane.title, 'Plans');
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: IdePaneContainer(
            panes: [pane],
            expanded: {pane.id},
            onToggle: (_) {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 50 && find.text('Roadmap').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Roadmap'), findsOneWidget);
    expect(find.textContaining('1/2'), findsOneWidget);
    // Titled by the pane, not by the list again.
    expect(find.text('Plans'), findsOneWidget);
    expect(ProjectPlans.listed(root), isTrue);
  });
}
