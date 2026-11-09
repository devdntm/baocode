// The fork's `workbench.scroll.momentum` setting (docs/fork.md): a
// trackpad's scrolling as Cursor's, by macOS's own momentum
// (packages/fork_scroll_momentum), and following the fingers from their
// first pixels. Off by default; BaoCode Dev turns it on.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:fork_scroll_momentum/fork_scroll_momentum.dart';

import '../platform/app_platform.dart';

enum ScrollMomentum {
  /// Flutter's fling, as upstream's (the default).
  flutter,

  /// The system's.
  system;

  static const settingKey = 'workbench.scroll.momentum';

  static ScrollMomentum parse(Object? value) =>
      value == system.name ? system : flutter;

  /// Whether a Mac's trackpad scrolls as the system does now.
  static final ValueNotifier<bool> systemNow = ValueNotifier(false);

  /// How far the fingers go on a trackpad before a list follows them: a
  /// touch screen's 18 px (Flutter's `kTouchSlop`) left a swipe's start
  /// behind; Cursor's follow at once. 3, not 1: a swipe down a page that
  /// starts a pixel sideways is not taken by a code block scrolling
  /// sideways in it. Null: Flutter's.
  static DeviceGestureSettings? get gestureSettings =>
      systemNow.value ? const DeviceGestureSettings(touchSlop: slop) : null;

  static const slop = 3.0;

  /// Follows [read] now and whenever [changes] notifies.
  static void follow(Listenable changes, Object? Function() read) {
    void update() {
      final on = AppPlatform.isMacOS && parse(read()) == system;
      systemNow.value = on;
      // The momentum's pan taken at once, all its deltas the view's.
      SystemMomentum.primeBy = on ? slop + 0.5 : 0;
      SystemMomentum.enable(on);
    }

    update();
    changes.addListener(update);
  }
}
