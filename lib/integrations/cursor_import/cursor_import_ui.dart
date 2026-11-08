// Where Import from Cursor is offered (docs/fork.md): a notice as the IDE
// opens a folder Cursor was used in (not again once put off), the IDE's
// palette, and a project's menu in the chat's sidebar.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../fork/fork_strings.dart';
import '../../ide/ide_notifications.dart';
import '../../ide/ide_workspace.dart';
import '../../ide/workbench/actions.dart';
import '../../ide/workbench/contributions.dart';
import '../../ide/workbench/services.dart';
import '../../platform/data_dir.dart';
import '../../sidebar/sidebar_menu.dart';
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
    if (!CursorImportNotice.enabled) return;
    // The window's workspace is its services' once it is made: after this.
    unawaited(
      Future.microtask(() async {
        final workspace = services.find<IdeWorkspace>();
        final folder = root();
        final context = services.find<WorkbenchHost>()?.context;
        if (workspace == null || folder == null || context == null) return;
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
  return [
    SidebarMenuItem(
      context.fork.cursorImportAction,
      icon: Icons.download_rounded,
      onSelected: () => unawaited(CursorImport.open(context, project.path)),
    ),
  ];
}
