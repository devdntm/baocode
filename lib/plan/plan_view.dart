// A plan as Cursor shows it (docs/fork.md): its title and how many of its
// to-dos are done, Build while it awaits the user (PlanStartBar), Run all
// once started; its to-dos, each run on its own or several picked; the
// plan itself under them, as what shows it has it (the IDE's markdown
// preview, the side panel's file). The file is read again as it changes:
// the agent ticks each to-do done there.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../chat/chat_session.dart';
import '../chat/panels/interaction_panel.dart' show PanelButton;
import '../chat/widgets/hover_builder.dart';
import '../chat/widgets/plan_start.dart';
import '../chat/widgets/tool_call_row.dart'
    show todoDoingIcon, todoDoneIcon, todoOpenIcon;
import '../fork/fork_strings.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_spinning.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'plan_sessions.dart';
import 'plan_todos.dart';

class PlanView extends StatefulWidget {
  const PlanView({
    super.key,
    required this.path,
    required this.body,
    this.session,
    this.folder,
    this.showBuild = false,
    this.read,
  });

  /// The plan's file, on this machine.
  final String path;

  /// The plan itself, under its to-dos.
  final Widget body;

  /// The conversation its to-dos run in; by default [PlanSessions]' (the
  /// one that wrote it, else [folder]'s IDE chat).
  final ChatSession? session;
  final String? folder;

  /// Whether Build is in its header, where what is under it has none.
  final bool showBuild;

  /// Reads the file, null where there is none; by default from the disk.
  final Future<String?> Function(String path)? read;

  /// How often the file is looked at for a change.
  static Duration pollEvery = const Duration(seconds: 1);

  /// Forgets what was sent of every plan.
  @visibleForTesting
  static void forgetSent() => _sent.clear();

  @override
  State<PlanView> createState() => _PlanViewState();
}

/// The ids of a plan's to-dos sent to be done, by its path, and when: kept
/// as the view is built anew (a tab shown again).
final Map<String, ({Set<String> ids, DateTime at})> _sent = {};

class _PlanViewState extends State<PlanView> {
  PlanTodos _todos = const PlanTodos();
  DateTime? _modified;
  Timer? _poll;
  final Set<String> _selected = {};

  /// How long to-dos just sent stay queued before the agent's turn starts.
  static const _settling = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(PlanView.pollEvery, (_) => unawaited(_load()));
  }

  @override
  void didUpdateWidget(PlanView oldWidget) {
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
    super.dispose();
  }

  Future<void> _load() async {
    final path = widget.path;
    final String? text;
    if (widget.read case final read?) {
      text = await read(path);
    } else {
      final file = File(path);
      try {
        final modified = await file.lastModified();
        if (modified == _modified) return;
        _modified = modified;
        text = await file.readAsString();
      } on FileSystemException {
        _modified = null;
        if (mounted && _todos.hasSection) {
          setState(() => _todos = const PlanTodos());
        }
        return;
      }
    }
    if (!mounted || path != widget.path) return;
    final todos = text == null ? const PlanTodos() : PlanTodos.parse(text);
    if (_same(todos, _todos)) return;
    setState(() {
      _todos = todos;
      _selected.removeWhere((id) => !todos.open.any((todo) => todo.id == id));
    });
  }

  static bool _same(PlanTodos a, PlanTodos b) =>
      a.title == b.title &&
      a.hasSection == b.hasSection &&
      a.todos.length == b.todos.length &&
      [for (var i = 0; i < a.todos.length; i++) a.todos[i] == b.todos[i]]
          .every((same) => same);

  ChatSession? _session({bool create = false}) =>
      widget.session ??
      PlanSessions.find(widget.path, folder: widget.folder, create: create);

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
    if (todos.isEmpty) return;
    final session = _session(create: true);
    if (session == null || !session.canSend) return;
    final hasCommand = session.commands.any(
      (command) => command.name == PlanRun.command,
    );
    session.send(
      ComposerMessage(
        text: PlanRun.message(todos, widget.path, hasCommand: hasCommand),
      ),
    );
    final before = _sent[widget.path]?.ids ?? const <String>{};
    _sent[widget.path] = (
      ids: {...before, for (final todo in todos) todo.id},
      at: DateTime.now(),
    );
    setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session();
    if (session == null) return _view(context, null);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _view(context, session),
    );
  }

  Widget _view(BuildContext context, ChatSession? session) {
    final todos = _todos;
    final awaiting = session?.awaitingPlan?.path == widget.path;
    final showBuild = widget.showBuild && session != null && awaiting;
    if (!todos.hasSection && !showBuild) return widget.body;
    final statuses = todos.statuses(
      sent: _sentNow(session),
      streaming: session?.isStreaming ?? false,
    );
    // Run where a conversation is, or can be made (the IDE's chat).
    final canRun =
        !awaiting &&
        (session?.canSend ??
            (PlanSessions.of != null && widget.folder != null));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, session, todos, statuses, canRun, showBuild),
        if (todos.todos.isNotEmpty) _list(context, statuses, canRun),
        Container(height: 1, color: AppColors.border),
        Expanded(child: widget.body),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    ChatSession? session,
    PlanTodos todos,
    Map<PlanTodo, PlanTodoStatus> statuses,
    bool canRun,
    bool showBuild,
  ) {
    final fork = context.fork;
    final open = [
      for (final MapEntry(key: todo, value: status) in statuses.entries)
        if (status == PlanTodoStatus.open) todo,
    ];
    final selected = [
      for (final todo in open)
        if (_selected.contains(todo.id)) todo,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
      child: Row(
        children: [
          Icon(Codicons.checklist, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              todos.title ?? fork.planTodos,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (todos.todos.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              fork.planProgress(todos.doneCount, todos.todos.length),
              key: const ValueKey('plan.progress'),
              style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
            ),
          ],
          const Spacer(),
          if (showBuild && session != null)
            PlanStartBar(
              session: session,
              path: widget.path,
              maxPickerWidth: 180,
              padding: const EdgeInsets.only(left: 6),
            )
          else if (canRun && selected.isNotEmpty)
            PanelButton(
              key: const ValueKey('plan.runSelected'),
              label: fork.planRunSelected(selected.length),
              primary: true,
              onTap: () => _run(selected),
            )
          else if (canRun && open.isNotEmpty)
            PanelButton(
              key: const ValueKey('plan.runAll'),
              label: fork.planRunAll,
              primary: true,
              onTap: () => _run(open),
            ),
        ],
      ),
    );
  }

  /// The to-dos, as the agent's to-do list shows them; at most a third of
  /// the room, scrolled past that.
  Widget _list(
    BuildContext context,
    Map<PlanTodo, PlanTodoStatus> statuses,
    bool canRun,
  ) => LayoutBuilder(
    builder: (context, constraints) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: constraints.maxHeight.isFinite
            ? constraints.maxHeight / 3
            : 240,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        children: [
          for (final MapEntry(key: todo, value: status) in statuses.entries)
            _TodoRow(
              key: ValueKey(('plan.todo', todo.id)),
              todo: todo,
              status: status,
              selecting: _selected.isNotEmpty,
              selected: _selected.contains(todo.id),
              onSelect: canRun && status == PlanTodoStatus.open
                  ? () => setState(() {
                      if (!_selected.remove(todo.id)) _selected.add(todo.id);
                    })
                  : null,
              onRun: canRun && status == PlanTodoStatus.open
                  ? () => _run([todo])
                  : null,
            ),
        ],
      ),
    ),
  );
}

