// A plan as Cursor shows it (docs/fork.md): its text, and under it, in the
// same scroll, its to-dos, "N To-dos": each with its status, run or
// changed from its menu, new ones added; several picked, built in a new
// agent. Its front matter is not shown as properties: the to-dos are its
// `todos`. Wherever a plan's file shows as markdown (the side panel's
// Plan page, the IDE's editor), the preview asks [PlanPreview] for these.
// The file is read again as it changes (the agent marks each to-do), and
// written as they are changed here.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../chat/chat_session.dart';
import '../chat/side_panel/file_open.dart';
import '../chat/widgets/hover_builder.dart';
import '../fork/fork_strings.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_input.dart';
import '../ide/ide_menu.dart';
import '../kernel/claude_code/claude_code_translator.dart';
import '../platform/data_dir.dart' show writeFileAtomically;
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import 'plan_sessions.dart';
import 'plan_todos.dart';
import 'todo_status_icons.dart';

/// What a plan's markdown preview has of its own.
abstract final class PlanPreview {
  /// Whether the file at [path] is a plan: Claude Code's (a `plans`
  /// folder), or Cursor's (`.plan.md`).
  static bool isPlan(String path) =>
      ClaudeTranslator.isPlanPath(path) || path.endsWith('.plan.md');

  /// Under its text: its to-dos.
  static Widget? footer(BuildContext context, String path) => isPlan(path)
      ? PlanTodosBlock(key: ValueKey(('plan.todos', path)), path: path)
      : null;

  /// In place of its front matter's properties: its overview, if it has
  /// one.
  static Widget? frontMatter(BuildContext context, String path, String yaml) =>
      isPlan(path) ? PlanFrontMatter(yaml: yaml) : null;
}

/// Where a plan shows: the conversation it was opened from (the side
/// panel's), or the IDE's folder; its to-dos run there.
class PlanContext extends InheritedWidget {
  const PlanContext({
    super.key,
    this.session,
    this.folder,
    this.projectRoot,
    this.onOpenPlan,
    required super.child,
  });

  final ChatSession? session;
  final String? folder;

  /// The project it is of, where Save to Project saves it; none, no Save.
  final String? projectRoot;

  /// Shows the plan at a path where this one shows (the copy saved).
  final ValueChanged<String>? onOpenPlan;

  static PlanContext? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlanContext>();

  @override
  bool updateShouldNotify(PlanContext oldWidget) =>
      session != oldWidget.session ||
      folder != oldWidget.folder ||
      projectRoot != oldWidget.projectRoot;
}

/// How plans' files are read and written: the disk's, by default.
abstract final class PlanFiles {
  static Future<String?> Function(String path) read = _read;
  static Future<void> Function(String path, String text) write = _write;

  /// When the file at [path] last changed, to read it again only then;
  /// null to read it each time (tests).
  static Future<DateTime?> Function(String path)? modified = _modified;

  static Future<String?> _read(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> _write(String path, String text) =>
      writeFileAtomically(File(path), text);

  static Future<DateTime?> _modified(String path) async {
    try {
      return await File(path).lastModified();
    } on FileSystemException {
      return null;
    }
  }

  /// The file at [path] as [change] leaves it, read anew first.
  static Future<String?> update(
    String path,
    String Function(PlanDoc doc) change,
  ) async {
    final text = await read(path);
    if (text == null) return null;
    final next = change(PlanDoc.parse(text));
    if (next != text) await write(path, next);
    return next;
  }

  /// Forgets what was sent of every plan.
  @visibleForTesting
  static void forgetSent() => _sent.clear();
}

/// The ids of a plan's to-dos sent to be done, by its path, and when: kept
/// as the view is built anew (a tab shown again).
final Map<String, ({Set<String> ids, DateTime at})> _sent = {};

/// Runs [todos] of the plan at [path] in [session]: by the cursor-plan
/// command where its agent has it, else in Cursor's words; noted as sent.
void runPlanTodos(
  ChatSession session,
  String path,
  List<PlanTodo> todos, {
  PlanTodosFormat format = PlanTodosFormat.frontMatter,
}) {
  if (todos.isEmpty || !session.canSend) return;
  final hasCommand = session.commands.any(
    (command) => command.name == PlanRun.command,
  );
  session.send(
    ComposerMessage(
      text: PlanRun.message(
        todos,
        path,
        hasCommand: hasCommand,
        format: format,
      ),
    ),
  );
  noteSent(path, [for (final todo in todos) todo.id]);
}

/// [ids] of the plan at [path] sent to be done.
void noteSent(String path, Iterable<String> ids) {
  final before = _sent[path]?.ids ?? const <String>{};
  _sent[path] = (ids: {...before, ...ids}, at: DateTime.now());
}

/// A plan's front matter: its overview, faint, over its text; nothing
/// else of it (its to-dos are under the text).
class PlanFrontMatter extends StatelessWidget {
  const PlanFrontMatter({super.key, required this.yaml});

