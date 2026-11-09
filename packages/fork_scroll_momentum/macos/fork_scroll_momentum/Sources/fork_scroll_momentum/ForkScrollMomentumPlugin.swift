// The trackpad's momentum as macOS makes it, for Flutter (docs/fork.md,
// `workbench.scroll.momentum`). Flutter's embedder drops the system's
// momentum events and flings by its own physics; Cursor (Chromium) scrolls
// by the system's. Turned on, each momentum event goes to Dart with where
// it is (the Flutter view under it, in its points) and its deltas, and
// Dart moves the view by them as by the fingers.

import AppKit
import FlutterMacOS

public final class ForkScrollMomentumPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var monitor: Any?

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "baocode/scroll_momentum",
      binaryMessenger: registrar.messenger
    )
    let plugin = ForkScrollMomentumPlugin(channel: channel)
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "enable":
      let on = (call.arguments as? Bool) ?? false
      if on && monitor == nil {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
          [weak self] event in
          self?.forward(event)
          return event
        }
      } else if !on, let monitor {
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// A momentum event (the fingers lifted, the system going on) to Dart.
  private func forward(_ event: NSEvent) {
    guard event.phase.isEmpty, !event.momentumPhase.isEmpty,
      event.hasPreciseScrollingDeltas,
      let window = event.window,
      let content = window.contentView
    else { return }
    let phase: String
    if event.momentumPhase.contains(.began) {
      phase = "begin"
    } else if event.momentumPhase.contains(.changed) {
      phase = "update"
    } else if event.momentumPhase.contains(.ended)
      || event.momentumPhase.contains(.cancelled)
    {
      phase = "end"
    } else {
      return
    }
    // The Flutter view under it: its controller is the next responder.
    var view = content.hitTest(content.convert(event.locationInWindow, from: nil))
    var controller: FlutterViewController?
    while let current = view {
      if let flutter = current.nextResponder as? FlutterViewController,
        flutter.view === current
      {
        controller = flutter
        break
      }
      view = current.superview
    }
    guard let controller else { return }
    let flutterView = controller.view
    let point = flutterView.convert(event.locationInWindow, from: nil)
    let y = flutterView.isFlipped ? point.y : flutterView.bounds.height - point.y
    channel.invokeMethod(
      "momentum",
      arguments: [
        "view": controller.viewIdentifier,
        "phase": phase,
        "x": point.x,
        "y": y,
        "dx": event.scrollingDeltaX,
        "dy": event.scrollingDeltaY,
        "time": Int64(event.timestamp * 1_000_000),
      ]
    )
  }
}
