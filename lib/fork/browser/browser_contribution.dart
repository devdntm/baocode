// The browser's page as a tab of the IDE's editor, as Cursor opens it
// (docs/fork.md): its file view (a path no file has, ForkBrowser.idePath)
// and View: Open Browser.

import 'dart:async';

import '../../ide/file_views.dart';
import '../../ide/services/editors.dart';
import '../../ide/workbench/actions.dart';
import '../../ide/workbench/contributions.dart';
import '../../ide/workbench/services.dart';
import 'browser_mirror.dart';
import 'fork_browser.dart';

class ForkBrowserContribution extends WorkbenchRegistrations {
  ForkBrowserContribution(WorkbenchServices services) {
    registerView();
    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: openId,
          category: 'View',
          title: 'Open Browser',
          precondition: (_) => ForkBrowser.offered,
          run: (_, _) => unawaited(
            services.get<EditorService>().open(ForkBrowser.idePath),
          ),
        ),
      ]),
    );
  }

  static const openId = 'workbench.action.openBrowserTab';

  /// The page in the IDE's tab at [ForkBrowser.idePath]: kept registered,
  /// so a tab of it the window kept opens again with the window.
  static void registerView() => FileViews.register(
    FileView(
      id: 'fork.browser',
      matches: ForkBrowser.isIdePath,
      build: (context, path) => const BrowserMirror(),
    ),
  );
}
