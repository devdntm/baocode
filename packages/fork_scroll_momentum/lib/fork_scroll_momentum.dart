/// The trackpad's momentum as macOS makes it (docs/fork.md,
/// `workbench.scroll.momentum`).
///
/// Flutter's macOS embedder drops the system's momentum events and flings
/// by the framework's physics, so a flick glides otherwise than in other
/// Mac apps (Cursor's, Chromium's, take the system's). Turned on, the
/// plugin's monitor sends each momentum event here, and it goes on to the
/// gestures as the fingers' pan did: a trackpad pan of its own device,
/// which lists and editors follow pixel for pixel. Their own fling is then
/// to be turned off ([flingsOff]).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

abstract final class SystemMomentum {
  static const _channel = MethodChannel('baocode/scroll_momentum');

  /// The device its pans come from: not the embedder's (1).
  static const device = 0x5c0110;

  /// Whether the system's momentum scrolls now.
  static bool get enabled => _enabled;
  static bool _enabled = false;

  /// Whether a trackpad's fingers lifting is to fling nothing: the system's
  /// momentum, coming here, goes on for them.
  static bool get flingsOff => _enabled || debugFlingsOff;

  /// [flingsOff] where the plugin is not there to turn it on: a test.
  @visibleForTesting
  static bool debugFlingsOff = false;

  /// Turns it on or off: a build without the plugin (a test, another
  /// platform) has none of it, and stays as Flutter scrolls.
  static Future<void> enable(bool on) async {
    if (on == _enabled) return;
    _enabled = on;
    _channel.setMethodCallHandler(on ? _call : null);
    try {
      await _channel.invokeMethod<void>('enable', on);
    } on MissingPluginException {
      _enabled = false;
      _channel.setMethodCallHandler(null);
    }
    if (!_enabled) _end(Duration.zero);
  }

  static Future<void> _call(MethodCall call) async {
    if (call.method != 'momentum') return;
    final args = (call.arguments as Map).cast<String, Object?>();
    handle(args);
  }

  static int _nextPointer = 0x5c01100000;
  static int? _pointer;
  static int _view = 0;
  static Offset _at = Offset.zero;
  static Offset _pan = Offset.zero;

  /// One momentum event: `phase` begin, update or end; `view`, `x`, `y`
  /// where it is (the view's points); `dx`, `dy` its deltas; `time` in
  /// microseconds. To [dispatch] (the gestures' by default).
  @visibleForTesting
  static void handle(
    Map<String, Object?> event, {
    void Function(PointerEvent event)? dispatch,
  }) {
    if (dispatch != null) _dispatch = dispatch;
    final time = Duration(microseconds: (event['time'] as num?)?.toInt() ?? 0);
    final view = (event['view'] as num?)?.toInt() ?? 0;
    final at = Offset(
      (event['x'] as num?)?.toDouble() ?? 0,
      (event['y'] as num?)?.toDouble() ?? 0,
    );
    final delta = Offset(
      (event['dx'] as num?)?.toDouble() ?? 0,
      (event['dy'] as num?)?.toDouble() ?? 0,
    );
    switch (event['phase']) {
      case 'begin':
        _end(time);
        _start(time, view, at);
        _prime(time, delta);
        _move(time, delta);
      case 'update':
        if (_pointer == null) {
          _start(time, view, at);
          _prime(time, delta);
        }
        _move(time, delta);
      case 'end':
        _move(time, delta);
        _end(time);
    }
  }

  static void Function(PointerEvent event) _dispatch =
      GestureBinding.instance.handlePointerEvent;

  @visibleForTesting
  static void resetDispatch() =>
      _dispatch = GestureBinding.instance.handlePointerEvent;

  static void _start(Duration time, int view, Offset at) {
    _pointer = _nextPointer++;
    _view = view;
    _at = at;
    _pan = Offset.zero;
    _dispatch(
      PointerPanZoomStartEvent(
        viewId: _view,
        timeStamp: time,
        device: device,
        pointer: _pointer!,
        position: _at,
      ),
    );
  }

  /// A step just past the slop the lists take a trackpad's drag after
  /// (`DeviceGestureSettings.touchSlop`), before the system's first delta:
  /// a drag drops what moved before it was taken, and the momentum's
  /// deltas are to move the view all of them. 0: none.
  static double primeBy = 0;

  static void _prime(Duration time, Offset delta) {
    if (primeBy <= 0 || delta == Offset.zero) return;
    final step = delta.dx.abs() > delta.dy.abs()
        ? Offset(delta.dx.sign * primeBy, 0)
        : Offset(0, delta.dy.sign * primeBy);
    _move(time, step);
  }

  static void _move(Duration time, Offset delta) {
    final pointer = _pointer;
    if (pointer == null || delta == Offset.zero) return;
    _pan += delta;
    _dispatch(
      PointerPanZoomUpdateEvent(
        viewId: _view,
        timeStamp: time,
        device: device,
        pointer: pointer,
        position: _at,
        pan: _pan,
        panDelta: delta,
      ),
    );
  }

  static void _end(Duration time) {
    final pointer = _pointer;
    if (pointer == null) return;
    _pointer = null;
    _dispatch(
      PointerPanZoomEndEvent(
        viewId: _view,
        timeStamp: time,
        device: device,
        pointer: pointer,
        position: _at,
      ),
    );
  }
}

/// A trackpad's velocity tracker that never flings: where the system's
/// momentum goes on for the fingers ([SystemMomentum.flingsOff]).
class NoFlingVelocityTracker extends VelocityTracker {
  NoFlingVelocityTracker() : super.withKind(PointerDeviceKind.trackpad);

  static const _still = VelocityEstimate(
    pixelsPerSecond: Offset.zero,
    confidence: 1,
    duration: Duration.zero,
    offset: Offset.zero,
  );

  @override
  VelocityEstimate? getVelocityEstimate() => _still;

  @override
  Velocity getVelocity() => Velocity.zero;
}
