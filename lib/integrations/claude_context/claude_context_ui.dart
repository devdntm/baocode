// Where the claude-context index shows (docs/fork.md): an item of the
// IDE's status bar, "Index 2488/2488", a run's share while it indexes,
// clicked for what is missing and to index; and the same in the chat's
// sidebar, in a project's menu. A project the IDE opens with no index is
// offered one, or indexed at once once the user said so for all.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../customize/customization_store.dart';
import '../../customize/customizations.dart';
import '../../fork/fork_strings.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_notifications.dart';
import '../../ide/ide_status_bar.dart';
import '../../ide/ide_workspace.dart';
import '../../ide/workbench/contributions.dart';
import '../../ide/workbench/services.dart';
import '../../ide/workbench/statusbar.dart';
import '../../platform/data_dir.dart';
import '../../settings/user_settings.dart';
import '../../sidebar/sidebar_menu.dart';
import '../../theme/codicons.dart';
import '../../workspace/workspace.dart';
import 'claude_context.dart';

/// The index's item in the IDE's status bar, for the folder's project
/// where claude-context is among its MCP servers.
class ClaudeContextContribution extends WorkbenchRegistrations {
  ClaudeContextContribution(WorkbenchServices services) {
    if (!ClaudeContextIndex.enabled) return;
    final changes = _Follow();
    add(changes.dispose);
    final entry = services.get<StatusbarService>().addEntry(
      'fork.claudeContext',
      StatusbarAlignment.right,
      (context) => switch (changes.index) {
        final index? => claudeContextStatusItem(context, index),
        null => null,
      },
      priority: 50,
      changes: changes,
    );
    add(entry.dispose);
    // The window's workspace is its services' once it is made: after this.
    unawaited(
      Future.microtask(() async {
        final workspace = services.find<IdeWorkspace>();
        if (workspace == null || !workspace.hasFolder || changes.disposed) {
          return;
        }
        final server = await ClaudeContextIndex.serverOf(workspace.root);
        final index = ClaudeContextIndex.of(workspace.root, server);
        if (index == null || changes.disposed) return;
        changes.follow(index);
        if (index.state == ClaudeContextState.unknown) await index.check();
        final context = services.find<WorkbenchHost>()?.context;
        if (changes.disposed || context == null || !context.mounted) return;
        if (index.state != ClaudeContextState.notIndexed) return;
        await offerClaudeContextIndex(context, workspace.notifications, index);
      }),
    );
  }
}

/// A project with no index, as the IDE opens it: indexed at once where the
/// user said so for every project (`claudeContext.autoIndex`), else offered
/// once a run of the app, not where the user said not to ask.
abstract final class ClaudeContextOffer {
  static const settingKey = 'claudeContext.autoIndex';

  static UserSettings get _settings => SettingsFiles.instance.settings;

  /// Whether every project with no index is indexed as it opens.
  static bool get auto => _settings[settingKey] == true;

  static Future<void> turnOn() => _settings.update(settingKey, true);

  /// The projects offered in this run of the app.
  static final Set<String> _offered = {};

  static File get _file => File(
    p.join(DataDirectory.current.cacheDir, 'claude-context', 'no-offer.json'),
  );

  static Future<Set<String>> _declined() async {
    try {
      final json = jsonDecode(await _file.readAsString());
      return {if (json is List) ...json.whereType<String>()};
    } on Object {
      return {};
    }
  }

  static Future<bool> declined(String root) async =>
      (await _declined()).contains(root);

  static Future<void> decline(String root) async {
    final roots = await _declined()
      ..add(root);
    await _file.parent.create(recursive: true);
    await writeFileAtomically(_file, jsonEncode(roots.toList()..sort()));
  }

  @visibleForTesting
  static void forgetOffered() => _offered.clear();
}

/// [index], of a project with none, indexed or offered
/// ([ClaudeContextOffer]).
Future<void> offerClaudeContextIndex(
  BuildContext context,
  IdeNotifications notifications,
  ClaudeContextIndex index,
) async {
  if (ClaudeContextOffer.auto) return index.index();
  if (!ClaudeContextOffer._offered.add(index.root)) return;
  if (await ClaudeContextOffer.declined(index.root) || !context.mounted) {
    return;
  }
  final fork = context.fork;
  notifications.notify(
    IdeSeverity.info,
    fork.indexOffer,
    source: 'claude-context',
    sticky: true,
    primary: [
      IdeNotificationAction(fork.indexRun, () => unawaited(index.index())),
      IdeNotificationAction(fork.indexOfferAlways, () {
        unawaited(ClaudeContextOffer.turnOn());
        unawaited(index.index());
      }),
    ],
    secondary: [
      IdeNotificationAction(
        fork.indexOfferNever,
        () => unawaited(ClaudeContextOffer.decline(index.root)),
      ),
    ],
  );
}

/// Tells as the index followed does, once there is one.
class _Follow extends ChangeNotifier {
  ClaudeContextIndex? index;
  bool disposed = false;