  final String yaml;

  @override
  Widget build(BuildContext context) {
    String? overview;
    try {
      if (loadYaml(yaml) case final Map meta) {
        if (meta['overview'] case final String text when text.trim() != '') {
          overview = text.trim();
        }
      }
    } on YamlException {
      overview = null;
    }
    if (overview == null) return const SizedBox(width: double.infinity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        overview,
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 13,
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

/// A plan's to-dos, under its text: "N To-dos" and New; each to-do's
/// status, its words, Run and its menu on hover; picked by a click,
/// "N To-dos Selected" with Build in New Agent.
class PlanTodosBlock extends StatefulWidget {
  const PlanTodosBlock({super.key, required this.path});

  final String path;

  /// How often the file is looked at for a change.
  static Duration pollEvery = const Duration(seconds: 1);

  @override
  State<PlanTodosBlock> createState() => _PlanTodosBlockState();
}

class _PlanTodosBlockState extends State<PlanTodosBlock> {
  PlanDoc? _doc;
  DateTime? _modified;
  Timer? _poll;
  final Set<String> _selected = {};

  /// A new to-do being written, at the list's end.
  TextEditingController? _adding;

  /// How long to-dos just sent stay queued before the agent's turn starts.
  static const _settling = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(PlanTodosBlock.pollEvery, (_) => unawaited(_load()));
  }

  @override
  void didUpdateWidget(PlanTodosBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _modified = null;
      _selected.clear();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _adding?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final path = widget.path;
    if (PlanFiles.modified case final modified?) {
      final at = await modified(path);
      if (at != null && at == _modified) return;
      _modified = at;
    }
    final text = await PlanFiles.read(path);
    if (!mounted || path != widget.path) return;
    _show(text == null ? null : PlanDoc.parse(text));
  }

  void _show(PlanDoc? doc) {
    if (doc?.source == _doc?.source) return;
    setState(() {
      _doc = doc;
      _selected.removeWhere(
        (id) => !(doc?.open.any((todo) => todo.id == id) ?? false),
      );
    });
  }

  /// The file as [change] leaves it, shown at once.
  Future<void> _change(String Function(PlanDoc doc) change) async {
    final next = await PlanFiles.update(widget.path, change);
    if (!mounted || next == null) return;
    _modified = null;
    _show(PlanDoc.parse(next));
  }

  ChatSession? _session({bool create = false}) {
    final scope = PlanContext.maybeOf(context);
    return scope?.session ??
        PlanSessions.find(widget.path, folder: scope?.folder, create: create);
  }

  /// The ids sent while [session] works on them: none once it is idle.
  Set<String> _sentNow(ChatSession? session) {
    final sent = _sent[widget.path];
    if (sent == null) return const {};
    final busy =
        session != null && (session.isStreaming || session.queued.isNotEmpty);
    if (busy || DateTime.now().difference(sent.at) < _settling) {
      return sent.ids;
    }
    _sent.remove(widget.path);
    return const {};
  }

  void _run(List<PlanTodo> todos) {
    final session = _session(create: true);
    if (session == null) return;
    runPlanTodos(session, widget.path, todos, format: _doc!.format);
    setState(_selected.clear);
  }

  void _runInNewAgent(List<PlanTodo> todos) {
    final scope = PlanContext.maybeOf(context);
    final session = PlanSessions.newSession(widget.path, folder: scope?.folder);
    if (session == null) return;
    runPlanTodos(session, widget.path, todos, format: _doc!.format);
    setState(_selected.clear);
  }

  void _startAdding() => setState(() => _adding ??= TextEditingController());

  void _stopAdding() {
    final adding = _adding;
    setState(() => _adding = null);
    adding?.dispose();
  }

  void _add(String text) {
    _stopAdding();
    if (text.trim().isEmpty) return;
    unawaited(_change((doc) => doc.withAdded(text)));
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null || !doc.hasTodos) return const SizedBox.shrink();
    final session = _session();
    if (session == null) return _block(context, doc, null);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _block(context, doc, session),
    );
  }