/// A to-do: its status (a box to pick it by, hovered or while some are
/// picked), its id and words; Run on hover.
class _TodoRow extends StatelessWidget {
  const _TodoRow({
    super.key,
    required this.todo,
    required this.status,
    required this.selecting,
    required this.selected,
    this.onSelect,
    this.onRun,
  });

  final PlanTodo todo;
  final PlanTodoStatus status;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onRun;

  @override
  Widget build(BuildContext context) {
    final fork = context.fork;
    final done = status == PlanTodoStatus.done;
    return HoverBuilder(
      builder: (context, hovered) => Container(
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: hovered || selected ? AppColors.hover : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: (hovered || selecting) && onSelect != null
                  ? IdeActionButton(
                      key: const ValueKey('plan.todo.select'),
                      icon: selected
                          ? Codicons.passFilled
                          : Codicons.circleLargeOutline,
                      color: selected ? themeColors['charts.blue'] : null,
                      size: 18,
                      iconSize: 14,
                      tooltip: fork.planSelect,
                      onPressed: onSelect!,
                    )
                  : switch (status) {
                      PlanTodoStatus.open => Center(child: _icon()),
                      _ => IdeHover(
                        message: switch (status) {
                          PlanTodoStatus.queued => fork.planQueued,
                          PlanTodoStatus.running => fork.planRunning,
                          _ => fork.planDone,
                        },
                        child: Center(child: _icon()),
                      ),
                    },
            ),
            const SizedBox(width: 6),
            Text(
              todo.id,
              style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                todo.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: done ? AppColors.textFaint : AppColors.text,
                  fontSize: 12.5,
                  height: 1.5,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.textFaint,
                ),
              ),
            ),
            if (hovered && onRun != null)
              IdeActionButton(
                key: const ValueKey('plan.todo.run'),
                icon: Codicons.play,
                size: 20,
                iconSize: 14,
                tooltip: fork.planRunHint,
                onPressed: onRun!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _icon() {
    final (icon, color) = switch (status) {
      PlanTodoStatus.done => (todoDoneIcon, themeColors['charts.green']),
      PlanTodoStatus.running => (todoDoingIcon, themeColors['charts.blue']),
      PlanTodoStatus.queued => (todoDoingIcon, AppColors.textFaint),
      PlanTodoStatus.open => (todoOpenIcon, AppColors.textMuted),
    };
    final svg = SvgPicture.asset(
      icon,
      width: 14,
      height: 14,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
    return status == PlanTodoStatus.running ? IdeSpinning(svg) : svg;
  }
}
