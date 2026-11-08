// A plan's to-dos, as Cursor keeps them (docs/fork.md): in its front
// matter, `todos: [{id, content, status}]` beside `name` and `overview`,
// out of the text. A plan written before has them as lines
// `- [ ] [id] what` under its `## Задачи` (`## Tasks`, `## To-dos`): read
// as they are, and moved into the front matter the first time they are
// changed here. What runs them is told which ids, by the
// cursor-plan:todos command where the agent has it, else in the words
// Cursor sends.

import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

/// A to-do's status as the file keeps it: Cursor's.
enum PlanTodoState {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled');

  const PlanTodoState(this.value);

  /// As the front matter writes it.
  final String value;

  static PlanTodoState parse(Object? value) =>
      values.where((state) => state.value == value).firstOrNull ?? pending;

  /// Done with: completed, or cancelled.
  bool get closed => this == completed || this == cancelled;
}

/// Where a to-do is, as its plan's view shows it: [open], to be done;
/// [queued], sent to be done; [running], being done (the agent says so,
/// or the first sent while it works); [done]; [cancelled].
enum PlanTodoStatus { open, queued, running, done, cancelled }

/// A to-do: its [id], what it says, and its [state].
@immutable
class PlanTodo {
  const PlanTodo({required this.id, required this.text, required this.state});

  final String id;
  final String text;
  final PlanTodoState state;

  bool get done => state == PlanTodoState.completed;

  PlanTodo copyWith({String? text, PlanTodoState? state}) =>
      PlanTodo(id: id, text: text ?? this.text, state: state ?? this.state);

  @override
  bool operator ==(Object other) =>
      other is PlanTodo &&
      other.id == id &&
      other.text == text &&
      other.state == state;

  @override
  int get hashCode => Object.hash(id, text, state);

  @override
  String toString() => 'PlanTodo([$id] $text, ${state.value})';
}

/// Where a plan keeps its to-dos.
enum PlanTodosFormat {
  /// None: no front matter `todos`, no section of them.
  none,

  /// Cursor's: its front matter's `todos`.
  frontMatter,

  /// A `## Задачи` section of lines `- [ ] [id] what`, as plans were
  /// written before.
  section,
}

/// A plan's file read: its title (its first `# `, else its front matter's
/// `name`), its `overview`, and its to-dos where it keeps them.
@immutable
class PlanDoc {
  const PlanDoc._(
    this.source, {
    this.title,
    this.overview,
    this.todos = const [],
    this.format = PlanTodosFormat.none,
    this.frontMatter,
    this.section,
  });

  /// The file's text.
  final String source;
  final String? title;
  final String? overview;
  final List<PlanTodo> todos;
  final PlanTodosFormat format;

  /// Its front matter's lines, the `---`s within: `(first, last)`.
  final (int, int)? frontMatter;

  /// Its `## Задачи` section's lines, heading to last item: `(first,
  /// last)`.
  final (int, int)? section;

  bool get hasTodos => format != PlanTodosFormat.none;
  int get doneCount => todos.where((todo) => todo.done).length;
  List<PlanTodo> get open => [
    for (final todo in todos)
      if (todo.state == PlanTodoState.pending) todo,
  ];

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

  static List<String> _lines(String source) => [
    for (final line in source.split('\n'))
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
  ];

  /// [source] read. Headings and items inside fenced code are not; front
  /// matter YAML that does not read leaves the plan as though it had none.
  static PlanDoc parse(String source) {
    final lines = _lines(source);
    (int, int)? frontMatter;
    Map<Object?, Object?>? meta;
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      final end = lines.indexWhere((line) => line.trim() == '---', 1);
      if (end > 0) {
        frontMatter = (0, end);
        try {
          final yaml = loadYaml(lines.sublist(1, end).join('\n'));
          if (yaml is Map) meta = yaml;
        } on YamlException {
          meta = null;
        }
      }
    }
    String? title;
    (int, int)? section;
    var inSection = false;
    var fenced = false;
    final legacy = <PlanTodo>[];
    final start = frontMatter == null ? 0 : frontMatter.$2 + 1;
    for (var index = start; index < lines.length; index++) {
      final line = lines[index];
      if (_fence.hasMatch(line)) {
        fenced = !fenced;
        continue;
      }
      if (fenced) continue;
      if (_heading.hasMatch(line)) {
        if (_section.hasMatch(line.trim()) && section == null) {
          inSection = true;
          section = (index, index);
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
        legacy.add(
          PlanTodo(
            id: match[2]!,
            text: match[3]!,
            state: match[1] == ' '
                ? PlanTodoState.pending
                : PlanTodoState.completed,
          ),
        );
        section = (section!.$1, index);
      }
    }
    String? text(Object? value) => switch (value) {
      final String text when text.trim().isNotEmpty => text.trim(),
      _ => null,
    };
    final name = text(meta?['name']);
    final overview = text(meta?['overview']);
    if (meta?['todos'] case final YamlList list) {
      return PlanDoc._(
        source,
        title: title ?? name,
        overview: overview,
        format: PlanTodosFormat.frontMatter,
        frontMatter: frontMatter,
        todos: [
          for (final item in list)
            if (item is Map && text(item['id']) != null)
              PlanTodo(
                id: text(item['id'])!,
                text: text(item['content']) ?? '',
                state: PlanTodoState.parse(item['status']),
              ),
        ],
      );
    }
    return PlanDoc._(
      source,
      title: title ?? name,
      overview: overview,
      format: section == null ? PlanTodosFormat.none : PlanTodosFormat.section,
      frontMatter: frontMatter,
      section: section,
      todos: legacy,
    );
  }

