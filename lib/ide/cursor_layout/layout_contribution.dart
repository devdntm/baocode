// The fork's layout command (docs/fork.md): View: Toggle Cursor Layout,
// which switches `workbench.ide.layout` in settings.json. The IDE follows
// the file, as it does every setting, so the grid changes at once.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../workbench/actions.dart';
import '../workbench/contributions.dart';
import '../workbench/environment.dart';
import '../workbench/services.dart';
import 'ide_layout_style.dart';

class CursorLayoutContribution extends WorkbenchRegistrations {
  CursorLayoutContribution(WorkbenchServices services) {
    final environment = services.get<WorkbenchEnvironment>();
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
