// Build, as Cursor's plans have it (docs/fork.md): the model picked
// beside it; while the plan awaits the user, it starts the plan with its
// open to-dos to do; once started, it has the open ones done in the same
// conversation; its arrow builds them in a new agent instead. Where
// PlanStartBar shows for a plan's file (the side panel's Plan page, a
// plan's card), and over a plan in the IDE's editor.

import 'dart:async';

import 'package:flutter/material.dart';

import '../chat/chat_models.dart';
import '../chat/chat_session.dart';
import '../chat/composer/session_model_picker.dart';
import '../chat/panels/interaction_panel.dart' show PanelButton;
import '../fork/fork_strings.dart';
import '../ide/ide_menu.dart';
import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import 'plan_sessions.dart';
import 'plan_todos.dart';
import 'plan_view.dart';

class PlanBuildBar extends StatefulWidget {
  const PlanBuildBar({
    super.key,
    required this.path,
    this.session,
    this.folder,
    this.always = true,
    this.padding = EdgeInsets.zero,
    this.maxPickerWidth = 180,
  });

  final String path;

  /// The conversation the plan shows in; else [PlanSessions]' for
  /// [folder] (the IDE's), made as it builds.
  final ChatSession? session;
  final String? folder;

  /// Whether it shows once the plan is started, while it has open to-dos:
  /// not on a plan's card in the history, only while it awaits.
  final bool always;

  final EdgeInsets padding;
  final double maxPickerWidth;

  /// How often the file is looked at for a change.
  static Duration pollEvery = const Duration(seconds: 1);

  @override
  State<PlanBuildBar> createState() => _PlanBuildBarState();
}

class _PlanBuildBarState extends State<PlanBuildBar> {
  PlanDoc? _doc;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _poll = Timer.periodic(PlanBuildBar.pollEvery, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final text = await PlanFiles.read(widget.path);
    if (!mounted) return;
    final doc = text == null ? null : PlanDoc.parse(text);
    if (doc?.source == _doc?.source) return;
    setState(() => _doc = doc);
  }

  ChatSession? _session({bool create = false}) =>
      widget.session ??
      PlanSessions.find(widget.path, folder: widget.folder, create: create);

  /// Awaiting the user, starts the plan with its open to-dos to do (as
  /// it was last read), else as BaoCode starts it; started, has them done.
  void _build({required String startMessage}) {
    final doc = _doc;
    final session = _session(create: true);
    if (session == null) return;
    final open = doc?.open ?? const <PlanTodo>[];
    if (session.awaitingPlan?.path == widget.path) {
      if (!session.canStartPlan) return;
      if (doc == null || open.isEmpty) return session.startPlan(startMessage);
      final hasCommand = session.commands.any(
        (command) => command.name == PlanRun.command,
      );
      session.startPlan(
        PlanRun.message(
          open,
          widget.path,
          hasCommand: hasCommand,
          format: doc.format,
        ),
      );
      noteSent(widget.path, [for (final todo in open) todo.id]);
      return;
    }
    if (doc == null) return;
    runPlanTodos(session, widget.path, open, format: doc.format);
  }

  void _buildInNewAgent() {
    final doc = _doc;
    if (doc == null || doc.open.isEmpty) return;
    final session = PlanSessions.newSession(widget.path, folder: widget.folder);
    if (session == null) return;
    runPlanTodos(session, widget.path, doc.open, format: doc.format);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session();
    if (session == null) return _bar(context, null);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _bar(context, session),
    );
  }

  Widget _bar(BuildContext context, ChatSession? session) {
    final l10n = context.l10n;
    final fork = context.fork;
    final awaiting = session?.awaitingPlan?.path == widget.path;
    final open = _doc?.open ?? const <PlanTodo>[];
    if (!awaiting && (!widget.always || open.isEmpty)) {
      return const SizedBox.shrink();
    }
    final canBuild = awaiting
        ? session!.canStartPlan
        : session?.canSend ??
              (PlanSessions.of != null && widget.folder != null);
    return Padding(
      padding: widget.padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session != null) ...[
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxPickerWidth),
              child: SessionModelPicker(session: session),
            ),
            const SizedBox(width: 6),
          ],
          PanelButton(
            key: const ValueKey('plan.build'),
            // Awaiting the user, BaoCode's Start (which builds now too).
            label: awaiting ? l10n.planStart : fork.planBuild,
            tooltip: awaiting ? l10n.planStartHint : fork.planBuildHint,
            primary: true,
            onTap: canBuild
                ? () => _build(startMessage: l10n.planStartMessage)
                : null,
          ),
          if (open.isNotEmpty && PlanSessions.created != null)
            IdeMenuButton(
              key: const ValueKey('plan.build.more'),
              icon: Codicons.chevronDown,
              tooltip: fork.planMore,
              entries: () => [
                IdeMenuAction(
                  fork.planBuildInNewAgent,
                  onSelected: _buildInNewAgent,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Whether [item] is the last card of its plan's file in [session]'s
/// conversation: a plan sent back still shows whole there, its to-dos to
/// build.
bool isLatestPlanCard(ChatSession session, PlanItem item) {
  if (item.path.isEmpty) return false;
  for (var i = session.itemCount - 1; i >= 0; i--) {
    if (session.itemAt(i) case final PlanItem plan
        when plan.path == item.path) {
      return identical(plan, item) || plan.round == item.round;
    }
  }
  return false;
}