  /// The plan with [todos] in its front matter, as Cursor keeps them (one
  /// made where it has none, named after its title): its `## Задачи`
  /// section gone, the rest of it as it was.
  String withTodos(List<PlanTodo> todos) {
    final lines = _lines(source);
    final ending = source.contains('\r\n') ? '\r\n' : '\n';
    final block = ['todos:', for (final todo in todos) ..._yamlTodo(todo)];
    if (section case (final first, final last)) {
      // The section and the blank lines after it.
      var end = last + 1;
      while (end < lines.length && lines[end].trim().isEmpty) {
        end++;
      }
      // At the end of the file, the blank lines before it too, the file
      // ending in a line break still.
      final atEnd = end == lines.length;
      var begin = first;
      if (atEnd) {
        while (begin > 0 && lines[begin - 1].trim().isEmpty) {
          begin--;
        }
      }
      lines.removeRange(begin, end);
      if (atEnd) lines.add('');
    }
    if (frontMatter case (final first, final last)) {
      final keys = lines.sublist(first + 1, last);
      final at = keys.indexWhere(
        (line) => RegExp(r'^todos\s*:').hasMatch(line),
      );
      if (at < 0) {
        keys.addAll(block);
      } else {
        var end = at + 1;
        while (end < keys.length &&
            (keys[end].trim().isEmpty ||
                keys[end].startsWith(' ') ||
                keys[end].startsWith('\t') ||
                keys[end].startsWith('-'))) {
          end++;
        }
        keys.replaceRange(at, end, block);
      }
      lines.replaceRange(first + 1, last, keys);
    } else {
      lines.insertAll(0, [
        '---',
        if (title case final title?) 'name: ${_yamlString(title)}',
        ...block,
        'isProject: false',
        '---',
        '',
      ]);
    }
    return lines.join(ending);
  }

  /// The plan with [id]'s state [state].
  String withState(String id, PlanTodoState state) => withTodos([
    for (final todo in todos)
      todo.id == id ? todo.copyWith(state: state) : todo,
  ]);

  /// The plan with a to-do saying [text] added at its end; its id made of
  /// its words, as no other's.
  String withAdded(String text) {
    final base = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final words = base.split('-').take(4).join('-');
    final stem = words.isEmpty ? 'todo' : words;
    final taken = {for (final todo in todos) todo.id};
    var id = stem;
    for (var n = 2; taken.contains(id); n++) {
      id = '$stem-$n';
    }
    return withTodos([
      ...todos,
      PlanTodo(id: id, text: text.trim(), state: PlanTodoState.pending),
    ]);
  }

  /// The plan without [ids]' to-dos.
  String withRemoved(Set<String> ids) => withTodos([
    for (final todo in todos)
      if (!ids.contains(todo.id)) todo,
  ]);

  static List<String> _yamlTodo(PlanTodo todo) => [
    '  - id: ${_yamlString(todo.id)}',
    '    content: ${_yamlString(todo.text)}',
    '    status: ${todo.state.value}',
  ];

  /// [text] as a YAML scalar: plain where that reads back the same, else
  /// double-quoted, as Cursor writes its contents.
  static String _yamlString(String text) {
    if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(text) &&
        !RegExp(r'^(true|false|null|yes|no|on|off|~|[0-9.eE+-]+)$')
            .hasMatch(text.toLowerCase())) {
      return text;
    }
    final escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }

  /// Each to-do's status: completed done, cancelled cancelled, in progress
  /// running; of the pending ones [sent] (their ids), the first is running
  /// while [streaming] and none is in progress, the others queued; the
  /// rest open.
  Map<PlanTodo, PlanTodoStatus> statuses({
    Set<String> sent = const {},
    bool streaming = false,
  }) {
    var running = todos.any((todo) => todo.state == PlanTodoState.inProgress);
    return {
      for (final todo in todos)
        todo: switch (todo.state) {
          PlanTodoState.completed => PlanTodoStatus.done,
          PlanTodoState.cancelled => PlanTodoStatus.cancelled,
          PlanTodoState.inProgress => PlanTodoStatus.running,
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

/// The message that has [todos] of the plan at [path] done.
abstract final class PlanRun {
  /// The skill that runs a plan's to-dos, where the agent has it.
  static const command = 'cursor-plan:todos';

  /// `/cursor-plan:todos id1 id2 <path>` where [hasCommand], else Cursor's
  /// words, the plan's path in them and how to mark each to-do as it goes
  /// ([format]: in the front matter, or its box in the section).
  static String message(
    List<PlanTodo> todos,
    String path, {
    required bool hasCommand,
    PlanTodosFormat format = PlanTodosFormat.frontMatter,
  }) {
    final ids = [for (final todo in todos) todo.id];
    if (hasCommand) return '/$command ${ids.join(' ')} $path';
    final n = todos.length;
    final marking = format == PlanTodosFormat.section
        ? 'tick each to-do as it is done: change its `- [ ]` to `- [x]`.'
        : "set each to-do's `status` in its front matter to `in_progress` "
              'as you start it and `completed` once it is done.';
    return [
      'Implement the following to-dos from the plan (the plan is attached '
          'for your reference). Do NOT edit the plan file itself, except to '
          '$marking',
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
