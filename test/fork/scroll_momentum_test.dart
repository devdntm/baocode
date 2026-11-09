import 'package:baocode/base/smooth_scroll.dart';
import 'package:baocode/fork/scroll_momentum.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fork_scroll_momentum/fork_scroll_momentum.dart';

/// A list of the app's scrolling, the trackpad's slop as the setting has it.
Future<ScrollController> _pumpList(WidgetTester tester) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const BaoScrollBehavior(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            gestureSettings: const DeviceGestureSettings(
              touchSlop: ScrollMomentum.slop,
            ),
          ),
          child: ListView.builder(
            controller: controller,
            itemCount: 200,
            itemBuilder: (context, i) =>
                SizedBox(height: 40, child: Text('row $i')),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  test('the setting: system only when set so', () {
    expect(ScrollMomentum.parse('system'), ScrollMomentum.system);
    expect(ScrollMomentum.parse(null), ScrollMomentum.flutter);
  });

  test('a momentum: a pan of its own device, begun, moved, ended', () {
    final events = <PointerEvent>[];
    void event(String phase, double dy) => SystemMomentum.handle({
      'view': 0,
      'phase': phase,
      'x': 100.0,
      'y': 200.0,
      'dx': 0.0,
      'dy': dy,
      'time': 1000,
    }, dispatch: events.add);
    addTearDown(SystemMomentum.resetDispatch);
    event('begin', -10);
    event('update', -6);
    event('update', 0);
    event('end', -1);
    expect(events.map((e) => e.runtimeType), [
      PointerPanZoomStartEvent,
      PointerPanZoomUpdateEvent,
      PointerPanZoomUpdateEvent,
      PointerPanZoomUpdateEvent,
      PointerPanZoomEndEvent,
    ]);
    expect(events.every((e) => e.device == SystemMomentum.device), isTrue);
    expect(events.map((e) => e.pointer).toSet(), hasLength(1));
    final last = events[3] as PointerPanZoomUpdateEvent;
    expect(last.pan, const Offset(0, -17));
    expect(last.position, const Offset(100, 200));
    expect(events.first.kind, PointerDeviceKind.trackpad);
  });

  testWidgets('flings off: a trackpad\'s tracker says it stood still', (
    tester,
  ) async {
    final tracker = NoFlingVelocityTracker();
    tracker.addPosition(Duration.zero, Offset.zero);
    tracker.addPosition(const Duration(milliseconds: 10), const Offset(0, 50));
    expect(tracker.getVelocity(), Velocity.zero);
    expect(tracker.getVelocityEstimate()!.pixelsPerSecond, Offset.zero);
  });

  testWidgets('the app\'s scrolling takes a trackpad\'s tracker as still, a '
      'mouse\'s as ever', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final builder = const BaoScrollBehavior().velocityTrackerBuilder(context);
    const trackpad = PointerPanZoomStartEvent();
    const mouse = PointerDownEvent();
    expect(builder(trackpad), isNot(isA<NoFlingVelocityTracker>()));
    SystemMomentum.debugFlingsOff = true;
    addTearDown(() => SystemMomentum.debugFlingsOff = false);
    expect(builder(trackpad), isA<NoFlingVelocityTracker>());
    expect(builder(mouse), isNot(isA<NoFlingVelocityTracker>()));
  });

  testWidgets('the system\'s momentum moves a list by its deltas, and the '
      'fingers fling it no further', (tester) async {
    SystemMomentum.debugFlingsOff = true;
    SystemMomentum.primeBy = ScrollMomentum.slop + 0.5;
    addTearDown(() {
      SystemMomentum.debugFlingsOff = false;
      SystemMomentum.primeBy = 0;
    });
    final controller = await _pumpList(tester);
    final view = tester.view.viewId;
    void event(String phase, double dy) => SystemMomentum.handle({
      'view': view,
      'phase': phase,
      'x': 100.0,
      'y': 200.0,
      'dx': 0.0,
      'dy': dy,
      'time': tester.binding.clock.now().microsecondsSinceEpoch,
    });
    // Momentum goes on downwards: the content up, the offset up.
    event('begin', -20);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      event('update', -10);
      await tester.pump(const Duration(milliseconds: 8));
    }
    event('end', 0);
    await tester.pumpAndSettle();
    // All of its 120 px: none dropped as the drag is taken, no fling after.
    expect(controller.offset, closeTo(120, 0.01));
  });
}
