import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Give the Flutter engine time to cleanly shut down SoLoud's native
  // resources and the SQLite database before the process exits. Without
  // this, the Dart VM cleanup races with FFI callback threads, causing
  // macOS to show the "TempoDeck quit unexpectedly" crash dialog.
  /// Guards `reply(toApplicationShouldTerminate:)` — whichever of the Dart
  /// callback and the safety timeout comes first wins, the other is a no-op.
  /// Replying twice for one termination request is undefined behaviour.
  private var hasRepliedToTerminate = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Send a shutdown signal to Dart via a method channel, then wait
    // for dispose to complete before allowing termination.
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.tempodeck.app/lifecycle",
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.invokeMethod("shutdown", arguments: nil) { [weak self] _ in
        // Dart dispose completed — allow termination.
        self?.replyToTerminateOnce(sender)
      }
      // Safety timeout: terminate after 2 seconds regardless.
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.replyToTerminateOnce(sender)
      }
    } else {
      return .terminateNow
    }
    return .terminateLater
  }

  /// Both callers run on the main thread, so the flag needs no extra locking.
  private func replyToTerminateOnce(_ sender: NSApplication) {
    guard !hasRepliedToTerminate else { return }
    hasRepliedToTerminate = true
    sender.reply(toApplicationShouldTerminate: true)
  }
}
