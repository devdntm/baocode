// The fork's layout (docs/fork.md): View: Toggle Cursor Layout, which
// switches `workbench.ide.layout` in settings.json (the IDE follows the
// file, as it does every setting, so the grid changes at once); and the
// CursorLayoutService Cursor's grid reads, kept with the window.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../workbench/actions.dart';
import '../workbench/contributions.dart';
import '../workbench/environment.dart';
import '../workbench/services.dart';
import '../workbench/storage.dart';
import 'cursor_layout_service.dart';
import 'ide_layout_style.dart';

class CursorLayoutContribution extends WorkbenchRegistrations {
  CursorLayoutContribution(WorkbenchServices services) {
    final environment = services.get<WorkbenchEnvironment>();
    final cursor = services.add(CursorLayoutService());
    final storage = services.get<WorkbenchStorage>();
    add(storage.register(cursor));
    cursor.addListener(storage.changed);
    add(() => cursor.removeListener(storage.changed));
    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: toggleId,
          category: 'View',
          title: 'Toggle Cursor Layout',
          // Without settings.json there is nowhere to keep it.
          precondition: (_) => environment.settings != null,
          run: (_, _) {
            final settings = environment.settings;
            if (settings == null) return;
            unawaited(
              IdeLayoutStyle.select(
                settings,
                IdeLayoutStyle.of(settings).other,
              ).catchError((Object error) {
                // A settings file that does not parse is left as it is.
                debugPrint('${IdeLayoutStyle.settingKey} not kept: $error');
              }),
            );
          },
        ),
      ]),
    );
  }

  static const toggleId = 'workbench.action.toggleCursorLayout';
}
