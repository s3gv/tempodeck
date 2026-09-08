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
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Send a shutdown signal to Dart via a method channel, then wait
    // for dispose to complete before allowing termination.
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.tempodeck.app/lifecycle",
        binaryMessenger: controller.engine.binaryMessenger
      )
      channel.invokeMethod("shutdown", arguments: nil) { _ in
        // Dart dispose completed (or timed out) — allow termination.
        sender.reply(toApplicationShouldTerminate: true)
      }
      // Safety timeout: terminate after 2 seconds regardless.
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        sender.reply(toApplicationShouldTerminate: true)
      }
    } else {
      return .terminateNow
    }
    return .terminateLater
  }
}
