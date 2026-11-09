// A project's plans (docs/fork.md): those saved in it, as Cursor keeps
// them (`.cursor/plans/*.plan.md`), and those its conversations wrote in
// `~/.claude/plans` (named in their transcripts); the side panel's Plan
// page lists them beside the one open. Save to Project copies a plan into
// `.cursor/plans`, its to-dos in its front matter.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bao_agent/bao_agent.dart' show AgentPaths;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../chat/widgets/hover_builder.dart';
import '../fork/fork_strings.dart';
import '../l10n/l10n.dart';
import '../platform/data_dir.dart' show writeFileAtomically;
import '../remote/remote_location.dart';
import '../sidebar/sidebar.dart' show relativeTime;
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import 'plan_todos.dart';

/// A project's plan: its file, its title, how many of its to-dos are
/// done of how many, when it last changed.
typedef ProjectPlan = ({
  String path,
  String title,
  int done,
  int total,
  DateTime modified,
});

abstract final class ProjectPlans {
  /// The user's home, where `~/.claude` is.
  static String home = Platform.environment['HOME'] ?? '';

  /// Whether the project at [root] has its plans listed: one on this
  /// machine.
  static bool listed(String? root) =>
      root != null && root.isNotEmpty && !RemoteLocation.isRemote(root);

  /// Where the project at [root] keeps the plans saved to it.
  static String folderIn(String root) => p.join(root, '.cursor', 'plans');

  /// The plans its transcripts name, by transcript: read again only once
  /// one changes (its size or time).
  static final Map<String, ({int size, DateTime at, Set<String> plans})>
  _named = {};

  /// The plans of the project at [root], the newest first: none for a
  /// project on another machine.
  static Future<List<ProjectPlan>> of(String root) async {
    if (root.isEmpty || RemoteLocation.isRemote(root)) return const [];
    final paths = <String>{};
    final saved = Directory(folderIn(root));
    if (await saved.exists()) {
      await for (final entry in saved.list()) {
        if (entry is File && entry.path.endsWith('.md')) paths.add(entry.path);
      }
    }
    paths.addAll(await _namedIn(root));
    final plans = <ProjectPlan>[];
    for (final path in paths) {
      final file = File(path);
      try {
        final doc = PlanDoc.parse(await file.readAsString());
        plans.add((
          path: path,
          title: doc.title ?? p.basenameWithoutExtension(path),
          done: doc.doneCount,
          total: doc.todos.length,
          modified: await file.lastModified(),
        ));
      } on FileSystemException {
        continue;
      }
    }
    return plans..sort((a, b) => b.modified.compareTo(a.modified));
  }

  /// The plans in `~/.claude/plans` the transcripts of [root]'s
  /// conversations name, that are there still.
  static Future<Set<String>> _namedIn(String root) async {
    final dir = Directory(
      p.join(home, '.claude', 'projects', AgentPaths.projectDirName(root)),
    );
    if (!await dir.exists()) return const {};
    final stale = <String>[];
    final seen = <String>{};
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
      seen.add(entry.path);
      final stat = await entry.stat();
      final known = _named[entry.path];
      if (known == null ||
          known.size != stat.size ||
          known.at != stat.modified) {
        stale.add(entry.path);
        _named[entry.path] = (size: stat.size, at: stat.modified, plans: {});
      }
    }
    if (stale.isNotEmpty) {
      // Read aside: transcripts run to megabytes.
      final found = await Isolate.run(() => _plansNamed(stale));
      for (final MapEntry(key: path, value: plans) in found.entries) {
        final known = _named[path]!;
        _named[path] = (size: known.size, at: known.at, plans: plans);
      }
    }
    final plans = <String>{for (final path in seen) ...?_named[path]?.plans};
    return {
      for (final plan in plans)
        if (await File(plan).exists()) plan,
    };
  }

  static Map<String, Set<String>> _plansNamed(List<String> transcripts) {
    final named = RegExp(r'/[^"\s\\]*?/\.claude/plans/[^"\s\\/]+\.md');
    return {
      for (final path in transcripts)
        path: () {
          try {
            return {
              for (final match in named.allMatches(
                File(path).readAsStringSync(),
              ))
                match[0]!,
            };
          } on FileSystemException {
            return <String>{};
          }
        }(),
    };
  }

  /// Whether the plan at [path] is one saved in the project at [root].
  static bool isSavedIn(String path, String root) =>
      root.isNotEmpty && p.isWithin(folderIn(root), path);

  /// Copies the plan at [path] into the project at [root], its to-dos in
  /// its front matter (`<title>_<8 hex>.plan.md`, again the same file for
  /// the same plan); its path. One saved there already stays as it is.
  static Future<String> saveToProject(String path, String root) async {
    if (isSavedIn(path, root)) return path;
    final text = await File(path).readAsString();
    final doc = PlanDoc.parse(text);
    final cursor = doc.format == PlanTodosFormat.frontMatter
        ? text
        : doc.withTodos(doc.todos);
    final title = doc.title ?? p.basenameWithoutExtension(path);
    var slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.length > 60) slug = slug.substring(0, 60);
    if (slug.isEmpty) slug = 'plan';
    final hash = sha1.convert(utf8.encode(path)).toString().substring(0, 8);
    final target = p.join(folderIn(root), '${slug}_$hash.plan.md');
    await Directory(folderIn(root)).create(recursive: true);
    await writeFileAtomically(File(target), cursor);
    return target;
  }
}

