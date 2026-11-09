// Where Import from Cursor is offered (docs/fork.md): a notice as the IDE
// opens a folder Cursor was used in (not again once put off), the IDE's
// palette, and a project's menu in the chat's sidebar. Once started, its
// progress is in the IDE's status bar and in that menu, and the IDE tells
// when it ends, its dialog closed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../fork/fork_strings.dart';
import '../../ide/ide_notifications.dart';
import '../../ide/ide_status_bar.dart';
import '../../ide/ide_workspace.dart';
import '../../ide/workbench/actions.dart';
import '../../ide/workbench/contributions.dart';
import '../../ide/workbench/services.dart';
import '../../ide/workbench/statusbar.dart';
import '../../platform/data_dir.dart';
import '../../sidebar/sidebar_menu.dart';
import '../../theme/codicons.dart';
import '../../workspace/workspace.dart';
import 'cursor_import.dart';
import 'cursor_import_dialog.dart';

/// Import from Cursor in the IDE: the palette's command, and the notice.
class CursorImportContribution extends WorkbenchRegistrations {
  CursorImportContribution(WorkbenchServices services) {
    String? root() => switch (services.find<IdeWorkspace>()) {
      final workspace? when workspace.hasFolder => workspace.root,
      _ => null,
    };
    void open() {
      final context = services.find<WorkbenchHost>()?.context;
      final folder = root();
      if (context == null || folder == null) return;
      unawaited(CursorImport.open(context, folder));
    }

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: commandId,
          category: 'File',
          title: 'Import from Cursor…',
          precondition: (_) => CursorProject.seen(root() ?? ''),
          run: (_, _) => open(),
        ),
      ]),
    );
    final job = _Job();
    add(job.dispose);
    final entry = services.get<StatusbarService>().addEntry(
      'fork.cursorImport',
      StatusbarAlignment.left,
      (context) => switch (job.job) {
        final followed? => cursorImportStatusItem(context, followed, open),
        null => null,
      },
      priority: 40,
      changes: job,
    );
    add(entry.dispose);
    // The window's workspace is its services' once it is made: after this.
    unawaited(
      Future.microtask(() async {
        final workspace = services.find<IdeWorkspace>();
        final folder = root();
        final context = services.find<WorkbenchHost>()?.context;
        if (workspace == null || folder == null || context == null) return;
        if (job.disposed) return;
        job.follow(CursorImportJob.of(folder), () {
          final context = services.find<WorkbenchHost>()?.context;
          if (context == null || !context.mounted) return;
          if (CursorImport.isOpen(folder)) return;
          final fork = context.fork;
          final failed = job.job?.failed ?? false;
          workspace.notifications.notify(
            failed ? IdeSeverity.error : IdeSeverity.info,
            failed ? fork.cursorImportFailed : fork.cursorImportFinished,
            source: fork.cursorImportTitle,
            primary: [IdeNotificationAction(fork.cursorImportShow, open)],
          );
        });
        if (!CursorImportNotice.enabled) return;
        if (!CursorProject.seen(folder)) return;
        if (await CursorImportNotice.putOff(folder)) return;
        if (!context.mounted) return;
        final fork = context.fork;
        workspace.notifications.notify(
          IdeSeverity.info,
          fork.cursorImportBanner,
          sticky: true,
          primary: [
            IdeNotificationAction(fork.cursorImportAction, open),
            IdeNotificationAction(
              fork.cursorImportDismiss,
              () => unawaited(CursorImportNotice.putOffFor(folder)),
            ),
          ],
        );
      }),
    );
  }

  static const commandId = 'fork.cursor.import';
}

/// Tells as the project's import does, once there is one, and calls
/// [_ended] as it ends.
class _Job extends ChangeNotifier {
  CursorImportJob? job;
  VoidCallback? _ended;
  bool _running = false;
  bool disposed = false;

  void follow(CursorImportJob next, VoidCallback ended) {
    job = next..addListener(_changed);
    _ended = ended;
    _running = next.running;
    notifyListeners();
  }

  void _changed() {
    final running = job!.running;
    if (_running && !running) _ended?.call();
    _running = running;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    job?.removeListener(_changed);
    super.dispose();
  }
}

/// How far [job] is, in a few words: the conversations' stage and turns,
/// else that it imports; null when it is not going on.
String? cursorImportProgress(BuildContext context, CursorImportJob job) {
  if (!job.running) return null;
  final fork = context.fork;
  final history = job.history;
  if (history != null && history.running) {
    final stage = fork.cursorImportStage(history.stage.name);
    return history.stage == CursorHistoryStage.summarizing
        ? fork.cursorImportHistoryProgress(stage, history.done, history.total)
        : stage;
  }
  return fork.cursorImportStatusParts;
}

/// The import's item in the status bar: how far it is while it goes on,
/// how it ended until that is seen ([open] shows it); none otherwise.
IdeStatusBarItem? cursorImportStatusItem(
  BuildContext context,
  CursorImportJob job,
  VoidCallback open,
) {
  final fork = context.fork;
  final progress = cursorImportProgress(context, job);
  if (progress == null && !job.unseen) return null;
  final (IconData icon, String text) = switch (progress) {
    final progress? => (
      Codicons.sync,
      fork.cursorImportStatusRunning(progress),
    ),
    null when job.failed => (Codicons.error, fork.cursorImportStatusFailed),
    null => (Codicons.check, fork.cursorImportStatusDone),
  };
  return IdeStatusBarItem(
    text,
    key: const ValueKey('fork.cursorImport'),
    icon: icon,
    tooltip: fork.cursorImportStatusTooltip,
    onTap: open,
  );
}

/// The folders whose notice was put off: not shown for them again.
abstract final class CursorImportNotice {
  /// Not under `flutter test`, unless a test says so.
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  static File get _file => File(
    p.join(DataDirectory.current.cacheDir, 'cursor-import', 'put-off.json'),
  );

  static Future<Set<String>> _read() async {
    try {
      final json = jsonDecode(await _file.readAsString());
      return {if (json is List) ...json.whereType<String>()};
    } on Object {
      return {};
    }
  }

  static Future<bool> putOff(String root) async =>
      (await _read()).contains(root);

  static Future<void> putOffFor(String root) async {
    final roots = await _read()
      ..add(root);
    await _file.parent.create(recursive: true);
    await writeFileAtomically(_file, jsonEncode(roots.toList()..sort()));
  }
}

/// A project's menu in the chat's sidebar: Import from Cursor, where it
/// was used in Cursor.
List<SidebarMenuItem> cursorImportProjectItems(
  BuildContext context,
  Project project,
) {
  if (!CursorProject.seen(project.path)) return const [];
  final job = CursorImportJob.started(project.path);
  return [
    SidebarMenuItem(
      context.fork.cursorImportAction,
      icon: Icons.download_rounded,
      detail: switch (job) {
        final job? => cursorImportProgress(context, job),
        null => null,
      },
      onSelected: () => unawaited(CursorImport.open(context, project.path)),
    ),
  ];
}
