// The project's plans as a pane of the IDE's Explorer, as the chat's Plan
// page lists them (docs/fork.md): under Cursor's look, for a folder on
// this machine. A click opens the plan in the editor, with its to-dos.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../fork/cursor_look.dart';
import '../fork/fork_strings.dart';
import '../ide/ide_panes.dart';
import '../ide/services/editors.dart';
import '../ide/workbench/services.dart';
import 'project_plans.dart';

abstract final class PlanExplorerPane {
  static const id = 'plans';

  /// The pane for the folder at [root], [active] the editor's file; none
  /// where the plans are not listed (a remote folder, BaoCode's look).
  static List<IdePane> of(
    BuildContext context,
    WorkbenchServices services, {
    required String? root,
    required String? active,
  }) {
    if (!ChatLook.isCursor || !ProjectPlans.listed(root)) return const [];
    return [
      IdePane(
        id: id,
        title: context.fork.planPlans,
        body: ProjectPlansList(
          key: ValueKey(('explorer.plans', root)),
          root: root!,
          current: active,
          header: false,
          onOpen: (path) => unawaited(services.get<EditorService>().open(path)),
        ),
      ),
    ];
  }
}