/// The side panel's Plan page: the project's plans at its left, the one
/// open beside them ([child]; a word on them where none is).
class ProjectPlansPage extends StatelessWidget {
  const ProjectPlansPage({
    super.key,
    required this.root,
    required this.current,
    required this.onOpen,
    this.child,
  });

  final String? root;
  final String? current;
  final ValueChanged<String> onOpen;
  final Widget? child;

  static const listWidth = 220.0;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: listWidth,
        child: ProjectPlansList(
          key: ValueKey(('plans', root)),
          root: root ?? '',
          current: current,
          onOpen: onOpen,
        ),
      ),
      Container(width: 1, color: AppColors.border),
      Expanded(
        child:
            child ??
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.fork.planNoneOpen,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
                ),
              ),
            ),
      ),
    ],
  );
}

/// The project's plans, the newest first: each its title, how many of
/// its to-dos are done, when it changed; the one open selected.
class ProjectPlansList extends StatefulWidget {
  const ProjectPlansList({
    super.key,
    required this.root,
    required this.current,
    required this.onOpen,
    this.header = true,
  });

  final String root;
  final String? current;
  final ValueChanged<String> onOpen;

  /// Whether "Plans" is over them: not where a pane titles them.
  final bool header;

  /// How often they are looked for again.
  static Duration refreshEvery = const Duration(seconds: 5);

  @override
  State<ProjectPlansList> createState() => _ProjectPlansListState();
}

class _ProjectPlansListState extends State<ProjectPlansList> {
  List<ProjectPlan>? _plans;
  Timer? _refresh;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _refresh = Timer.periodic(
      ProjectPlansList.refreshEvery,
      (_) => unawaited(_load()),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final plans = await ProjectPlans.of(widget.root);
      if (mounted) setState(() => _plans = plans);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fork = context.fork;
    final plans = _plans;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              fork.planPlans,
              style: TextStyle(
                color: AppColors.textFaint,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: plans == null
              ? const SizedBox.shrink()
              : plans.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    fork.planNoPlans,
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  children: [
                    for (final plan in plans)
                      _PlanRow(
                        key: ValueKey(('plans.row', plan.path)),
                        plan: plan,
                        saved: ProjectPlans.isSavedIn(plan.path, widget.root),
                        selected: plan.path == widget.current,
                        onTap: () => widget.onOpen(plan.path),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    super.key,
    required this.plan,
    required this.saved,
    required this.selected,
    required this.onTap,
  });

  final ProjectPlan plan;

  /// Whether it is saved in the project, not only in `~/.claude/plans`.
  final bool saved;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
          margin: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            color: selected || hovered ? AppColors.hover : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  saved ? Codicons.checklist : Codicons.note,
                  size: 14,
                  color: AppColors.textFaint,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    Text(
                      [
                        if (plan.total > 0) '${plan.done}/${plan.total}',
                        relativeTime(plan.modified, DateTime.now(), l10n),
                      ].join(' · '),
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
