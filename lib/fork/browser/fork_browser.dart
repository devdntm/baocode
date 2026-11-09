// The browser's page as Cursor has one (docs/fork.md): the mirror of the
// user's tab an agent works in, which BaoCode's upstream took out of its
// side panel in 1.9.0 (#665). Here it is the side panel's Browser page in
// the agents' window, and a Browser tab in the IDE's editor; both under
// `chat.look: cursor`, once a browser of the user's has connected.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../browser/browser_bridge.dart';
import '../../ide/services/editors.dart';
import '../../ide/workbench/services.dart';
import '../cursor_look.dart';

abstract final class ForkBrowser {
  /// The tab an agent last used: the page shows it.
  static final lastTab = ValueNotifier<BrowserTab?>(null);

  static final _shown = StreamController<BrowserTab>.broadcast();

  /// The tabs asked to show ([show]): the page brings them to the front.
  static Stream<BrowserTab> get shown => _shown.stream;

  /// Shows the page in the agents' window's side panel: set by the
  /// workbench (an IDE's chat opens its tab instead, see [showAt]).
  static void Function()? revealInPanel;

  /// Whether the page is offered: Cursor's look, a browser connected.
  static bool get offered => ChatLook.isCursor && BrowserBridge.instance.used;

  /// An agent's browser tool used [tabId]: the page follows it.
  static void used(int tabId) {
    final browsers = BrowserBridge.instance.browsers;
    if (browsers.isEmpty) return;
    lastTab.value = BrowserTab(browsers.first, tabId);
  }

  /// Shows [tabId] on the page (a step of the conversation's): as the tab
  /// an agent used last, over the one the user picked there.
  static void show(int tabId) {
    final browsers = BrowserBridge.instance.browsers;
    if (browsers.isEmpty) return;
    final tab = BrowserTab(browsers.first, tabId);
    lastTab.value = tab;
    _shown.add(tab);
  }

  /// [show]s [tabId] where [context] is: in a tab of the IDE's editor in
  /// an IDE, else on the side panel's page.
  static void showAt(BuildContext context, int tabId) {
    show(tabId);
    if (WorkbenchScope.maybeOf(context) case final services?) {
      unawaited(services.get<EditorService>().open(idePath));
    } else {
      revealInPanel?.call();
    }
  }

  static final _started = StreamController<Object>.broadcast();

  /// The conversations (their sessions) an agent of which began to work in
  /// the browser this turn: the window that shows one opens the page, as
  /// Cursor does ([agentInBrowser]).
  static Stream<Object> get started => _started.stream;

  static final Set<Object> _openedFor = {};

  /// A browser step of [session]'s agent came: the page opens, once a
  /// turn (closed meanwhile, it stays closed till the next).
  static void agentInBrowser(Object session) {
    if (!offered || !_openedFor.add(session)) return;
    _started.add(session);
  }

  /// [session]'s turn ended: its next browser step opens the page again.
  static void turnEnded(Object session) => _openedFor.remove(session);

  /// The IDE's tab of the page: a path no file has, its name the tab's.
  static const idePath = '/.baocode-browser/Browser';

  static bool isIdePath(String path) => path == idePath;
}
