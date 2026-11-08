import 'dart:io';

import 'package:bao_agent/bao_agent.dart' show AgentPaths;
import 'package:baocode/plan/plan_todos.dart';
import 'package:baocode/plan/project_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A project's plans: those saved in its .cursor/plans, and those its
/// conversations wrote in ~/.claude/plans; Save to Project.
void main() {
  late Directory temp;
  late String root;
  late String home;
  late String oldHome;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('baocode-project-plans');
    root = p.join(temp.path, 'project');
    home = p.join(temp.path, 'home');
    Directory(root).createSync(recursive: true);
    oldHome = ProjectPlans.home;
    ProjectPlans.home = home;
  });
  tearDown(() {
    ProjectPlans.home = oldHome;
    temp.deleteSync(recursive: true);
  });

  File write(String path, String text, {DateTime? at}) {
    final file = File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
    if (at != null) file.setLastModifiedSync(at);
    return file;
  }

  String claudePlan(String name) => p.join(home, '.claude', 'plans', name);

  test('saved ones and those its conversations wrote, the newest first; '
      'none gone, none of another project', () async {
    write(
      p.join(root, '.cursor', 'plans', 'roadmap_1234abcd.plan.md'),
      '---\nname: Roadmap\ntodos:\n  - id: a\n    content: A\n'
      '    status: completed\n  - id: b\n    content: B\n'
      '    status: pending\n---\n# Roadmap\n',
      at: DateTime(2026, 11, 1),
    );
    write(
      claudePlan('quiet-river.md'),
      '# Quiet river\n\n## Задачи\n\n- [ ] [x] X\n',
      at: DateTime(2026, 11, 5),
    );
    write(claudePlan('elsewhere.md'), '# Another project\n');
    final transcripts = p.join(
      home,
      '.claude',
      'projects',
      AgentPaths.projectDirName(root),
    );
    write(
      p.join(transcripts, 's1.jsonl'),
      '{"tool_use":{"input":{"file_path":"${claudePlan('quiet-river.md')}"}}}\n'
      '{"text":"see ${claudePlan('gone.md')}"}\n',
    );

    final plans = await ProjectPlans.of(root);
    expect([for (final plan in plans) plan.title], ['Quiet river', 'Roadmap']);
    expect((plans[1].done, plans[1].total), (1, 2));
    expect((plans[0].done, plans[0].total), (0, 1));

    // A transcript changed is read again.
    write(
      p.join(transcripts, 's1.jsonl'),
      '{"file_path":"${claudePlan('elsewhere.md')}"}\n',
    );
    expect([
      for (final plan in await ProjectPlans.of(root)) plan.title,
    ], containsAll(['Another project', 'Roadmap']));
    expect(await ProjectPlans.of('ssh://host/p'), isEmpty);
  });

  test('Save to Project: a copy in .cursor/plans, its to-dos in its front '
      'matter, the same file again for the same plan', () async {
    final plan = write(
      claudePlan('quiet-river.md'),
      '# Quiet river: the plan\n\nText.\n\n## Задачи\n\n- [x] [a] A\n'
      '- [ ] [b] B\n',
    ).path;
    final saved = await ProjectPlans.saveToProject(plan, root);
    expect(p.dirname(saved), p.join(root, '.cursor', 'plans'));
    expect(
      p.basename(saved),
      matches(RegExp(r'^quiet_river_the_plan_[0-9a-f]{8}\.plan\.md$')),
    );
    final doc = PlanDoc.parse(File(saved).readAsStringSync());
    expect(doc.format, PlanTodosFormat.frontMatter);
    expect(
      [for (final todo in doc.todos) todo.state],
      [PlanTodoState.completed, PlanTodoState.pending],
    );
    expect(File(plan).readAsStringSync(), contains('## Задачи'));
    expect(await ProjectPlans.saveToProject(plan, root), saved);
    expect(ProjectPlans.isSavedIn(saved, root), isTrue);
    expect(await ProjectPlans.saveToProject(saved, root), saved);
  });

  testWidgets('the page: the plans at its left, one picked opens; a word '
      'where none is open', (tester) async {
    final plan = write(claudePlan('quiet-river.md'), '# Quiet river\n').path;
    write(
      p.join(
        home,
        '.claude',
        'projects',
        AgentPaths.projectDirName(root),
        's.jsonl',
      ),
      '"$plan"\n',
    );
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: ProjectPlansPage(
            root: root,
            current: null,
            onOpen: opened.add,
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 50 && find.text('Quiet river').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Quiet river'), findsOneWidget);
    expect(find.textContaining('Pick a plan at the left'), findsOneWidget);
    await tester.tap(find.text('Quiet river'));
    expect(opened, [plan]);
  });
}