  Widget _block(BuildContext context, PlanDoc doc, ChatSession? session) {
    final fork = context.fork;
    final statuses = doc.statuses(
      sent: _sentNow(session),
      streaming: session?.isStreaming ?? false,
    );
    final canRun =
        session?.canSend ??
        (PlanSessions.of != null && PlanContext.maybeOf(context) != null);
    final picked = [
      for (final todo in doc.todos)
        if (_selected.contains(todo.id)) todo,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    picked.isEmpty
                        ? fork.planTodosCount(doc.todos.length)
                        : fork.planTodosSelected(picked.length),
                    key: const ValueKey('plan.todos.heading'),
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                ),
                if (picked.isNotEmpty) ...[
                  IdeActionButton(
                    key: const ValueKey('plan.todos.unselect'),
                    icon: Codicons.close,
                    tooltip: fork.planUnselect,
                    onPressed: () => setState(_selected.clear),
                  ),
                  const SizedBox(width: 6),
                  _Button(
                    key: const ValueKey('plan.todos.buildNew'),
                    label: fork.planBuildInNewAgent,
                    onTap: PlanSessions.created == null
                        ? null
                        : () => _runInNewAgent(picked),
                  ),
                  const SizedBox(width: 6),
                ],
                _Button(
                  key: const ValueKey('plan.todos.new'),
                  icon: Codicons.add,
                  label: fork.planNew,
                  onTap: _startAdding,
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.only(top: 4, bottom: 6),
            color: AppColors.border,
          ),
          for (final MapEntry(key: todo, value: status) in statuses.entries)
            _TodoRow(
              key: ValueKey(('plan.todo', todo.id)),
              todo: todo,
              status: status,
              selected: _selected.contains(todo.id),
              dimmed: picked.isNotEmpty && !_selected.contains(todo.id),
              onToggle: status == PlanTodoStatus.open
                  ? () => setState(() {
                      if (!_selected.remove(todo.id)) _selected.add(todo.id);
                    })
                  : null,
              onRun: canRun && status == PlanTodoStatus.open
                  ? () => _run([todo])
                  : null,
              menu: () => [
                if (canRun && status == PlanTodoStatus.open)
                  IdeMenuAction(fork.planRun, onSelected: () => _run([todo])),
                if (PlanSessions.created != null &&
                    status == PlanTodoStatus.open)
                  IdeMenuAction(
                    fork.planBuildInNewAgent,
                    onSelected: () => _runInNewAgent([todo]),
                  ),
                const IdeMenuSeparator(),
                for (final state in PlanTodoState.values)
                  IdeMenuAction(
                    fork.planState(state),
                    icon: TodoStatusIcons.of(state),
                    checked: todo.state == state,
                    onSelected: () => unawaited(
                      _change((doc) => doc.withState(todo.id, state)),
                    ),
                  ),
                const IdeMenuSeparator(),
                IdeMenuAction(
                  fork.planDelete,
                  onSelected: () =>
                      unawaited(_change((doc) => doc.withRemoved({todo.id}))),
                ),
              ],
            ),
          if (_adding case final adding?)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 26),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): _stopAdding,
                },
                child: IdeInputBox(
                  key: const ValueKey('plan.todos.newInput'),
                  controller: adding,
                  placeholder: fork.planNewPlaceholder,
                  autofocus: true,
                  onSubmitted: _add,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A plain button of the block's heading: an icon, its label.
class _Button extends StatelessWidget {
  const _Button({super.key, this.icon, required this.label, this.onTap});

  final IconData? icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => HoverBuilder(
    cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
    builder: (context, hovered) => GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hovered && onTap != null ? AppColors.hover : AppColors.border,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final icon?) ...[
              Icon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? AppColors.textFaint : AppColors.text,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A to-do: its status (a check while picked), its words, struck through
/// once done or dropped; Run and its menu on hover, its menu on a right
/// click too. A click picks an open one.
class _TodoRow extends StatelessWidget {
  const _TodoRow({
    super.key,
    required this.todo,
    required this.status,
    required this.selected,
    required this.dimmed,
    required this.menu,
    this.onToggle,
    this.onRun,
  });

  final PlanTodo todo;
  final PlanTodoStatus status;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onToggle;
  final VoidCallback? onRun;
  final List<IdeMenuEntry> Function() menu;

  @override
  Widget build(BuildContext context) {
    final closed =
        status == PlanTodoStatus.done || status == PlanTodoStatus.cancelled;
    return HoverBuilder(
      cursor: onToggle == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        onSecondaryTapUp: (details) => unawaited(
          showIdeMenu(
            context,
            position: details.globalPosition,
            entries: menu(),
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: hovered ? AppColors.hover : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Center(
                  child: selected
                      ? Icon(
                          Codicons.check,
                          key: const ValueKey('plan.todo.picked'),
                          size: 16,
                          color: AppColors.text,
                        )
                      : _status(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    todo.text,
                    style: TextStyle(
                      color: closed || dimmed
                          ? AppColors.textFaint
                          : AppColors.text,
                      fontSize: 14,
                      height: 1.45,
                      decoration: closed ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.textFaint,
                    ),
                  ),
                ),
              ),
              if (hovered) ...[
                if (onRun case final run?)
                  IdeActionButton(
                    key: const ValueKey('plan.todo.run'),
                    icon: Codicons.play,
                    tooltip: context.fork.planRunHint,
                    onPressed: run,
                  ),
                IdeMenuButton(
                  key: const ValueKey('plan.todo.menu'),
                  icon: Codicons.ellipsis,
                  tooltip: context.fork.planMore,
                  entries: menu,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(BuildContext context) {
    final fork = context.fork;
    final (Widget icon, String? hint) = switch (status) {
      // As Cursor's (todo_status_icons.dart): outlines in the faint color.
      PlanTodoStatus.open => (TodoStatusIcons.pending(), null),
      PlanTodoStatus.queued => (
        Icon(Codicons.clock, size: 15, color: AppColors.textFaint),
        fork.planQueued,
      ),
      PlanTodoStatus.running => (
        TodoStatusIcons.inProgress(),
        fork.planRunning,
      ),
      PlanTodoStatus.done => (TodoStatusIcons.completed(), fork.planDone),
      PlanTodoStatus.cancelled => (
        TodoStatusIcons.cancelled(),
        fork.planCancelled,
      ),
    };
    return hint == null ? icon : IdeHover(message: hint, child: icon);
  }
}

/// [request] for a plan's file, opened from a link in the conversation, as
/// its plan's page opens it; any other as it is (its changes, or a file
/// asked for as a file).
FileOpenRequest planPageRequest(FileOpenRequest request) {
  if (request.plan ||
      request.diff ||
      request.agentChange ||
      !PlanPreview.isPlan(request.path)) {
    return request;
  }
  return FileOpenRequest(
    request.path,
    range: request.range,
    plan: true,
    local: request.local,
    readOnly: request.readOnly,
  );
}