  void follow(ClaudeContextIndex next) {
    index = next..addListener(notifyListeners);
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    index?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// "Index 2488/2488" and its state's icon; a run's share while indexing.
IdeStatusBarItem claudeContextStatusItem(
  BuildContext context,
  ClaudeContextIndex index,
) {
  final fork = context.fork;
  final report = index.report;
  final (IconData icon, String text) = switch (index.state) {
    ClaudeContextState.unknown ||
    ClaudeContextState.checking => (Codicons.database, fork.indexChecking),
    ClaudeContextState.indexing => (
      Codicons.sync,
      fork.indexRunning(switch (index.percentage) {
        final share? => '${share.round()}%',
        null => '${index.rows ?? 0}',
      }),
    ),
    ClaudeContextState.complete => (
      Codicons.pass,
      fork.indexFiles(report!.indexedFiles, report.projectFiles!),
    ),
    ClaudeContextState.incomplete => (
      Codicons.warning,
      fork.indexFiles(
        report!.indexedFiles,
        report.projectFiles ?? report.indexedFiles,
      ),
    ),
    ClaudeContextState.notIndexed => (Codicons.database, fork.indexNotIndexed),
    ClaudeContextState.interrupted => (Codicons.warning, fork.indexInterrupted),
    ClaudeContextState.failed => (Codicons.error, fork.indexFailed),
  };
  return IdeStatusBarItem(
    text,
    key: const ValueKey('fork.claudeContext'),
    icon: icon,
    tooltip: fork.indexTooltip,
    onTapRect: (rect) =>
        unawaited(showClaudeContextMenu(context, index, anchor: rect)),
  );
}

/// What the index is (how much of the project, the folders it misses)
/// and what to do: index the files changed, all again (asked first), look
/// again.
List<IdeMenuEntry> claudeContextMenu(
  BuildContext context,
  ClaudeContextIndex index,
) {
  final fork = context.fork;
  final report = index.report;
  return [
    if (report != null && report.exists)
      IdeMenuAction(
        fork.indexSummary(
          report.indexedFiles,
          report.projectFiles,
          report.chunks,
        ),
        enabled: false,
      ),
    for (final (:dir, :count)
        in report?.missingByDir.take(8) ?? const <({String dir, int count})>[])
      IdeMenuAction(fork.indexMissingIn(dir, count), enabled: false),
    if (index.state == ClaudeContextState.interrupted)
      IdeMenuAction(fork.indexInterruptedHint, enabled: false),
    if (index.error case final error?) IdeMenuAction(error, enabled: false),
    const IdeMenuSeparator(),
    IdeMenuAction(
      fork.indexRun,
      enabled: !index.busy,
      onSelected: () => unawaited(index.index()),
    ),
    IdeMenuAction(
      fork.indexForce,
      enabled: !index.busy,
      onSelected: () => unawaited(_forceIndex(context, index)),
    ),
    IdeMenuAction(
      fork.indexCheck,
      enabled: !index.busy,
      onSelected: () => unawaited(index.check()),
    ),
  ];
}

Future<void> showClaudeContextMenu(
  BuildContext context,
  ClaudeContextIndex index, {
  Rect? anchor,
  Offset? position,
}) => showIdeMenu(
  context,
  anchor: anchor,
  position: position,
  alignRight: true,
  entries: claudeContextMenu(context, index),
);

/// All of it again, once the user says so: the index is dropped.
Future<void> _forceIndex(BuildContext context, ClaudeContextIndex index) async {
  final fork = context.fork;
  final choice = await showIdeDialog(
    context,
    message: fork.indexForceTitle,
    detail: fork.indexForceDetail,
    buttons: [fork.indexForce.replaceAll('…', '')],
  );
  if (choice == 0) await index.index(force: true);
}

/// A project's menu in the chat's sidebar: its index's state and the same
/// actions, where claude-context is the user's MCP server.
List<SidebarMenuItem> claudeContextProjectItems(
  BuildContext context,
  Project project,
) {
  final index = ClaudeContextIndex.of(
    project.path,
    ClaudeContextIndex.userServer,
  );
  if (index == null) return const [];
  if (index.state == ClaudeContextState.unknown) unawaited(index.check());
  final fork = context.fork;
  final report = index.report;
  final state = switch (index.state) {
    ClaudeContextState.complete ||
    ClaudeContextState.incomplete => fork.indexFiles(
      report!.indexedFiles,
      report.projectFiles ?? report.indexedFiles,
    ),
    ClaudeContextState.notIndexed => fork.indexNotIndexed,
    ClaudeContextState.interrupted => fork.indexInterrupted,
    ClaudeContextState.failed => fork.indexFailed,
    ClaudeContextState.indexing => fork.indexRunning(switch (index.percentage) {
      final share? => '${share.round()}%',
      null => '${index.rows ?? 0}',
    }),
    _ => fork.indexChecking,
  };
  return [
    const SidebarMenuItem.divider(),
    SidebarMenuItem(
      fork.indexProject,
      icon: Icons.manage_search_rounded,
      detail: state,
      onSelected: () => index.busy ? null : unawaited(index.index()),
    ),
    SidebarMenuItem(
      fork.indexForce,
      icon: Icons.refresh_rounded,
      onSelected: () =>
          index.busy ? null : unawaited(_forceIndex(context, index)),
    ),
  ];
}

/// Looks for the user's claude-context server once, for the sidebar's
/// projects (the IDE looks for each project's own).
Future<void> findClaudeContextServer([CustomizationStore? store]) async {
  if (!ClaudeContextIndex.enabled) return;
  final servers = await (store ?? ClaudeContextIndex.store).list(
    // The user's: no project.
    CustomizationKind.mcps,
  );
  for (final server in servers) {
    if (server.name == 'claude-context' &&
        server.enabled != false &&
        server.server?['command'] is String) {
      ClaudeContextIndex.userServer = server.server;
      return;
    }
  }
}
