// A plan's to-dos, as Cursor's plans have them (docs/fork.md): the lines
// `- [ ] [id] what` under its `## Tasks` (`## Задачи`, `## To-dos`), each
// ticked `- [x]` in the file once done. What runs them is told which ids,
// by the cursor-plan:todos command where the agent has it, else in the
// words Cursor sends.

import 'package:flutter/foundation.dart';

/// Where a to-do is: [open]; [queued], sent to be done; [running], the
/// first of those sent not done yet while the agent works; [done], ticked
/// in the file.
enum PlanTodoStatus { open, queued, running, done }

/// A to-do: its [id] (`[id]`), what it says, whether it is ticked, and its
/// [line] in the file (from 0).
@immutable
class PlanTodo {
  const PlanTodo({
    required this.id,
    required this.text,
    required this.done,
    required this.line,
  });

  final String id;
  final String text;
  final bool done;
  final int line;

  @override
  bool operator ==(Object other) =>
      other is PlanTodo &&
      other.id == id &&
      other.text == text &&
      other.done == done &&
      other.line == line;

  @override
  int get hashCode => Object.hash(id, text, done, line);

  @override
  String toString() => 'PlanTodo([$id] $text${done ? ', done' : ''})';
}

/// What a plan's file says of itself: its title (its first `# `), and its
/// to-dos, where it has a section of them ([hasSection]).
@immutable
class PlanTodos {
  const PlanTodos({this.title, this.todos = const [], this.hasSection = false});

  final String? title;
  final List<PlanTodo> todos;
  final bool hasSection;

  int get doneCount => todos.where((todo) => todo.done).length;
  List<PlanTodo> get open => [
    for (final todo in todos)
      if (!todo.done) todo,
  ];

  /// The section's headings, as the cursor-plan rules write them.
  static final _section = RegExp(
    r'^##\s+(задачи|tasks|to-?dos)\s*:?\s*$',
    caseSensitive: false,
    unicode: true,
  );
  static final _title = RegExp(r'^#\s+(.+?)\s*#*\s*$');
  static final _heading = RegExp(r'^#{1,2}\s');
  static final _fence = RegExp(r'^\s*(```|~~~)');
  static final _item = RegExp(
    r'^\s*[-*+]\s+\[([ xX])\]\s+\[([^\]\s]+)\]\s+(.*?)\s*$',
  );

  /// [source] read: headings and items inside fenced code are not.
  static PlanTodos parse(String source) {
    final lines = source.split('\n');
    String? title;
    var inSection = false;
    var hasSection = false;
    var fenced = false;
    final todos = <PlanTodo>[];
    for (final (index, raw) in lines.indexed) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (_fence.hasMatch(line)) {
        fenced = !fenced;
        continue;
      }
      if (fenced) continue;
      if (_heading.hasMatch(line)) {
        if (_section.hasMatch(line.trim())) {
          inSection = hasSection = true;
          continue;
        }
        inSection = false;
        if (title == null) {
          if (_title.firstMatch(line) case final match?) title = match[1];
        }
        continue;
      }
      if (!inSection) continue;
      if (_item.firstMatch(line) case final match?) {
        todos.add(
          PlanTodo(
            id: match[2]!,
            text: match[3]!,
            done: match[1] != ' ',
            line: index,
          ),
        );
      }
    }
    return PlanTodos(title: title, todos: todos, hasSection: hasSection);
  }

  /// Each to-do's status: done where ticked; of those in [sent] (their
  /// ids), the first not done is running while [streaming], the others
  /// queued; the rest open.
  Map<PlanTodo, PlanTodoStatus> statuses({
    Set<String> sent = const {},
    bool streaming = false,
  }) {
    var running = false;
    return {
      for (final todo in todos)
        todo: switch (todo) {
          PlanTodo(done: true) => PlanTodoStatus.done,
          _ when sent.contains(todo.id) && streaming && !running => () {
            running = true;
            return PlanTodoStatus.running;
          }(),
          _ when sent.contains(todo.id) => PlanTodoStatus.queued,
          _ => PlanTodoStatus.open,
        },
    };
  }
}

final _box = RegExp(r'^(\s*[-*+]\s+\[)[ xX]\]\s+\[([^\]\s]+)\]');

/// [source] with [todo]'s box ticked ([done]) or not; as it was where its
/// line is not that to-do's any more.
String setPlanTodoDone(String source, PlanTodo todo, {required bool done}) {
  final lines = source.split('\n');
  if (todo.line >= lines.length) return source;
  final line = lines[todo.line];
  final match = _box.firstMatch(line);
  if (match == null || match[2] != todo.id) return source;
  // The box's mark, after its `- [`.
  final at = match[1]!.length;
  lines[todo.line] = line.replaceRange(at, at + 1, done ? 'x' : ' ');
  return lines.join('\n');
}

/// The message that has [todos] of the plan at [path] done.
abstract final class PlanRun {
  /// The skill that runs a plan's to-dos, where the agent has it.
  static const command = 'cursor-plan:todos';

  /// `/cursor-plan:todos id1 id2 <path>` where [hasCommand], else Cursor's
  /// words, the plan's path in them and its boxes to tick as each is done
  /// (Cursor ticks its own list; here the file is the list).
  static String message(
    List<PlanTodo> todos,
    String path, {
    required bool hasCommand,
  }) {
    final ids = [for (final todo in todos) todo.id];
    if (hasCommand) return '/$command ${ids.join(' ')} $path';
    final n = todos.length;
    return [
      'Implement the following to-dos from the plan (the plan is attached '
          'for your reference). Do NOT edit the plan file itself, except to '
          'tick each to-do as it is done: change its `- [ ]` to `- [x]`.',
      '',
      'The plan: $path',
      '',
      'You have been assigned the following $n to-do${n == 1 ? '' : 's'} '
          'with IDs: ${ids.join(', ')}',
      '',
      for (final (index, todo) in todos.indexed)
        '${index + 1}. [${todo.id}] ${todo.text}',
      '',
      'These to-dos have already been created. Do not create them again. '
          'Mark them as in_progress as you work, starting with the first one. '
          "Don't stop until you have completed all the assigned to-dos.",
    ].join('\n');
  }
}
